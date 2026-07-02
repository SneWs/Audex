namespace Grenis.AudioBooks.Core;

public class ProgressDto
{
    public int BookId { get; set; }
    public int ChapterId { get; set; }
    public int PositionSec { get; set; }
}