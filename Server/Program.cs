using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Server;

var builder = WebApplication.CreateBuilder(args);

if (string.IsNullOrEmpty(builder.Configuration["Jwt:Secret"])) throw new Exception("JWT secret missing");

builder.Services.AddDbContext<AppDbContext>(opt =>
    opt.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

var settings = builder.Configuration.GetSection("AudiobookSettings").Get<AudiobookSettings>()
    ?? throw new Exception("AudiobookSettings missing");
builder.Services.AddSingleton(Options.Create(settings));

var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Secret"]!));
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = false,
            ValidateAudience = false,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = key
        };
    });
builder.Services.AddAuthorization();

builder.Services.AddScoped<IAudioIndexer, AudioIndexer>();
builder.Services.AddHostedService<AudioIndexBackgroundService>();

builder.Services.AddCors(options =>
    options.AddDefaultPolicy(p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
}

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();

app.MapPost("/api/register", async (LoginRequest req, AppDbContext db) =>
{
    if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Password))
        return Results.BadRequest(new { message = "Email and password are required." });

    if (await db.Users.AnyAsync(u => u.Email == req.Email))
        return Results.Conflict(new { message = "An account with this email already exists." });

    var user = new User
    {
        Email = req.Email,
        PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password)
    };
    db.Users.Add(user);
    await db.SaveChangesAsync();

    return Results.Ok(new { Token = GenerateToken(user) });
});

app.MapPost("/api/login", async (LoginRequest req, AppDbContext db) =>
{
    var user = await db.Users.FirstOrDefaultAsync(u => u.Email == req.Email);
    if (user is null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
        return Results.Unauthorized();

    return Results.Ok(new { Token = GenerateToken(user) });
});

app.MapGet("/api/books", async (AppDbContext db, ClaimsPrincipal principal) =>
{
    var userId = GetUserId(principal);
    var books = await db.Books.AsNoTracking()
        .Include(b => b.Genres)
        .OrderBy(b => b.Title)
        .ToListAsync();

    var progress = await db.Progress.AsNoTracking()
        .Where(p => p.UserId == userId)
        .ToListAsync();
    var progById = progress.ToDictionary(p => p.BookId);

    var progressedIds = progById.Keys.ToList();
    var chaptersByBook = (await db.Chapters.AsNoTracking()
            .Where(c => progressedIds.Contains(c.BookId))
            .ToListAsync())
        .GroupBy(c => c.BookId)
        .ToDictionary(g => g.Key,
            g => g.OrderBy(c => c.TrackNumber).ThenBy(c => c.FilePath).ToList());

    var result = books.Select(b =>
    {
        int progressSec = 0;
        var completed = false;
        DateTime? lastPlayed = null;
        int? resumeChapterId = null;
        var resumePos = 0;

        if (progById.TryGetValue(b.Id, out var p))
        {
            lastPlayed = p.UpdatedAt;
            resumeChapterId = p.ChapterId;
            resumePos = p.PositionSec;
            if (chaptersByBook.TryGetValue(b.Id, out var chs))
                (progressSec, completed) = ComputeProgress(chs, p);
        }

        return new BookDto
        {
            Id = b.Id,
            Title = b.Title,
            Author = b.Author,
            DurationSec = b.DurationSec,
            ChapterCount = b.ChapterCount,
            HasCover = b.HasCover,
            Description = b.Description,
            AddedAt = b.AddedAt,
            ProgressSec = progressSec,
            IsCompleted = completed,
            LastPlayedAt = lastPlayed,
            ResumeChapterId = resumeChapterId,
            ResumePositionSec = resumePos,
            Genres = b.Genres.Select(g => g.Name).OrderBy(n => n).ToList()
        };
    }).ToList();

    return Results.Ok(result);
}).RequireAuthorization();

app.MapGet("/api/genres", async (AppDbContext db) =>
    await db.Genres
        .Select(g => new GenreDto { Name = g.Name, Count = g.Books.Count })
        .Where(g => g.Count > 0)
        .OrderByDescending(g => g.Count).ThenBy(g => g.Name)
        .ToListAsync())
    .RequireAuthorization();

app.MapGet("/api/books/{id:int}", async (int id, AppDbContext db, ClaimsPrincipal principal) =>
{
    var b = await db.Books
        .Include(x => x.Chapters)
        .Include(x => x.Genres)
        .FirstOrDefaultAsync(x => x.Id == id);
    if (b is null) return Results.NotFound();

    var orderedChapters = b.Chapters
        .OrderBy(c => c.TrackNumber).ThenBy(c => c.FilePath)
        .ToList();

    var userId = GetUserId(principal);
    var p = await db.Progress.AsNoTracking()
        .FirstOrDefaultAsync(x => x.UserId == userId && x.BookId == id);

    var progressSec = 0;
    var completed = false;
    if (p is not null)
        (progressSec, completed) = ComputeProgress(orderedChapters, p);

    return Results.Ok(new BookDetailDto
    {
        Id = b.Id,
        Title = b.Title,
        Author = b.Author,
        DurationSec = b.DurationSec,
        ChapterCount = b.ChapterCount,
        HasCover = b.HasCover,
        Description = b.Description,
        AddedAt = b.AddedAt,
        ProgressSec = progressSec,
        IsCompleted = completed,
        LastPlayedAt = p?.UpdatedAt,
        ResumeChapterId = p?.ChapterId,
        ResumePositionSec = p?.PositionSec ?? 0,
        Genres = b.Genres.Select(g => g.Name).OrderBy(n => n).ToList(),
        Chapters = orderedChapters
            .Select(c => new ChapterDto
            {
                Id = c.Id,
                Title = c.Title,
                DurationSec = c.DurationSec,
                TrackNumber = c.TrackNumber
            })
            .ToList()
    });
}).RequireAuthorization();

app.MapPost("/api/books/rescan", async (IAudioIndexer indexer, AppDbContext db, CancellationToken ct) =>
{
    await indexer.InitialScanAsync(ct);
    var count = await db.Books.CountAsync(ct);
    return Results.Ok(new { count });
}).RequireAuthorization();

app.MapGet("/api/books/{id:int}/cover", async (int id, AppDbContext db, IOptions<AudiobookSettings> opt) =>
{
    var chapter = await db.Chapters
        .Where(c => c.BookId == id)
        .OrderBy(c => c.TrackNumber)
        .FirstOrDefaultAsync();
    if (chapter is null) return Results.NotFound();

    var path = Path.Combine(opt.Value.LibraryPath, chapter.FilePath);
    if (!File.Exists(path)) return Results.NotFound();

    try
    {
        using var tf = TagLib.File.Create(path);
        var pic = tf.Tag.Pictures?.FirstOrDefault();
        if (pic is null || pic.Data.Count == 0) return Results.NotFound();
        var mime = string.IsNullOrEmpty(pic.MimeType) ? "image/jpeg" : pic.MimeType;
        return Results.File(pic.Data.Data, mime);
    }
    catch
    {
        return Results.NotFound();
    }
});

app.MapGet("/api/chapters/{id:int}/audio", async (int id, AppDbContext db, IOptions<AudiobookSettings> opt) =>
{
    var chapter = await db.Chapters.FindAsync(id);
    if (chapter is null) return Results.NotFound();
    var path = Path.Combine(opt.Value.LibraryPath, chapter.FilePath);
    if (!File.Exists(path)) return Results.NotFound();
    return Results.File(path, ContentTypeFor(path), enableRangeProcessing: true);
});

app.MapPost("/api/users/{userId:int}/progress", async (int userId, ProgressDto dto, AppDbContext db) =>
{
    var progress = await db.Progress.FirstOrDefaultAsync(p => p.UserId == userId && p.BookId == dto.BookId);
    if (progress is null)
    {
        progress = new Progress { UserId = userId, BookId = dto.BookId, ChapterId = dto.ChapterId, PositionSec = dto.PositionSec, UpdatedAt = DateTime.UtcNow };
        db.Progress.Add(progress);
    }
    else
    {
        progress.ChapterId = dto.ChapterId;
        progress.PositionSec = dto.PositionSec;
        progress.UpdatedAt = DateTime.UtcNow;
    }
    await db.SaveChangesAsync();
    return Results.Ok();
}).RequireAuthorization();

app.Run();

static int GetUserId(ClaimsPrincipal principal) =>
    int.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : 0;

static (int ProgressSec, bool Completed) ComputeProgress(List<Chapter> orderedChapters, Progress p)
{
    var idx = orderedChapters.FindIndex(c => c.Id == p.ChapterId);
    if (idx < 0) return (0, false);

    var before = orderedChapters.Take(idx).Sum(c => c.DurationSec);
    var overall = before + p.PositionSec;

    var currentDuration = orderedChapters[idx].DurationSec;
    var completed = idx == orderedChapters.Count - 1
        && currentDuration > 0
        && p.PositionSec >= currentDuration - 20;

    return (overall, completed);
}

static string ContentTypeFor(string path) => Path.GetExtension(path).ToLowerInvariant() switch
{
    ".mp3" => "audio/mpeg",
    ".m4a" or ".m4b" => "audio/mp4",
    ".aac" => "audio/aac",
    ".ogg" => "audio/ogg",
    ".flac" => "audio/flac",
    ".wav" => "audio/wav",
    _ => "application/octet-stream"
};

string GenerateToken(User user)
{
    var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
    var claims = new[]
    {
        new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
        new Claim(ClaimTypes.Email, user.Email)
    };
    var jwt = new JwtSecurityToken(
        claims: claims,
        expires: DateTime.UtcNow.AddDays(7),
        signingCredentials: creds);
    return new JwtSecurityTokenHandler().WriteToken(jwt);
}
