namespace Grenis.AudioBooks.Server.Database.Tables;
public class Book
{
    public int Id { get; set; }
    public string Title { get; set; } = default!;
    public string? Subtitle { get; set; }
    public string Author { get; set; } = default!;
    public int? Year { get; set; }
    public string? ReadBy { get; set; }                 // narrator, from AlbumArtists tag
    public string FolderPath { get; set; } = default!; // relative to library path
    public int DurationSec { get; set; }               // total across all chapters
    public int ChapterCount { get; set; }
    public bool HasCover { get; set; }
    public string? CoverUrl { get; set; }              // external cover image URL (from Google Books / Open Library)
    public string? Description { get; set; }
    public string? Publisher { get; set; }
    public string? Language { get; set; }
    public string? Isbn10 { get; set; }
    public string? Isbn13 { get; set; }
    public int? PageCount { get; set; }
    public double? Rating { get; set; }
    public int? RatingCount { get; set; }
    public string? GoogleBooksUrl { get; set; }
    public string? OpenLibraryUrl { get; set; }
    public DateTime AddedAt { get; set; }

    public List<Chapter> Chapters { get; set; } = new();
    public List<Genre> Genres { get; set; } = new();
}
