using Microsoft.AspNetCore.SignalR;

namespace Grenis.AudioBooks.Server;

/// <summary>
/// SignalR hub for real-time library notifications.
/// Clients receive events when books are discovered, updated, or removed.
/// </summary>
public class LibraryHub : Hub<ILibraryHubClient>
{
    public override async Task OnConnectedAsync()
    {
        await base.OnConnectedAsync();
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
