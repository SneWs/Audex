using System.Collections.Generic;

namespace Client;

public class ChapterDto
{
    public int Id { get; init; }
    public string Title { get; init; } = default!;
    public int DurationSec { get; init; }
    public int TrackNumber { get; init; }
}

public class BookDto
{
    public int Id { get; init; }
    public string Title { get; init; } = default!;
    public string Author { get; init; } = default!;
    public int DurationSec { get; init; }
    public int ChapterCount { get; init; }
    public bool HasCover { get; init; }
    public string? Description { get; init; }
    public DateTime AddedAt { get; init; }
    public int ProgressSec { get; init; }
    public bool IsCompleted { get; init; }
    public DateTime? LastPlayedAt { get; init; }
    public int? ResumeChapterId { get; init; }
    public int ResumePositionSec { get; init; }
    public List<string> Genres { get; init; } = new();
    public bool IsStarted => LastPlayedAt is not null;
}

public class GenreDto
{
    public string Name { get; init; } = default!;
    public int Count { get; init; }
}

public class BookDetailDto : BookDto
{
    public List<ChapterDto> Chapters { get; init; } = new();
}
