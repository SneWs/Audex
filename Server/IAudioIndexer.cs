namespace Grenis.AudioBooks.Server;

public interface IAudioIndexer
{
    string RootPath { get; }
    Task InitialScanAsync(CancellationToken ct = default);
    Task<bool> RescanBookAsync(int bookId, CancellationToken ct = default);
    Task IndexFolderAsync(string folderFullPath, CancellationToken ct);
    Task HandleRenameAsync(string oldFullPath, string newFullPath, CancellationToken ct);
    Task HandleDeleteAsync(string fullPath, CancellationToken ct);
}