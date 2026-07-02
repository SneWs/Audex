using System.Security.Claims;

namespace Grenis.AudioBooks.Client;
public static class ClaimsPrincipalExtensions{
    public static string? FindFirstValue(this ClaimsPrincipal c,string type){return c.FindFirst(type)?.Value;}
}
