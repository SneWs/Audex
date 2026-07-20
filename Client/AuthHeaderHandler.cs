using System.Net.Http.Headers;
using Blazored.LocalStorage;
using Microsoft.AspNetCore.Components;

namespace Grenis.AudioBooks.Client;

public class AuthHeaderHandler : DelegatingHandler
{
    private readonly ILocalStorageService _storage;
    private readonly TokenAuthenticationStateProvider _authenticationStateProvider;
    private readonly NavigationManager _navigation;

    public AuthHeaderHandler(
        ILocalStorageService storage,
        TokenAuthenticationStateProvider authenticationStateProvider,
        NavigationManager navigation)
    {
        _storage = storage;
        _authenticationStateProvider = authenticationStateProvider;
        _navigation = navigation;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var token = await _storage.GetItemAsync<string>("token");
        if (!string.IsNullOrWhiteSpace(token))
        {
            if (TokenAuthenticationStateProvider.IsTokenExpired(token))
            {
                await _authenticationStateProvider.MarkUserAsLoggedOut();
                _navigation.NavigateTo("/login", forceLoad: true);
            }
            else
            {
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            }
        }
        return await base.SendAsync(request, cancellationToken);
    }
}
