using System.Security.Claims;
using Grenis.AudioBooks.Server.Database;
using Microsoft.EntityFrameworkCore;

namespace Grenis.AudioBooks.Server.Endpoints;

public static class AccountEndpoints
{
    public static void MapAccountEndpoints(this IEndpointRouteBuilder app)
    {
        var account = app.MapGroup("").WithTags("Account");

        account.MapGet("/api/account", async (AppDbContext db, ClaimsPrincipal principal) =>
        {
            var userId = principal.GetUserId();
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
            var userId = principal.GetUserId();
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

        account.MapPut("/api/account/email", async (ChangeEmailRequest req, AppDbContext db, ClaimsPrincipal principal, TokenGenerator tokenGenerator) =>
        {
            if (string.IsNullOrWhiteSpace(req.NewEmail))
                return Results.BadRequest(new MessageResponse("Email is required."));

            var userId = principal.GetUserId();
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
            return Results.Ok(new EmailChangeResponse(tokenGenerator.GenerateToken(user), user.Email));
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

            var userId = principal.GetUserId();
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
    }
}
