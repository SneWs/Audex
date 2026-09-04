using Grenis.AudioBooks.Server.Database;
using Microsoft.EntityFrameworkCore;

namespace Grenis.AudioBooks.Server.Endpoints;

public static class GenresEndpoints
{
    public static void MapGenresEndpoints(this IEndpointRouteBuilder app)
    {
        var genres = app.MapGroup("").WithTags("Genres");

        genres.MapGet("/api/genres", async (AppDbContext db) =>
                await db.Genres
                    .Select(g => new GenreDto { Name = g.Name, Count = g.Books.Count })
                    .Where(g => g.Count > 0)
                    .OrderByDescending(g => g.Count).ThenBy(g => g.Name)
                    .ToListAsync())
            .RequireAuthorization()
            .WithSummary("List genres with book counts")
            .Produces<List<GenreDto>>();
    }
}
