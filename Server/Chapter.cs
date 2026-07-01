namespace Server;
public class Chapter
{
    public int Id { get; set; }
    public int BookId { get; set; }
    public string Title { get; set; } = default!;
    public string FilePath { get; set; } = default!; // relative to library path
    public int DurationSec { get; set; }
    public int TrackNumber { get; set; }

    public Book Book { get; set; } = default!;
}
