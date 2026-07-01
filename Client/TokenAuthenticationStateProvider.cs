using System.Security.Claims;
using Blazored.LocalStorage;
using Microsoft.AspNetCore.Components.Authorization;

public class TokenAuthenticationStateProvider : AuthenticationStateProvider
{
    private readonly ILocalStorageService _storage;
    public TokenAuthenticationStateProvider(ILocalStorageService storage)
    {
        _storage = storage;
    }
    public override async Task<AuthenticationState> GetAuthenticationStateAsync()
    {
        var token = await _storage.GetItemAsync<string>("token");
        ClaimsPrincipal user;
        if (string.IsNullOrWhiteSpace(token))
            user = new ClaimsPrincipal(new ClaimsIdentity());
        else
        {
            var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
            var jwt = handler.ReadJwtToken(token);
            var identity = new ClaimsIdentity(jwt.Claims, "jwt");
            user = new ClaimsPrincipal(identity);
        }
        return new AuthenticationState(user);
    }
    public async Task MarkUserAsAuthenticated(string token)
    {
        await _storage.SetItemAsync("token", token);
        NotifyAuthenticationStateChanged(GetAuthenticationStateAsync());
    }
    public async Task MarkUserAsLoggedOut()
    {
        await _storage.RemoveItemAsync("token");
        NotifyAuthenticationStateChanged(Task.FromResult(new AuthenticationState(new ClaimsPrincipal(new ClaimsIdentity()))));
    }
}
