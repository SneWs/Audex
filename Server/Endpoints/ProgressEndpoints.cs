using System.Security.Claims;
using Grenis.AudioBooks.Server.Database;
using Grenis.AudioBooks.Server.Database.Tables;
using Microsoft.EntityFrameworkCore;

namespace Grenis.AudioBooks.Server.Endpoints;

public static class ProgressEndpoints
{
    public static void MapProgressEndpoints(this IEndpointRouteBuilder app)
    {
        var progress = app.MapGroup("").WithTags("Progress");

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
    }
}
