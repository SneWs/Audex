namespace Grenis.AudioBooks.Core;

public class BookDto
{
    public int Id { get; init; }
    public string Title { get; init; } = string.Empty;
    public string? CustomTitle { get; init; }
    public string? Subtitle { get; init; }
    public string Author { get; init; } = string.Empty;
    public int? Year { get; init; }
    public string? ReadBy { get; init; }
    public int DurationSec { get; init; }
    public int ChapterCount { get; init; }
    public bool HasCover { get; init; }
    public string? Description { get; init; }
    public string? Publisher { get; init; }
    public string? Language { get; init; }
    public string? Isbn10 { get; init; }
    public string? Isbn13 { get; init; }
    public int? PageCount { get; init; }
    public double? Rating { get; init; }
    public int? RatingCount { get; init; }
    public string? GoogleBooksUrl { get; init; }
    public string? OpenLibraryUrl { get; init; }
    public DateTime AddedAt { get; init; }
    public int ProgressSec { get; init; }
    public bool IsCompleted { get; init; }
    public bool IsFavorite { get; set; }
    public DateTime? LastPlayedAt { get; init; }
    public int? ResumeChapterId { get; init; }
    public int ResumePositionSec { get; init; }
    public List<string> Genres { get; init; } = new();
    public bool IsStarted => LastPlayedAt is not null;
}