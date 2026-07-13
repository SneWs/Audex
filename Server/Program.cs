using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Grenis.AudioBooks.Core;
using Grenis.AudioBooks.Server;
using Grenis.AudioBooks.Server.Database;
using Grenis.AudioBooks.Server.Database.Tables;
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

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new Microsoft.OpenApi.OpenApiInfo
    {
        Title = "Audiobook Library API",
        Version = "v1",
        Description = "REST API for the Audiobook Library: browse books, stream chapters, track progress, manage favorites and account."
    });

    const string schemeId = "Bearer";
    options.AddSecurityDefinition(schemeId, new Microsoft.OpenApi.OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = Microsoft.OpenApi.SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = Microsoft.OpenApi.ParameterLocation.Header,
        Description = "Enter the JWT returned by /api/login or /api/register (no 'Bearer' prefix needed)."
    });
    options.AddSecurityRequirement(doc => new Microsoft.OpenApi.OpenApiSecurityRequirement
    {
        { new Microsoft.OpenApi.OpenApiSecuritySchemeReference(schemeId, doc, null), new List<string>() }
    });
});

builder.Services.AddHttpClient<BookMetadataLookup>(client =>
{
    client.DefaultRequestHeaders.Add("User-Agent", "Audex/1.0");
    client.Timeout = TimeSpan.FromSeconds(15);
});
builder.Services.AddSignalR();
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

app.MapHub<LibraryHub>("/hubs/library");

app.UseSwagger();
app.UseSwaggerUI(options =>
{
    options.SwaggerEndpoint("/swagger/v1/swagger.json", "Audiobook Library API v1");
    options.DocumentTitle = "Audiobook Library API";
});

var auth = app.MapGroup("").WithTags("Authentication");
var books = app.MapGroup("").WithTags("Books");
var genres = app.MapGroup("").WithTags("Genres");
var chapters = app.MapGroup("").WithTags("Chapters");
var progress = app.MapGroup("").WithTags("Progress");
var favorites = app.MapGroup("").WithTags("Favorites");
var account = app.MapGroup("").WithTags("Account");

auth.MapPost("/api/register", async (LoginRequest req, AppDbContext db) =>
{
    if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Password))
        return Results.BadRequest(new MessageResponse("Email and password are required."));

    if (await db.Users.AnyAsync(u => u.Email == req.Email))
        return Results.Conflict(new MessageResponse("An account with this email already exists."));

    var user = new User
    {
        Email = req.Email,
        PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password)
    };
    db.Users.Add(user);
    await db.SaveChangesAsync();

    return Results.Ok(new AuthResponse(GenerateToken(user)));
})
.WithSummary("Register a new account")
.Produces<AuthResponse>()
.Produces<MessageResponse>(StatusCodes.Status400BadRequest)
.Produces<MessageResponse>(StatusCodes.Status409Conflict);

auth.MapPost("/api/login", async (LoginRequest req, AppDbContext db) =>
{
    var user = await db.Users.FirstOrDefaultAsync(u => u.Email == req.Email);
    if (user is null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
        return Results.Unauthorized();

    return Results.Ok(new AuthResponse(GenerateToken(user)));
})
.WithSummary("Sign in and obtain a JWT")
.Produces<AuthResponse>()
.Produces(StatusCodes.Status401Unauthorized);

books.MapGet("/api/books", async (AppDbContext db, ClaimsPrincipal principal) =>
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

    var favoriteIds = (await db.Favorites.AsNoTracking()
        .Where(f => f.UserId == userId)
        .Select(f => f.BookId)
        .ToListAsync()).ToHashSet();

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
            Subtitle = b.Subtitle,
            Author = b.Author,
            Year = b.Year,
            ReadBy = b.ReadBy,
            DurationSec = b.DurationSec,
            ChapterCount = b.ChapterCount,
            HasCover = b.HasCover,
            Description = b.Description,
            Publisher = b.Publisher,
            Language = b.Language,
            Isbn10 = b.Isbn10,
            Isbn13 = b.Isbn13,
            PageCount = b.PageCount,
            Rating = b.Rating,
            RatingCount = b.RatingCount,
            GoogleBooksUrl = b.GoogleBooksUrl,
            OpenLibraryUrl = b.OpenLibraryUrl,
            AddedAt = b.AddedAt,
            ProgressSec = progressSec,
            IsCompleted = completed,
            IsFavorite = favoriteIds.Contains(b.Id),
            LastPlayedAt = lastPlayed,
            ResumeChapterId = resumeChapterId,
            ResumePositionSec = resumePos,
            Genres = b.Genres.Select(g => g.Name).OrderBy(n => n).ToList()
        };
    }).ToList();

    return Results.Ok(result);
})
.RequireAuthorization()
.WithSummary("List all audiobooks with the caller's progress and favorite state")
.Produces<List<BookDto>>();

genres.MapGet("/api/genres", async (AppDbContext db) =>
    await db.Genres
        .Select(g => new GenreDto { Name = g.Name, Count = g.Books.Count })
        .Where(g => g.Count > 0)
        .OrderByDescending(g => g.Count).ThenBy(g => g.Name)
        .ToListAsync())
    .RequireAuthorization()
    .WithSummary("List genres with book counts")
    .Produces<List<GenreDto>>();

books.MapGet("/api/books/{id:int}", async (int id, AppDbContext db, ClaimsPrincipal principal) =>
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

    var isFavorite = await db.Favorites.AsNoTracking()
        .AnyAsync(f => f.UserId == userId && f.BookId == id);

    return Results.Ok(new BookDetailDto
    {
        Id = b.Id,
        Title = b.Title,
        Subtitle = b.Subtitle,
        Author = b.Author,
        Year = b.Year,
        ReadBy = b.ReadBy,
        DurationSec = b.DurationSec,
        ChapterCount = b.ChapterCount,
        HasCover = b.HasCover,
        Description = b.Description,
        Publisher = b.Publisher,
        Language = b.Language,
        Isbn10 = b.Isbn10,
        Isbn13 = b.Isbn13,
        PageCount = b.PageCount,
        Rating = b.Rating,
        RatingCount = b.RatingCount,
        GoogleBooksUrl = b.GoogleBooksUrl,
        OpenLibraryUrl = b.OpenLibraryUrl,
        AddedAt = b.AddedAt,
        ProgressSec = progressSec,
        IsCompleted = completed,
        IsFavorite = isFavorite,
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
})
.RequireAuthorization()
.WithSummary("Get a single audiobook with chapters, progress and favorite state")
.Produces<BookDetailDto>()
.Produces(StatusCodes.Status404NotFound);

books.MapPost("/api/books/rescan", (IAudioIndexer indexer, IServiceProvider sp) =>
{
    // Run the scan in the background so the HTTP request doesn't time out.
    _ = Task.Run(async () =>
    {
        using var scope = sp.CreateScope();
        var bgIndexer = scope.ServiceProvider.GetRequiredService<IAudioIndexer>();
        var logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
        try
        {
            await bgIndexer.InitialScanAsync();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var count = await db.Books.CountAsync();
            logger.LogInformation("Background rescan completed. {Count} book(s) in library.", count);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Background rescan failed.");
        }
    });

    return Results.Ok(new RescanResponse(-1) { Message = "Rescan started in background." });
})
.RequireAuthorization()
.WithSummary("Trigger a full re-scan of the library (progress is preserved)")
.Produces<RescanResponse>();

books.MapPost("/api/books/{id:int}/rescan", async (int id, IAudioIndexer indexer) =>
{
    var found = await indexer.RescanBookAsync(id);
    if (!found)
        return Results.NotFound();

    return Results.Ok(new MessageResponse("Book re-scan completed."));
})
.RequireAuthorization()
.WithSummary("Re-scan a single audiobook folder to refresh metadata enrichment")
.Produces<MessageResponse>()
.Produces(StatusCodes.Status404NotFound);

books.MapGet("/api/books/{id:int}/cover", async (int id, AppDbContext db, IOptions<AudiobookSettings> opt, IHttpClientFactory httpFactory) =>
{
    var book = await db.Books.FindAsync(id);
    if (book is null) return Results.NotFound();

    // Try embedded cover from audio file tags first.
    var chapter = await db.Chapters
        .Where(c => c.BookId == id)
        .OrderBy(c => c.TrackNumber)
        .FirstOrDefaultAsync();

    if (chapter is not null)
    {
        var path = Path.Combine(opt.Value.LibraryPath, chapter.FilePath);
        if (File.Exists(path))
        {
            try
            {
                using var tf = TagLib.File.Create(path);
                var pic = tf.Tag.Pictures?.FirstOrDefault();
                if (pic is not null && pic.Data.Count > 0)
                {
                    var mime = string.IsNullOrEmpty(pic.MimeType) ? "image/jpeg" : pic.MimeType;
                    return Results.File(pic.Data.Data, mime);
                }
            }
            catch { /* fall through to external cover */ }
        }
    }

    // Fall back to externally fetched cover URL.
    if (!string.IsNullOrWhiteSpace(book.CoverUrl))
    {
        try
        {
            var http = httpFactory.CreateClient();
            http.DefaultRequestHeaders.Add("User-Agent", "Audex/1.0");
            var response = await http.GetAsync(book.CoverUrl);
            if (response.IsSuccessStatusCode)
            {
                var contentType = response.Content.Headers.ContentType?.MediaType ?? "image/jpeg";
                var bytes = await response.Content.ReadAsByteArrayAsync();
                return Results.File(bytes, contentType);
            }
        }
        catch { /* no external cover available */ }
    }

    return Results.NotFound();
})
.WithSummary("Get the cover image for a book (extracted from its audio tags)")
.Produces(StatusCodes.Status200OK, contentType: "image/jpeg")
.Produces(StatusCodes.Status404NotFound);

chapters.MapGet("/api/chapters/{id:int}/audio", async (int id, AppDbContext db, IOptions<AudiobookSettings> opt) =>
{
    var chapter = await db.Chapters.FindAsync(id);
    if (chapter is null) return Results.NotFound();
    var path = Path.Combine(opt.Value.LibraryPath, chapter.FilePath);
    if (!File.Exists(path)) return Results.NotFound();
    return Results.File(path, ContentTypeFor(path), enableRangeProcessing: true);
})
.WithSummary("Stream a chapter's audio file (supports range requests)")
.Produces(StatusCodes.Status200OK, contentType: "audio/mpeg")
.Produces(StatusCodes.Status404NotFound);

progress.MapPost("/api/users/{userId:int}/progress", async (int userId, ProgressDto dto, AppDbContext db) =>
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
})
.RequireAuthorization()
.WithSummary("Save listening progress for a book")
.Accepts<ProgressDto>("application/json")
.Produces(StatusCodes.Status200OK);

favorites.MapPut("/api/books/{id:int}/favorite", async (int id, AppDbContext db, ClaimsPrincipal principal) =>
{
    var userId = GetUserId(principal);
    if (!await db.Books.AnyAsync(b => b.Id == id)) return Results.NotFound();

    var exists = await db.Favorites.AnyAsync(f => f.UserId == userId && f.BookId == id);
    if (!exists)
    {
        db.Favorites.Add(new Favorite { UserId = userId, BookId = id, CreatedAt = DateTime.UtcNow });
        await db.SaveChangesAsync();
    }
    return Results.Ok(new FavoriteResponse(true));
})
.RequireAuthorization()
.WithSummary("Mark a book as a favorite")
.Produces<FavoriteResponse>()
.Produces(StatusCodes.Status404NotFound);

favorites.MapDelete("/api/books/{id:int}/favorite", async (int id, AppDbContext db, ClaimsPrincipal principal) =>
{
    var userId = GetUserId(principal);
    var fav = await db.Favorites.FirstOrDefaultAsync(f => f.UserId == userId && f.BookId == id);
    if (fav is not null)
    {
        db.Favorites.Remove(fav);
        await db.SaveChangesAsync();
    }
    return Results.Ok(new FavoriteResponse(false));
})
.RequireAuthorization()
.WithSummary("Remove a book from favorites")
.Produces<FavoriteResponse>();

account.MapGet("/api/account", async (AppDbContext db, ClaimsPrincipal principal) =>
{
    var userId = GetUserId(principal);
    var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == userId);
    return user is null
        ? Results.NotFound()
        : Results.Ok(new AccountDto(user.Id, user.Email, user.PrefersDarkMode));
})
.RequireAuthorization()
.WithSummary("Get the current account's details")
.Produces<AccountDto>()
.Produces(StatusCodes.Status404NotFound);

account.MapPut("/api/account/preferences/theme", async (ThemePreferenceRequest req, AppDbContext db, ClaimsPrincipal principal) =>
{
    var userId = GetUserId(principal);
    var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId);
    if (user is null) return Results.NotFound();

    user.PrefersDarkMode = req.IsDarkMode;
    await db.SaveChangesAsync();
    return Results.Ok(new AccountDto(user.Id, user.Email, user.PrefersDarkMode));
})
.RequireAuthorization()
.WithSummary("Save the current account's theme preference")
.Accepts<ThemePreferenceRequest>("application/json")
.Produces<AccountDto>()
.Produces(StatusCodes.Status404NotFound);

account.MapPut("/api/account/email", async (ChangeEmailRequest req, AppDbContext db, ClaimsPrincipal principal) =>
{
    if (string.IsNullOrWhiteSpace(req.NewEmail))
        return Results.BadRequest(new MessageResponse("Email is required."));

    var userId = GetUserId(principal);
    var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId);
    if (user is null) return Results.NotFound();

    if (!BCrypt.Net.BCrypt.Verify(req.CurrentPassword, user.PasswordHash))
        return Results.BadRequest(new MessageResponse("Current password is incorrect."));

    var newEmail = req.NewEmail.Trim();
    if (!string.Equals(newEmail, user.Email, StringComparison.OrdinalIgnoreCase)
        && await db.Users.AnyAsync(u => u.Email == newEmail))
        return Results.Conflict(new MessageResponse("An account with this email already exists."));

    user.Email = newEmail;
    await db.SaveChangesAsync();
    return Results.Ok(new EmailChangeResponse(GenerateToken(user), user.Email));
})
.RequireAuthorization()
.WithSummary("Change the account email (re-issues a JWT)")
.Accepts<ChangeEmailRequest>("application/json")
.Produces<EmailChangeResponse>()
.Produces<MessageResponse>(StatusCodes.Status400BadRequest)
.Produces<MessageResponse>(StatusCodes.Status409Conflict)
.Produces(StatusCodes.Status404NotFound);

account.MapPut("/api/account/password", async (ChangePasswordRequest req, AppDbContext db, ClaimsPrincipal principal) =>
{
    if (string.IsNullOrWhiteSpace(req.NewPassword) || req.NewPassword.Length < 6)
        return Results.BadRequest(new MessageResponse("New password must be at least 6 characters."));

    var userId = GetUserId(principal);
    var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId);
    if (user is null) return Results.NotFound();

    if (!BCrypt.Net.BCrypt.Verify(req.CurrentPassword, user.PasswordHash))
        return Results.BadRequest(new MessageResponse("Current password is incorrect."));

    user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.NewPassword);
    await db.SaveChangesAsync();
    return Results.Ok();
})
.RequireAuthorization()
.WithSummary("Change the account password")
.Accepts<ChangePasswordRequest>("application/json")
.Produces(StatusCodes.Status200OK)
.Produces<MessageResponse>(StatusCodes.Status400BadRequest)
.Produces(StatusCodes.Status404NotFound);

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
