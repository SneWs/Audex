using System.Security.Claims;
using Blazored.LocalStorage;
using Microsoft.AspNetCore.Components.Authorization;

namespace Grenis.AudioBooks.Client;

public class TokenAuthenticationStateProvider : AuthenticationStateProvider
{
    private readonly ILocalStorageService _storage;
    private static readonly ClaimsPrincipal Anonymous = new(new ClaimsIdentity());

    public TokenAuthenticationStateProvider(ILocalStorageService storage)
    {
        _storage = storage;
    }

    public override async Task<AuthenticationState> GetAuthenticationStateAsync()
    {
        var token = await _storage.GetItemAsync<string>("token");
        if (string.IsNullOrWhiteSpace(token))
        {
            return new AuthenticationState(Anonymous);
        }

        if (TryCreatePrincipalFromToken(token, out var user))
        {
            return new AuthenticationState(user);
        }

        await _storage.RemoveItemAsync("token");
        return new AuthenticationState(Anonymous);
    }

    public static bool IsTokenExpired(string token)
    {
        try
        {
            var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
            var jwt = handler.ReadJwtToken(token);

            return jwt.ValidTo <= DateTime.UtcNow;
        }
        catch
        {
            return true;
        }
    }

    private static bool TryCreatePrincipalFromToken(string token, out ClaimsPrincipal user)
    {
        user = Anonymous;

        try
        {
            var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
            var jwt = handler.ReadJwtToken(token);

            if (jwt.ValidTo <= DateTime.UtcNow)
            {
                return false;
            }

            var identity = new ClaimsIdentity(jwt.Claims, "jwt");
            user = new ClaimsPrincipal(identity);
            return true;
        }
        catch
        {
            return false;
        }
    }

    public async Task MarkUserAsAuthenticated(string token)
    {
        await _storage.SetItemAsync("token", token);
        NotifyAuthenticationStateChanged(GetAuthenticationStateAsync());
    }

    public async Task MarkUserAsLoggedOut()
    {
        await _storage.RemoveItemAsync("token");
        NotifyAuthenticationStateChanged(Task.FromResult(new AuthenticationState(Anonymous)));
    }
}