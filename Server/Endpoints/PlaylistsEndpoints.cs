using System.Security.Claims;
using Grenis.AudioBooks.Core;
using Grenis.AudioBooks.Server.Database;
using Grenis.AudioBooks.Server.Database.Tables;
using Microsoft.EntityFrameworkCore;

namespace Grenis.AudioBooks.Server.Endpoints;

public static class PlaylistsEndpoints
{
    public static void MapPlaylistsEndpoints(this IEndpointRouteBuilder app)
    {
        var playlists = app.MapGroup("/api/playlists").WithTags("Playlists").RequireAuthorization();

        playlists.MapGet("", async (AppDbContext db, ClaimsPrincipal principal) =>
        {
            var userId = principal.GetUserId();
            var entries = await db.Playlists.AsNoTracking()
                .Where(p => p.UserId == userId)
                .Include(p => p.Books).ThenInclude(pb => pb.Book).ThenInclude(b => b.Genres)
                .OrderBy(p => p.Name)
                .ToListAsync();

            return Results.Ok(await ToDtosAsync(entries, userId, db));
        })
        .WithSummary("List the caller's playlists with books in playlist order")
        .Produces<List<PlaylistDto>>();

        playlists.MapGet("/{id:int}", async (int id, AppDbContext db, ClaimsPrincipal principal) =>
        {
            var userId = principal.GetUserId();
            var playlist = await db.Playlists.AsNoTracking()
                .Where(p => p.Id == id && p.UserId == userId)
                .Include(p => p.Books).ThenInclude(pb => pb.Book).ThenInclude(b => b.Genres)
                .SingleOrDefaultAsync();
            if (playlist is null) return Results.NotFound();

            return Results.Ok((await ToDtosAsync([playlist], userId, db)).Single());
        })
        .WithSummary("Get one playlist with books in playlist order")
        .Produces<PlaylistDto>()
        .Produces(StatusCodes.Status404NotFound);

        playlists.MapPost("", async (PlaylistRequest request, AppDbContext db, ClaimsPrincipal principal) =>
        {
            var userId = principal.GetUserId();
            var validation = await ValidateRequestAsync(request, userId, null, db);
            if (validation is not null) return validation;

            var now = DateTime.UtcNow;
            var playlist = new Playlist
            {
                UserId = userId,
                Name = request.Name.Trim(),
                CreatedAt = now,
                UpdatedAt = now,
                Books = request.BookIds.Select((bookId, position) => new PlaylistBook
                {
                    BookId = bookId,
                    Position = position
                }).ToList()
            };
            db.Playlists.Add(playlist);
            await db.SaveChangesAsync();

            return Results.Created($"/api/playlists/{playlist.Id}", new PlaylistDto
            {
                Id = playlist.Id,
                Name = playlist.Name,
                CreatedAt = playlist.CreatedAt,
                UpdatedAt = playlist.UpdatedAt
            });
        })
        .WithSummary("Create a playlist")
        .Accepts<PlaylistRequest>("application/json")
        .Produces<PlaylistDto>(StatusCodes.Status201Created)
        .Produces<MessageResponse>(StatusCodes.Status400BadRequest);

        playlists.MapPut("/{id:int}", async (int id, PlaylistRequest request, AppDbContext db, ClaimsPrincipal principal) =>
        {
            var validation = await ValidateRequestAsync(request, principal.GetUserId(), id, db);
            if (validation is not null) return validation;

            var playlist = await db.Playlists
                .Include(p => p.Books)
                .SingleOrDefaultAsync(p => p.Id == id && p.UserId == principal.GetUserId());
            if (playlist is null) return Results.NotFound();

            db.PlaylistBooks.RemoveRange(playlist.Books);
            playlist.Name = request.Name.Trim();
            playlist.UpdatedAt = DateTime.UtcNow;
            playlist.Books = request.BookIds.Select((bookId, position) => new PlaylistBook
            {
                PlaylistId = playlist.Id,
                BookId = bookId,
                Position = position
            }).ToList();
            await db.SaveChangesAsync();

            return Results.Ok(new PlaylistDto
            {
                Id = playlist.Id,
                Name = playlist.Name,
                CreatedAt = playlist.CreatedAt,
                UpdatedAt = playlist.UpdatedAt
            });
        })
        .WithSummary("Replace a playlist's name and ordered books")
        .Accepts<PlaylistRequest>("application/json")
        .Produces<PlaylistDto>()
        .Produces<MessageResponse>(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status404NotFound);

        playlists.MapDelete("/{id:int}", async (int id, AppDbContext db, ClaimsPrincipal principal) =>
        {
            var playlist = await db.Playlists
                .SingleOrDefaultAsync(p => p.Id == id && p.UserId == principal.GetUserId());
            if (playlist is null) return Results.NotFound();

            db.Playlists.Remove(playlist);
            await db.SaveChangesAsync();
            return Results.NoContent();
        })
        .WithSummary("Delete a playlist")
        .Produces(StatusCodes.Status204NoContent)
        .Produces(StatusCodes.Status404NotFound);
    }

    private static async Task<IResult?> ValidateRequestAsync(PlaylistRequest request, int userId, int? playlistId, AppDbContext db)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
            return Results.BadRequest(new MessageResponse("A playlist name is required."));
        if (request.Name.Trim().Length > 200)
            return Results.BadRequest(new MessageResponse("A playlist name cannot exceed 200 characters."));
        if (request.BookIds is null)
            return Results.BadRequest(new MessageResponse("The playlist books are required."));
        if (request.BookIds.Distinct().Count() != request.BookIds.Count)
            return Results.BadRequest(new MessageResponse("A playlist cannot contain the same book more than once."));
        if (await db.Playlists.AnyAsync(p => p.UserId == userId && p.Name == request.Name.Trim() && p.Id != playlistId))
            return Results.BadRequest(new MessageResponse("You already have a playlist with this name."));

        var foundBookCount = await db.Books.CountAsync(b => request.BookIds.Contains(b.Id));
        return foundBookCount == request.BookIds.Count
            ? null
            : Results.BadRequest(new MessageResponse("One or more selected books no longer exist."));
    }

    private static async Task<List<PlaylistDto>> ToDtosAsync(IEnumerable<Playlist> playlists, int userId, AppDbContext db)
    {
        var playlistList = playlists.ToList();
        var bookIds = playlistList.SelectMany(p => p.Books).Select(pb => pb.BookId).Distinct().ToList();
        var progressByBookId = await db.Progress.AsNoTracking()
            .Where(p => p.UserId == userId && bookIds.Contains(p.BookId))
            .ToDictionaryAsync(p => p.BookId);
        var favoriteBookIds = (await db.Favorites.AsNoTracking()
            .Where(f => f.UserId == userId && bookIds.Contains(f.BookId))
            .Select(f => f.BookId)
            .ToListAsync()).ToHashSet();

        return playlistList.Select(playlist => new PlaylistDto
        {
            Id = playlist.Id,
            Name = playlist.Name,
            CreatedAt = playlist.CreatedAt,
            UpdatedAt = playlist.UpdatedAt,
            Books = playlist.Books.OrderBy(pb => pb.Position).Select(pb =>
            {
                var book = pb.Book;
                progressByBookId.TryGetValue(book.Id, out var progress);
                return new BookDto
                {
                    Id = book.Id,
                    Title = string.IsNullOrWhiteSpace(book.CustomTitle) ? book.Title : book.CustomTitle,
                    CustomTitle = book.CustomTitle,
                    Subtitle = book.Subtitle,
                    Author = book.Author,
                    Year = book.Year,
                    ReadBy = book.ReadBy,
                    DurationSec = book.DurationSec,
                    ChapterCount = book.ChapterCount,
                    HasCover = book.HasCover,
                    Description = book.Description,
                    Publisher = book.Publisher,
                    Language = book.Language,
                    Isbn10 = book.Isbn10,
                    Isbn13 = book.Isbn13,
                    PageCount = book.PageCount,
                    Rating = book.Rating,
                    RatingCount = book.RatingCount,
                    OpenLibraryUrl = book.OpenLibraryUrl,
                    AddedAt = book.AddedAt,
                    IsFavorite = favoriteBookIds.Contains(book.Id),
                    LastPlayedAt = progress?.UpdatedAt,
                    ResumeChapterId = progress?.ChapterId,
                    ResumePositionSec = progress?.PositionSec ?? 0,
                    Genres = book.Genres.Select(g => g.Name).OrderBy(name => name).ToList()
                };
            }).ToList()
        }).ToList();
    }
}
