using System.Security.Claims;

namespace Client;
public static class ClaimsPrincipalExtensions{
    public static string? FindFirstValue(this ClaimsPrincipal c,string type){return c.FindFirst(type)?.Value;}
}
