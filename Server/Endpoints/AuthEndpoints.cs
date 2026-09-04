using System.Security.Claims;
using Grenis.AudioBooks.Server.Database;
using Grenis.AudioBooks.Server.Database.Tables;
using Microsoft.EntityFrameworkCore;

namespace Grenis.AudioBooks.Server.Endpoints;

public static class AuthEndpoints
{
    public static void MapAuthEndpoints(this IEndpointRouteBuilder app)
    {
        var auth = app.MapGroup("").WithTags("Authentication");

        auth.MapPost("/api/register", async (LoginRequest req, AppDbContext db, TokenGenerator tokenGenerator) =>
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

            return Results.Ok(new AuthResponse(tokenGenerator.GenerateToken(user)));
        })
        .WithSummary("Register a new account")
        .Produces<AuthResponse>()
        .Produces<MessageResponse>(StatusCodes.Status400BadRequest)
        .Produces<MessageResponse>(StatusCodes.Status409Conflict);

        auth.MapPost("/api/login", async (LoginRequest req, AppDbContext db, TokenGenerator tokenGenerator) =>
        {
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email == req.Email);
            if (user is null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
                return Results.Unauthorized();

            return Results.Ok(new AuthResponse(tokenGenerator.GenerateToken(user)));
        })
        .WithSummary("Sign in and obtain a JWT")
        .Produces<AuthResponse>()
        .Produces(StatusCodes.Status401Unauthorized);

        auth.MapPost("/api/refresh", async (AppDbContext db, ClaimsPrincipal principal, TokenGenerator tokenGenerator) =>
        {
            var userId = principal.GetUserId();
            var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId);
            if (user is null) return Results.Unauthorized();

            return Results.Ok(new AuthResponse(tokenGenerator.GenerateToken(user)));
        })
        .RequireAuthorization()
        .WithSummary("Refresh the current JWT")
        .Produces<AuthResponse>()
        .Produces(StatusCodes.Status401Unauthorized);
    }
}
