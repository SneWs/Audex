using Grenis.AudioBooks.Server.Database;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Grenis.AudioBooks.Server.Endpoints;

public static class ChapterEndpoints
{
    public static void MapChapterEndpoints(this IEndpointRouteBuilder app)
    {
        var chapters = app.MapGroup("").WithTags("Chapters");

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

        chapters.MapGet("/api/chapters/{id:int}/download", async (int id, AppDbContext db, IOptions<AudiobookSettings> opt) =>
        {
            var chapter = await db.Chapters.FindAsync(id);
            if (chapter is null) return Results.NotFound();

            var path = Path.Combine(opt.Value.LibraryPath, chapter.FilePath);
            if (!File.Exists(path)) return Results.NotFound();

            return Results.File(
                path,
                ContentTypeFor(path),
                fileDownloadName: Path.GetFileName(path),
                enableRangeProcessing: true);
        })
        .RequireAuthorization()
        .WithSummary("Download a chapter audio file (supports range requests and resumable downloads)")
        .Produces(StatusCodes.Status200OK, contentType: "application/octet-stream")
        .Produces(StatusCodes.Status404NotFound);
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
}
