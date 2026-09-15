using System.Security.Claims;
using Grenis.AudioBooks.Server.Database;
using Grenis.AudioBooks.Server.Database.Tables;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Grenis.AudioBooks.Server.Endpoints;

public static class BooksEndpoints
{
    public static void MapBooksEndpoints(this IEndpointRouteBuilder app)
    {
        var books = app.MapGroup("").WithTags("Books");

        books.MapGet("/api/books", async (AppDbContext db, ClaimsPrincipal principal) =>
        {
            var userId = principal.GetUserId();
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
                    Title = string.IsNullOrWhiteSpace(b.CustomTitle) ? b.Title : b.CustomTitle,
                    CustomTitle = b.CustomTitle,
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

            var userId = principal.GetUserId();
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
                Title = string.IsNullOrWhiteSpace(b.CustomTitle) ? b.Title : b.CustomTitle,
                CustomTitle = b.CustomTitle,
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
                        TrackNumber = c.TrackNumber,
                        AudioUrl = $"/api/chapters/{c.Id}/audio",
                        DownloadUrl = $"/api/chapters/{c.Id}/download"
                    })
                    .ToList()
            });
        })
        .RequireAuthorization()
        .WithSummary("Get a single audiobook with chapters, progress and favorite state")
        .Produces<BookDetailDto>()
        .Produces(StatusCodes.Status404NotFound);

        books.MapPut("/api/books/{id:int}/custom-title", async (int id, BookCustomTitleRequest req, AppDbContext db) =>
        {
            var book = await db.Books.FirstOrDefaultAsync(b => b.Id == id);
            if (book == null) return Results.NotFound();

            book.CustomTitle = string.IsNullOrWhiteSpace(req.CustomTitle) ? null : req.CustomTitle.Trim();
            await db.SaveChangesAsync();

            return Results.Ok(new MessageResponse("Custom title updated."));
        })
        .RequireAuthorization()
        .WithSummary("Set or clear a user-defined custom title for a book")
        .Accepts<BookCustomTitleRequest>("application/json")
        .Produces<MessageResponse>()
        .Produces(StatusCodes.Status404NotFound);

        books.MapPost("/api/books/rescan", (IServiceProvider sp) =>
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

        books.MapPut("/api/books/{id:int}/complete", async (int id, AppDbContext db, ClaimsPrincipal principal) =>
        {
            var userId = principal.GetUserId();
            var book = await db.Books
                .Include(b => b.Chapters)
                .FirstOrDefaultAsync(b => b.Id == id);
            if (book is null) return Results.NotFound();

            var lastChapter = book.Chapters.OrderBy(c => c.TrackNumber).ThenBy(c => c.FilePath).LastOrDefault();
            if (lastChapter is null) return Results.BadRequest("Book has no chapters.");

            var progress = await db.Progress.FirstOrDefaultAsync(p => p.UserId == userId && p.BookId == id);
            if (progress is null)
            {
                progress = new Progress
                {
                    UserId = userId,
                    BookId = id,
                    ChapterId = lastChapter.Id,
                    PositionSec = lastChapter.DurationSec,
                    UpdatedAt = DateTime.UtcNow
                };
                db.Progress.Add(progress);
            }
            else
            {
                progress.ChapterId = lastChapter.Id;
                progress.PositionSec = lastChapter.DurationSec;
                progress.UpdatedAt = DateTime.UtcNow;
            }
            await db.SaveChangesAsync();
            return Results.Ok(new MessageResponse("Book marked as complete."));
        })
        .RequireAuthorization()
        .WithSummary("Mark an audiobook as complete")
        .Produces<MessageResponse>()
        .Produces(StatusCodes.Status404NotFound);
    }

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
}
