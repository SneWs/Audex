using Microsoft.Extensions.Options;

namespace Grenis.AudioBooks.Server;

public class AudioIndexBackgroundService : BackgroundService
{
    private static readonly string[] AudioExtensions =
        { ".mp3", ".m4a", ".m4b", ".aac", ".ogg", ".flac", ".wav" };

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly string _rootPath;
    private readonly ILogger<AudioIndexBackgroundService> _logger;

    public AudioIndexBackgroundService(
        IServiceScopeFactory scopeFactory,
        IOptions<AudiobookSettings> options,
        ILogger<AudioIndexBackgroundService> logger)
    {
        _scopeFactory = scopeFactory;
        _rootPath = options.Value.LibraryPath;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!Directory.Exists(_rootPath))
        {
            _logger.LogWarning("Audio library path {Path} does not exist. Indexer idle.", _rootPath);
            return;
        }

        using (var scope = _scopeFactory.CreateScope())
        {
            var indexer = scope.ServiceProvider.GetRequiredService<IAudioIndexer>();
            await indexer.InitialScanAsync(stoppingToken);
        }

        var watcher = new FileSystemWatcher(_rootPath) { IncludeSubdirectories = true };
        watcher.NotifyFilter = NotifyFilters.FileName | NotifyFilters.Size | NotifyFilters.LastWrite | NotifyFilters.DirectoryName;
        watcher.Created += async (_, e) => await ReindexFolderOf(e.FullPath, stoppingToken);
        watcher.Changed += async (_, e) => await ReindexFolderOf(e.FullPath, stoppingToken);
        watcher.Deleted += async (_, e) => await HandleDelete(e.FullPath, stoppingToken);
        watcher.Renamed += async (_, e) => await HandleRename(e.OldFullPath, e.FullPath, stoppingToken);
        watcher.EnableRaisingEvents = true;

        _logger.LogInformation("Audio indexer started.");
        try
        {
            await Task.Delay(Timeout.Infinite, stoppingToken).ConfigureAwait(false);
        }
        catch (TaskCanceledException)
        {
        }
        finally
        {
            watcher.Dispose();
        }
    }

    private async Task ReindexFolderOf(string changedPath, CancellationToken ct)
    {
        var ext = Path.GetExtension(changedPath).ToLowerInvariant();
        // React to audio files and directory-level changes.
        if (!string.IsNullOrEmpty(ext) && !AudioExtensions.Contains(ext)) return;

        var folder = Directory.Exists(changedPath) ? changedPath : Path.GetDirectoryName(changedPath);
        if (string.IsNullOrEmpty(folder)) return;

        try
        {
            using var scope = _scopeFactory.CreateScope();
            var indexer = scope.ServiceProvider.GetRequiredService<IAudioIndexer>();
            await indexer.IndexFolderAsync(folder, ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to reindex folder {Folder}", folder);
        }
    }

    private async Task HandleRename(string oldPath, string newPath, CancellationToken ct)
    {
        // Directory renames must always be handled (identity migration); for files only
        // react when audio is involved.
        var newIsDir = Directory.Exists(newPath);
        if (!newIsDir)
        {
            var ext = Path.GetExtension(newPath).ToLowerInvariant();
            if (!string.IsNullOrEmpty(ext) && !AudioExtensions.Contains(ext)) return;
        }

        try
        {
            using var scope = _scopeFactory.CreateScope();
            var indexer = scope.ServiceProvider.GetRequiredService<IAudioIndexer>();
            await indexer.HandleRenameAsync(oldPath, newPath, ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to handle rename {Old} -> {New}", oldPath, newPath);
        }
    }

    private async Task HandleDelete(string deletedPath, CancellationToken ct)
    {
        var ext = Path.GetExtension(deletedPath).ToLowerInvariant();
        // A deleted directory has no extension; a deleted file must be audio to matter.
        if (!string.IsNullOrEmpty(ext) && !AudioExtensions.Contains(ext)) return;

        try
        {
            using var scope = _scopeFactory.CreateScope();
            var indexer = scope.ServiceProvider.GetRequiredService<IAudioIndexer>();
            await indexer.HandleDeleteAsync(deletedPath, ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to handle delete {Path}", deletedPath);
        }
    }
}