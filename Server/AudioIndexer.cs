using Grenis.AudioBooks.Server.Database;
using Grenis.AudioBooks.Server.Database.Tables;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace Grenis.AudioBooks.Server;

public class AudioIndexer : IAudioIndexer
{
    private static readonly string[] AudioExtensions =
        { ".mp3", ".m4a", ".m4b", ".aac", ".ogg", ".flac", ".wav" };

    private static readonly SemaphoreSlim _indexLock = new(1, 1);

    private readonly AppDbContext _db;
    private readonly AudiobookSettings _settings;
    private readonly BookMetadataLookup _metadataLookup;
    private readonly IHubContext<LibraryHub, ILibraryHubClient> _hub;
    private readonly ILogger<AudioIndexer> _logger;

    public string RootPath => _settings.LibraryPath;

    public AudioIndexer(
        AppDbContext db,
        Microsoft.Extensions.Options.IOptions<AudiobookSettings> options,
        BookMetadataLookup metadataLookup,
        IHubContext<LibraryHub, ILibraryHubClient> hub,
        ILogger<AudioIndexer> logger)
    {
        _db = db;
        _settings = options.Value;
        _metadataLookup = metadataLookup;
        _hub = hub;
        _logger = logger;
    }

    public async Task InitialScanAsync(CancellationToken ct = default)
    {
        if (!Directory.Exists(RootPath))
        {
            _logger.LogWarning("Library path {Path} does not exist.", RootPath);
            return;
        }

        await _hub.Clients.All.ScanStarted();

        // Every directory that directly contains at least one audio file is a book.
        var bookFolders = Directory.EnumerateDirectories(RootPath, "*", SearchOption.AllDirectories)
            .Append(RootPath)
            .Where(HasAudioFiles)
            .ToList();

        for (var i = 0; i < bookFolders.Count; i++)
        {
            ct.ThrowIfCancellationRequested();
            await _hub.Clients.All.ScanProgress($"Scanning {i + 1}/{bookFolders.Count}: {Path.GetFileName(bookFolders[i])}");
            await IndexFolderAsync(bookFolders[i], ct)
                .ConfigureAwait(false);
        }

        await PruneMissingBooksAsync(ct)
            .ConfigureAwait(false);

        var totalBooks = await _db.Books.CountAsync(ct).ConfigureAwait(false);
        await _hub.Clients.All.ScanCompleted(totalBooks);
    }

    public async Task<bool> RescanBookAsync(int bookId, CancellationToken ct = default)
    {
        var book = await _db.Books.AsNoTracking()
            .FirstOrDefaultAsync(b => b.Id == bookId, ct)
            .ConfigureAwait(false);

        if (book == null)
            return false;

        var folderFullPath = Path.Combine(RootPath, book.FolderPath);
        await IndexFolderAsync(folderFullPath, ct).ConfigureAwait(false);
        return true;
    }

    public async Task IndexFolderAsync(string folderFullPath, CancellationToken ct)
    {
        await _indexLock.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            await IndexFolderCoreAsync(folderFullPath, ct).ConfigureAwait(false);
        }
        finally
        {
            _indexLock.Release();
        }
    }

    private async Task IndexFolderCoreAsync(string folderFullPath, CancellationToken ct)
    {
        var relFolder = RelPath(folderFullPath);

        var files = GetAudioFiles(folderFullPath);
        if (files.Count == 0)
        {
            // Folder no longer holds audio -> drop the book if we had one.
            var stale = await _db.Books.FirstOrDefaultAsync(b => b.FolderPath == relFolder, ct)
                .ConfigureAwait(false);

            if (stale != null)
            {
                var removedId = stale.Id;
                var removedTitle = stale.Title;
                _db.Books.Remove(stale);
                await _db.SaveChangesAsync(ct)
                    .ConfigureAwait(false);

                await _hub.Clients.All.BookRemoved(removedId, removedTitle);
                _logger.LogInformation("Removed book (no audio left): {Folder}", relFolder);
            }
            return;
        }

        var scanned = new List<ScannedChapter>();
        var author = "Unknown";
        int? year = null;
        string? readBy = null;
        string? description = null;
        string? album = null;
        string? taggedTitle = null;
        string? firstFileNameTitle = null;
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

            if (author == "Unknown" && !string.IsNullOrWhiteSpace(meta.Author)) 
                author = meta.Author!;
            if (year is null && meta.Year > 0)
                year = meta.Year;
            if (readBy == null && !string.IsNullOrWhiteSpace(meta.ReadBy)) 
                readBy = meta.ReadBy;
            if (album == null && !string.IsNullOrWhiteSpace(meta.Album)) 
                album = meta.Album;
            if (taggedTitle == null && !string.IsNullOrWhiteSpace(meta.Title))
                taggedTitle = meta.Title;
            if (firstFileNameTitle == null)
                firstFileNameTitle = Path.GetFileNameWithoutExtension(file);
            if (description == null && !string.IsNullOrWhiteSpace(meta.Description)) 
                description = meta.Description;
            if (meta.HasCover) 
                hasCover = true;
            
            foreach (var raw in meta.Genres)
            {
                // A single tag field may pack several genres, e.g. "Literary Fiction, Classics".
                foreach (var part in raw.Split([',', ';', '/', '|'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    if (!genreNames.Contains(part, StringComparer.OrdinalIgnoreCase))
                        genreNames.Add(part);
                }
            }
        }

        scanned = scanned.OrderBy(c => c.TrackNumber).ThenBy(c => c.FilePath).ToList();

        // Prefer the Album tag as the book name; fall back to the folder name.
        var folderName = new DirectoryInfo(folderFullPath).Name;
        var title = string.IsNullOrWhiteSpace(album) ? folderName : album;
        
        // Avoid showing the same text as both title and description.
        if (!string.IsNullOrWhiteSpace(description) &&
            string.Equals(description, title, StringComparison.OrdinalIgnoreCase))
        {
            description = null;
        }
        
        var totalDuration = scanned.Sum(c => c.DurationSec);

        var book = await _db.Books
            .AsSplitQuery()
            .Include(b => b.Chapters)
            .Include(b => b.Genres)
            .FirstOrDefaultAsync(b => b.FolderPath == relFolder, ct)
            .ConfigureAwait(false);

        var isNew = false;
        if (book == null)
        {
            book = new Book { FolderPath = relFolder, AddedAt = DateTime.UtcNow };
            _db.Books.Add(book);
            isNew = true;
        }
        else if (book.AddedAt == default)
        {
            book.AddedAt = DateTime.UtcNow;
        }

        var previousCustomTitle = book.CustomTitle;
        var previousDbTitle = book.Title;

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
        book.Year = year;
        book.ReadBy = readBy;
        book.Description = description;
        book.HasCover = hasCover;
        book.DurationSec = totalDuration;
        book.ChapterCount = scanned.Count;

        // Enrich with external metadata for missing fields.
        try
        {
            BookMetadataLookup.ExternalMetadata? external = null;
            foreach (var lookupTitle in BuildLookupTitleCandidates(previousCustomTitle, album, taggedTitle, firstFileNameTitle, previousDbTitle))
            {
                external = await _metadataLookup.LookupAsync(lookupTitle, author, year, ct).ConfigureAwait(false);
                if (external != null)
                    break;
            }

            if (external is not null)
            {
                if (string.IsNullOrWhiteSpace(description) && !string.IsNullOrWhiteSpace(external.Description))
                    book.Description = external.Description;

                if (string.IsNullOrWhiteSpace(book.Subtitle) && !string.IsNullOrWhiteSpace(external.Subtitle))
                    book.Subtitle = external.Subtitle;

                if (!hasCover && !string.IsNullOrWhiteSpace(external.CoverUrl))
                {
                    book.CoverUrl = external.CoverUrl;
                    book.HasCover = true;
                }

                if (string.IsNullOrWhiteSpace(book.Publisher) && !string.IsNullOrWhiteSpace(external.Publisher))
                    book.Publisher = external.Publisher;

                if (string.IsNullOrWhiteSpace(book.Language) && !string.IsNullOrWhiteSpace(external.Language))
                    book.Language = external.Language;

                if (book.Isbn10 is null && external.Isbn10 is not null)
                    book.Isbn10 = external.Isbn10;

                if (book.Isbn13 is null && external.Isbn13 is not null)
                    book.Isbn13 = external.Isbn13;

                if (book.PageCount is null && external.PageCount is > 0)
                    book.PageCount = external.PageCount;

                if (book.Rating is null && external.Rating is > 0)
                    book.Rating = external.Rating;

                if (book.RatingCount is null && external.RatingCount is > 0)
                    book.RatingCount = external.RatingCount;

                if (book.Year is null && !string.IsNullOrWhiteSpace(external.PublishedDate)
                    && int.TryParse(external.PublishedDate.AsSpan(0, Math.Min(4, external.PublishedDate.Length)), out var extYear)
                    && extYear > 0)
                    book.Year = extYear;

                if (external.Source == "GoogleBooks" && string.IsNullOrWhiteSpace(book.GoogleBooksUrl))
                    book.GoogleBooksUrl = external.InfoUrl;
                if (external.Source == "OpenLibrary" && string.IsNullOrWhiteSpace(book.OpenLibraryUrl))
                    book.OpenLibraryUrl = external.InfoUrl;
                if (!string.IsNullOrWhiteSpace(external.OpenLibraryInfoUrl) && string.IsNullOrWhiteSpace(book.OpenLibraryUrl))
                    book.OpenLibraryUrl = external.OpenLibraryInfoUrl;

                if (external.Categories is { Count: > 0 })
                {
                    foreach (var cat in external.Categories)
                    {
                        if (!genreNames.Contains(cat, StringComparer.OrdinalIgnoreCase))
                            genreNames.Add(cat);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "External metadata lookup failed for '{Title}'", title);
        }

        book.Genres = await ResolveGenresAsync(genreNames, ct)
            .ConfigureAwait(false);

        await _db.SaveChangesAsync(ct)
            .ConfigureAwait(false);

        var displayTitle = string.IsNullOrWhiteSpace(book.CustomTitle) ? title : book.CustomTitle;
        if (isNew)
            await _hub.Clients.All.BookAdded(book.Id, displayTitle!);
        else
            await _hub.Clients.All.BookUpdated(book.Id, displayTitle!);

        _logger.LogInformation("Indexed '{Title}' ({Count} chapter(s), {Dur}s, genres: {Genres})",
            displayTitle, scanned.Count, totalDuration,
            genreNames.Count > 0 ? string.Join(", ", genreNames) : "-");
    }

    // Maps genre names to shared Genre rows, creating any that don't yet exist.
    private async Task<List<Genre>> ResolveGenresAsync(List<string> names, CancellationToken ct)
    {
        var result = new List<Genre>();
        if (names.Count == 0) return result;

        var existing = await _db.Genres
            .Where(g => names.Contains(g.Name))
            .ToListAsync(ct)
            .ConfigureAwait(false);

        foreach (var name in names)
        {
            var genre = existing.FirstOrDefault(g => string.Equals(g.Name, name, StringComparison.OrdinalIgnoreCase))
                        ?? _db.Genres.Local.FirstOrDefault(g => string.Equals(g.Name, name, StringComparison.OrdinalIgnoreCase));
            if (genre == null)
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
            if (!string.IsNullOrEmpty(fileFolder))
            {
                await IndexFolderAsync(fileFolder, ct)
                    .ConfigureAwait(false);
            }

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
            .ToListAsync(ct)
            .ConfigureAwait(false);

        if (affected.Count == 0)
        {
            // Nothing tracked under the old path yet -> treat as a fresh scan.
            await ScanTreeAsync(newFullPath, ct)
                .ConfigureAwait(false);

            return;
        }

        foreach (var book in affected)
        {
            var remainder = book.FolderPath.Substring(oldRel.Length); // "" or "/nested..."
            var newFolder = newRel + remainder;

            // Drop any stale row already occupying the destination to avoid a unique clash.
            var dup = await _db.Books.FirstOrDefaultAsync(
                b => b.FolderPath == newFolder && b.Id != book.Id, ct)
                .ConfigureAwait(false);

            if (dup is not null)
            {
                _db.Books.Remove(dup);
            }

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

        await _db.SaveChangesAsync(ct)
            .ConfigureAwait(false);

        _logger.LogInformation("Renamed folder '{Old}' -> '{New}' ({Count} book(s) migrated).",
            oldRel, newRel, affected.Count);
    }

    public async Task HandleDeleteAsync(string fullPath, CancellationToken ct)
    {
        // If the deleted path still exists it was a transient event; reindex the folder.
        if (File.Exists(fullPath) || Directory.Exists(fullPath))
        {
            var folder = Directory.Exists(fullPath) ? fullPath : Path.GetDirectoryName(fullPath);
            if (!string.IsNullOrEmpty(folder))
            {
                await IndexFolderAsync(folder, ct)
                    .ConfigureAwait(false);
            }

            return;
        }

        var rel = RelPath(fullPath);
        var prefix = rel + "/";

        // Remove any books whose folder was deleted (exact match or nested beneath it).
        var gone = await _db.Books
            .Where(b => b.FolderPath == rel || b.FolderPath.StartsWith(prefix))
            .ToListAsync(ct)
            .ConfigureAwait(false);

        if (gone.Count > 0)
        {
            _db.Books.RemoveRange(gone);
            await _db.SaveChangesAsync(ct)
                .ConfigureAwait(false);

            _logger.LogInformation("Removed {Count} book(s) under deleted path '{Path}'.", gone.Count, rel);
            return;
        }

        // Otherwise a file was deleted from within a book folder -> reindex the parent.
        var parent = Path.GetDirectoryName(fullPath);
        if (!string.IsNullOrEmpty(parent) && Directory.Exists(parent))
        {
            await IndexFolderAsync(parent, ct)
                .ConfigureAwait(false);
        }
    }

    private async Task ScanTreeAsync(string rootFullPath, CancellationToken ct)
    {
        foreach (var folder in Directory.EnumerateDirectories(rootFullPath, "*", SearchOption.AllDirectories)
                     .Append(rootFullPath)
                     .Where(HasAudioFiles))
        {
            ct.ThrowIfCancellationRequested();
            await IndexFolderAsync(folder, ct)
                .ConfigureAwait(false);
        }
    }

    private async Task PruneMissingBooksAsync(CancellationToken ct)
    {
        var books = await _db.Books.ToListAsync(ct)
            .ConfigureAwait(false);

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

        if (removed)
        {
            await _db.SaveChangesAsync(ct)
                .ConfigureAwait(false);
        }
    }

    private static bool HasAudioFiles(string folder) => GetAudioFiles(folder).Count > 0;

    private static List<string> GetAudioFiles(string folder)
    {
        if (!Directory.Exists(folder))
            return new List<string>();

        return Directory.EnumerateFiles(folder, "*", SearchOption.TopDirectoryOnly)
            .Where(f => AudioExtensions.Contains(Path.GetExtension(f).ToLowerInvariant())
                     && !Path.GetFileName(f).StartsWith('.'))
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

            if (_logger.IsEnabled(LogLevel.Debug))
            {
                _logger.LogDebug(
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
                Year = tag.Year > 0 ? (int)tag.Year : null,
                ReadBy = FirstNonEmpty(tag.Composers) ?? FirstNonEmpty(tag.AlbumArtists),
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

    private static List<string> BuildLookupTitleCandidates(
        string? customTitle,
        string? metadataAlbumTitle,
        string? metadataTrackTitle,
        string? fileNameTitle,
        string? databaseTitle)
    {
        var titles = new List<string>();
        AddCandidateTitle(titles, customTitle);
        AddCandidateTitle(titles, metadataAlbumTitle);
        AddCandidateTitle(titles, metadataTrackTitle);
        AddCandidateTitle(titles, fileNameTitle);
        AddCandidateTitle(titles, databaseTitle);
        return titles;
    }

    private static void AddCandidateTitle(List<string> titles, string? candidate)
    {
        if (string.IsNullOrWhiteSpace(candidate))
            return;

        var normalized = candidate.Trim();
        if (titles.Contains(normalized, StringComparer.OrdinalIgnoreCase))
            return;

        titles.Add(normalized);
    }

    private static string? FirstNonEmpty(string[]? values)
    {
        var picked = values?.Where(v => !string.IsNullOrWhiteSpace(v)).Select(v => v.Trim()).ToArray();
        return picked is { Length: > 0 } ? string.Join(", ", picked) : null;
    }
    private static string Show(string[]? values) =>
        values is { Length: > 0 } ? string.Join(", ", values) : "-";

    private record ScannedChapter(string Title, string FilePath, int DurationSec, int TrackNumber);

    private class Metadata
    {
        public string? Title { get; set; }
        public string? Author { get; set; }
        public int? Year { get; set; }
        public string? ReadBy { get; set; }
        public string? Album { get; set; }
        public string[] Genres { get; set; } = Array.Empty<string>();
        public string? Description { get; set; }
        public int DurationSec { get; set; }
        public int Track { get; set; }
        public bool HasCover { get; set; }
    }
}
