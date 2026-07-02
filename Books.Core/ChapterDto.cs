namespace Grenis.AudioBooks.Core;

public class ChapterDto
{
    public int Id { get; init; }
    public string Title { get; init; } = string.Empty;
    public int DurationSec { get; init; }
    public int TrackNumber { get; init; }
}