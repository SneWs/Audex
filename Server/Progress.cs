using System.Collections.Generic;
namespace Server;
public class Progress
{
    public int UserId { get; set; }
    public int BookId { get; set; }
    public int ChapterId { get; set; }
    public int PositionSec { get; set; }
    public DateTime UpdatedAt { get; set; }
}
