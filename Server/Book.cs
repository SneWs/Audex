using System.Collections.Generic;
namespace Server;
public class Book
{
    public int Id { get; set; }
    public string Title { get; set; } = default!;
    public string Author { get; set; } = default!;
    public string FolderPath { get; set; } = default!; // relative to library path
    public int DurationSec { get; set; }               // total across all chapters
    public int ChapterCount { get; set; }
    public bool HasCover { get; set; }
    public string? Description { get; set; }
    public DateTime AddedAt { get; set; }

    public List<Chapter> Chapters { get; set; } = new();
    public List<Genre> Genres { get; set; } = new();
}
