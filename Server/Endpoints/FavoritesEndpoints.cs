using System.Security.Claims;
using Grenis.AudioBooks.Server.Database;
using Grenis.AudioBooks.Server.Database.Tables;
using Microsoft.EntityFrameworkCore;

namespace Grenis.AudioBooks.Server.Endpoints;

public static class FavoritesEndpoints
{
    public static void MapFavoritesEndpoints(this IEndpointRouteBuilder app)
    {
        var favorites = app.MapGroup("").WithTags("Favorites");

        favorites.MapPut("/api/books/{id:int}/favorite", async (int id, AppDbContext db, ClaimsPrincipal principal) =>
        {
            var userId = principal.GetUserId();
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
            var userId = principal.GetUserId();
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
    }
}
