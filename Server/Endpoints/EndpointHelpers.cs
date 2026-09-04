using System.Security.Claims;

namespace Grenis.AudioBooks.Server.Endpoints;

public static class EndpointHelpers
{
    public static int GetUserId(this ClaimsPrincipal principal) =>
        int.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : 0;
}
