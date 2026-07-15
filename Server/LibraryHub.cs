using Microsoft.AspNetCore.SignalR;

namespace Grenis.AudioBooks.Server;

/// <summary>
/// SignalR hub for real-time library notifications.
/// Clients receive events when books are discovered, updated, or removed.
/// </summary>
public class LibraryHub : Hub<ILibraryHubClient>
{
    private readonly ILogger<LibraryHub> _logger;
    private static volatile int _totalClients;

    public LibraryHub(ILogger<LibraryHub> logger)
    {
        _logger = logger;
    }
    
    public override async Task OnConnectedAsync()
    {
        _logger.LogInformation("New websocket connection for user {User} / Connection Id: {ConnectionId}",
            Context.User!.Identity!.Name, Context.ConnectionId);

        Interlocked.Increment(ref _totalClients);
        if (_totalClients < 1)
            _totalClients = 1;
        
        _logger.LogInformation("Total connections: {ConnectionCount}",
            _totalClients);
        
        await base.OnConnectedAsync();
    }

    public override Task OnDisconnectedAsync(Exception? exception)
    {
        _logger.LogInformation("Client disconnected. {ConnectionId}", Context.ConnectionId);
        
        Interlocked.Decrement(ref _totalClients);
        if (_totalClients < 0)
            _totalClients = 0;
        
        _logger.LogInformation("Total connections: {ConnectionCount}",
            _totalClients);
        
        return base.OnDisconnectedAsync(exception);
    }
}

/// <summary>
/// Strongly-typed client interface for LibraryHub notifications.
/// </summary>
public interface ILibraryHubClient
{
    Task BookAdded(int bookId, string title);
    Task BookUpdated(int bookId, string title);
    Task BookRemoved(int bookId, string title);
    Task ScanStarted();
    Task ScanCompleted(int totalBooks);
    Task ScanProgress(string message);
}
