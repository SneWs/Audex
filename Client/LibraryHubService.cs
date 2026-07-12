using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.SignalR.Client;

namespace Grenis.AudioBooks.Client;

/// <summary>
/// Manages the SignalR connection to the library hub for real-time notifications.
/// </summary>
public sealed class LibraryHubService : IAsyncDisposable
{
    private HubConnection? _hub;
    private readonly NavigationManager _nav;

    public LibraryHubService(NavigationManager nav)
    {
        _nav = nav;
    }

    public event Action<int, string>? BookAdded;
    public event Action<int, string>? BookUpdated;
    public event Action<int, string>? BookRemoved;
    public event Action? ScanStarted;
    public event Action<int>? ScanCompleted;
    public event Action<string>? ScanProgress;

    public bool IsConnected => _hub?.State == HubConnectionState.Connected;

    public async Task StartAsync()
    {
        if (_hub is not null) return;

        _hub = new HubConnectionBuilder()
            .WithUrl(_nav.ToAbsoluteUri("/hubs/library"))
            .WithAutomaticReconnect()
            .Build();

        _hub.On<int, string>("BookAdded", (id, title) => BookAdded?.Invoke(id, title));
        _hub.On<int, string>("BookUpdated", (id, title) => BookUpdated?.Invoke(id, title));
        _hub.On<int, string>("BookRemoved", (id, title) => BookRemoved?.Invoke(id, title));
        _hub.On("ScanStarted", () => ScanStarted?.Invoke());
        _hub.On<int>("ScanCompleted", (count) => ScanCompleted?.Invoke(count));
        _hub.On<string>("ScanProgress", (msg) => ScanProgress?.Invoke(msg));

        try
        {
            await _hub.StartAsync();
        }
        catch
        {
            // Hub may not be reachable yet; automatic reconnect will handle it.
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_hub is not null)
        {
            await _hub.DisposeAsync();
            _hub = null;
        }
    }
}
