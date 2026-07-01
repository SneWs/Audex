using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Server;

public class AudioIndexer : IAudioIndexer
{
    private static readonly string[] AudioExtensions =
        { ".mp3", ".m4a", ".m4b", ".aac", ".ogg", ".flac", ".wav" };

    private readonly AppDbContext _db;
    private readonly AudiobookSettings _settings;
    private readonly ILogger<AudioIndexer> _logger;

    public string RootPath => _settings.LibraryPath;

    public AudioIndexer(
        AppDbContext db,
        Microsoft.Extensions.Options.IOptions<AudiobookSettings> options,
        ILogger<AudioIndexer> logger)
    {
        _db = db;
        _settings = options.Value;
        _logger = logger;
    }

    public async Task InitialScanAsync(CancellationToken ct = default)
    {
        if (!Directory.Exists(RootPath))
        {
            _logger.LogWarning("Library path {Path} does not exist.", RootPath);
            return;
        }

        // Every directory that directly contains at least one audio file is a book.
        var bookFolders = Directory.EnumerateDirectories(RootPath, "*", SearchOption.AllDirectories)
            .Append(RootPath)
            .Where(HasAudioFiles)
            .ToList();

        foreach (var folder in bookFolders)
        {
            ct.ThrowIfCancellationRequested();
            await IndexFolderAsync(folder, ct);
        }

        await PruneMissingBooksAsync(ct);
    }

    public async Task IndexFolderAsync(string folderFullPath, CancellationToken ct)
    {
        var relFolder = RelPath(folderFullPath);

        var files = GetAudioFiles(folderFullPath);
        if (files.Count == 0)
        {
            // Folder no longer holds audio -> drop the book if we had one.
            var stale = await _db.Books.FirstOrDefaultAsync(b => b.FolderPath == relFolder, ct);
            if (stale != null)
            {
                _db.Books.Remove(stale);
                await _db.SaveChangesAsync(ct);
                _logger.LogInformation("Removed book (no audio left): {Folder}", relFolder);
            }
            return;
        }

        var scanned = new List<ScannedChapter>();
        var author = "Unknown";
        string? description = null;
        string? album = null;
        var genreNames = new List<string>();
        var hasCover = false;
        var index = 0;

        foreach (var file in files)
        {
            ct.ThrowIfCancellationRequested();
            var meta = ReadMetadata(file);
            index++;
            scanned.Add(new ScannedChapter(
                Title: string.IsNullOrWhiteSpace(meta.Title) ? Path.GetFileNameWithoutExtension(file) : meta.Title!,
                FilePath: RelPath(file),
                DurationSec: meta.DurationSec,
                TrackNumber: meta.Track > 0 ? meta.Track : index));

            if (author == "Unknown" && !string.IsNullOrWhiteSpace(meta.Author)) author = meta.Author!;
            if (album is null && !string.IsNullOrWhiteSpace(meta.Album)) album = meta.Album;
            if (description is null && !string.IsNullOrWhiteSpace(meta.Description)) description = meta.Description;
            if (meta.HasCover) hasCover = true;
            foreach (var raw in meta.Genres)
            {
                // A single tag field may pack several genres, e.g. "Literary Fiction, Classics".
                foreach (var part in (raw ?? string.Empty).Split(new[] { ',', ';', '/', '|' },
                             StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    if (!genreNames.Contains(part, StringComparer.OrdinalIgnoreCase))
                        genreNames.Add(part);
                }
            }
        }

        scanned = scanned.OrderBy(c => c.TrackNumber).ThenBy(c => c.FilePath).ToList();

        // Prefer the Album tag as the book name; fall back to the folder name.
        var folderName = new DirectoryInfo(folderFullPath).Name;
        var title = string.IsNullOrWhiteSpace(album) ? folderName : album!;
        // Avoid showing the same text as both title and description.
        if (!string.IsNullOrWhiteSpace(description) &&
            string.Equals(description, title, StringComparison.OrdinalIgnoreCase))
            description = null;
        var totalDuration = scanned.Sum(c => c.DurationSec);

        var book = await _db.Books
            .Include(b => b.Chapters)
            .Include(b => b.Genres)
            .FirstOrDefaultAsync(b => b.FolderPath == relFolder, ct);

        if (book is null)
        {
            book = new Book { FolderPath = relFolder, AddedAt = DateTime.UtcNow };
            _db.Books.Add(book);
        }
        else if (book.AddedAt == default)
        {
            book.AddedAt = DateTime.UtcNow;
        }

        // Reconcile chapters by FilePath so unchanged files keep their Chapter.Id
        // (and therefore any saved listening progress) across a re-scan.
        var existingByPath = book.Chapters.ToDictionary(c => c.FilePath);
        var scannedPaths = scanned.Select(c => c.FilePath).ToHashSet();

        foreach (var gone in book.Chapters.Where(c => !scannedPaths.Contains(c.FilePath)).ToList())
        {
            book.Chapters.Remove(gone);
            _db.Chapters.Remove(gone);
        }

        foreach (var s in scanned)
        {
            if (existingByPath.TryGetValue(s.FilePath, out var ch))
            {
                ch.Title = s.Title;
                ch.DurationSec = s.DurationSec;
                ch.TrackNumber = s.TrackNumber;
            }
            else
            {
                book.Chapters.Add(new Chapter
                {
                    Title = s.Title,
                    FilePath = s.FilePath,
                    DurationSec = s.DurationSec,
                    TrackNumber = s.TrackNumber
                });
            }
        }

        book.Title = title;
        book.Author = author;
        book.Description = description;
        book.HasCover = hasCover;
        book.DurationSec = totalDuration;
        book.ChapterCount = scanned.Count;
        book.Genres = await ResolveGenresAsync(genreNames, ct);

        await _db.SaveChangesAsync(ct);
        _logger.LogInformation("Indexed '{Title}' ({Count} chapter(s), {Dur}s, genres: {Genres})",
            title, scanned.Count, totalDuration,
            genreNames.Count > 0 ? string.Join(", ", genreNames) : "-");
    }

    // Maps genre names to shared Genre rows, creating any that don't yet exist.
    private async Task<List<Genre>> ResolveGenresAsync(List<string> names, CancellationToken ct)
    {
        var result = new List<Genre>();
        if (names.Count == 0) return result;

        var existing = await _db.Genres
            .Where(g => names.Contains(g.Name))
            .ToListAsync(ct);

        foreach (var name in names)
        {
            var genre = existing.FirstOrDefault(g => string.Equals(g.Name, name, StringComparison.OrdinalIgnoreCase))
                        ?? _db.Genres.Local.FirstOrDefault(g => string.Equals(g.Name, name, StringComparison.OrdinalIgnoreCase));
            if (genre is null)
            {
                genre = new Genre { Name = name };
                _db.Genres.Add(genre);
            }
            result.Add(genre);
        }

        return result;
    }

    public async Task HandleRenameAsync(string oldFullPath, string newFullPath, CancellationToken ct)
    {
        // A renamed file (still inside the same folder) is just a content change.
        if (!Directory.Exists(newFullPath))
        {
            var fileFolder = Path.GetDirectoryName(newFullPath);
            if (!string.IsNullOrEmpty(fileFolder)) await IndexFolderAsync(fileFolder, ct);
            return;
        }

        // A directory was renamed or moved. Migrate the FolderPath (and every chapter
        // FilePath) of the affected book and any books nested beneath it, preserving the
        // book/chapter identities so listening progress is retained.
        var oldRel = RelPath(oldFullPath);
        var newRel = RelPath(newFullPath);
        var oldPrefix = oldRel + "/";

        var affected = await _db.Books
            .Include(b => b.Chapters)
            .Where(b => b.FolderPath == oldRel || b.FolderPath.StartsWith(oldPrefix))
            .ToListAsync(ct);

        if (affected.Count == 0)
        {
            // Nothing tracked under the old path yet -> treat as a fresh scan.
            await ScanTreeAsync(newFullPath, ct);
            return;
        }

        foreach (var book in affected)
        {
            var remainder = book.FolderPath.Substring(oldRel.Length); // "" or "/nested..."
            var newFolder = newRel + remainder;

            // Drop any stale row already occupying the destination to avoid a unique clash.
            var dup = await _db.Books.FirstOrDefaultAsync(
                b => b.FolderPath == newFolder && b.Id != book.Id, ct);
            if (dup is not null) _db.Books.Remove(dup);

            book.FolderPath = newFolder;
            // Only refresh the title from the folder name when it was folder-derived;
            // an Album-tag title must survive a folder rename.
            var oldLeaf = Path.GetFileName(oldRel + remainder);
            var newLeaf = Path.GetFileName(newFolder);
            if (string.Equals(book.Title, oldLeaf, StringComparison.Ordinal))
                book.Title = newLeaf;

            foreach (var ch in book.Chapters)
            {
                if (ch.FilePath == oldRel || ch.FilePath.StartsWith(oldPrefix))
                    ch.FilePath = newRel + ch.FilePath.Substring(oldRel.Length);
            }
        }

        await _db.SaveChangesAsync(ct);
        _logger.LogInformation("Renamed folder '{Old}' -> '{New}' ({Count} book(s) migrated).",
            oldRel, newRel, affected.Count);
    }

    public async Task HandleDeleteAsync(string fullPath, CancellationToken ct)
    {
        // If the deleted path still exists it was a transient event; reindex the folder.
        if (File.Exists(fullPath) || Directory.Exists(fullPath))
        {
            var folder = Directory.Exists(fullPath) ? fullPath : Path.GetDirectoryName(fullPath);
            if (!string.IsNullOrEmpty(folder)) await IndexFolderAsync(folder, ct);
            return;
        }

        var rel = RelPath(fullPath);
        var prefix = rel + "/";

        // Remove any books whose folder was deleted (exact match or nested beneath it).
        var gone = await _db.Books
            .Where(b => b.FolderPath == rel || b.FolderPath.StartsWith(prefix))
            .ToListAsync(ct);
        if (gone.Count > 0)
        {
            _db.Books.RemoveRange(gone);
            await _db.SaveChangesAsync(ct);
            _logger.LogInformation("Removed {Count} book(s) under deleted path '{Path}'.", gone.Count, rel);
            return;
        }

        // Otherwise a file was deleted from within a book folder -> reindex the parent.
        var parent = Path.GetDirectoryName(fullPath);
        if (!string.IsNullOrEmpty(parent) && Directory.Exists(parent))
            await IndexFolderAsync(parent, ct);
    }

    private async Task ScanTreeAsync(string rootFullPath, CancellationToken ct)
    {
        foreach (var folder in Directory.EnumerateDirectories(rootFullPath, "*", SearchOption.AllDirectories)
                     .Append(rootFullPath)
                     .Where(HasAudioFiles))
        {
            ct.ThrowIfCancellationRequested();
            await IndexFolderAsync(folder, ct);
        }
    }

    private async Task PruneMissingBooksAsync(CancellationToken ct)
    {
        var books = await _db.Books.ToListAsync(ct);
        var removed = false;
        foreach (var b in books)
        {
            var full = Path.Combine(RootPath, b.FolderPath);
            if (!Directory.Exists(full) || GetAudioFiles(full).Count == 0)
            {
                _db.Books.Remove(b);
                removed = true;
            }
        }
        if (removed) await _db.SaveChangesAsync(ct);
    }

    private static bool HasAudioFiles(string folder) => GetAudioFiles(folder).Count > 0;

    private static List<string> GetAudioFiles(string folder)
    {
        if (!Directory.Exists(folder)) return new List<string>();
        return Directory.EnumerateFiles(folder, "*", SearchOption.TopDirectoryOnly)
            .Where(f => AudioExtensions.Contains(Path.GetExtension(f).ToLowerInvariant()))
            .OrderBy(f => f, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private string RelPath(string fullPath) =>
        Path.GetRelativePath(RootPath, fullPath).Replace("\\", "/");

    private Metadata ReadMetadata(string fullPath)
    {
        try
        {
            using var tf = TagLib.File.Create(fullPath);
            var tag = tf.Tag;
            var pic = tag.Pictures?.FirstOrDefault();

            if (_logger.IsEnabled(LogLevel.Information))
            {
                _logger.LogInformation(
                    "ID tags for {File} [{TagTypes}]:\n" +
                    "  Title        : {Title}\n" +
                    "  Performers   : {Performers}\n" +
                    "  AlbumArtists : {AlbumArtists}\n" +
                    "  Composers    : {Composers}\n" +
                    "  Album        : {Album}\n" +
                    "  Track        : {Track}/{TrackCount}   Disc: {Disc}/{DiscCount}\n" +
                    "  Year         : {Year}\n" +
                    "  Genres       : {Genres}\n" +
                    "  Duration     : {Duration} ({DurationSec}s)   Codecs: {Codecs}   Bitrate: {Bitrate}kbps\n" +
                    "  Comment      : {Comment}\n" +
                    "  Pictures     : {PictureCount} (first: {PicMime}, {PicBytes} bytes)",
                    RelPath(fullPath),
                    string.Join("|", tf.TagTypes),
                    Show(tag.Title),
                    Show(tag.Performers),
                    Show(tag.AlbumArtists),
                    Show(tag.Composers),
                    Show(tag.Album),
                    tag.Track, tag.TrackCount, tag.Disc, tag.DiscCount,
                    tag.Year,
                    Show(tag.Genres),
                    tf.Properties?.Duration, (int)(tf.Properties?.Duration.TotalSeconds ?? 0),
                    string.Join("|", tf.Properties?.Codecs.Where(c => c is not null).Select(c => c!.Description) ?? Enumerable.Empty<string>()),
                    tf.Properties?.AudioBitrate ?? 0,
                    Show(tag.Comment),
                    tag.Pictures?.Length ?? 0,
                    pic?.MimeType ?? "-", pic?.Data.Count ?? 0);
            }

            return new Metadata
            {
                Title = tag.Title,
                Author = tag.FirstPerformer ?? tag.FirstAlbumArtist ?? tag.FirstComposer,
                Album = tag.Album,
                Genres = tag.Genres ?? Array.Empty<string>(),
                Description = string.IsNullOrWhiteSpace(tag.Comment) ? tag.Album : tag.Comment,
                DurationSec = (int)(tf.Properties?.Duration.TotalSeconds ?? 0),
                Track = (int)tag.Track,
                HasCover = pic is not null && pic.Data.Count > 0
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to read metadata for {File}", fullPath);
            return new Metadata { DurationSec = 0 };
        }
    }

    private static string Show(string? value) => string.IsNullOrWhiteSpace(value) ? "-" : value;
    private static string Show(string[]? values) =>
        values is { Length: > 0 } ? string.Join(", ", values) : "-";

    private record ScannedChapter(string Title, string FilePath, int DurationSec, int TrackNumber);

    private class Metadata
    {
        public string? Title { get; set; }
        public string? Author { get; set; }
        public string? Album { get; set; }
        public string[] Genres { get; set; } = Array.Empty<string>();
        public string? Description { get; set; }
        public int DurationSec { get; set; }
        public int Track { get; set; }
        public bool HasCover { get; set; }
    }
}
