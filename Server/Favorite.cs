namespace Server;

public class Favorite
{
    public int UserId { get; set; }
    public int BookId { get; set; }
    public DateTime CreatedAt { get; set; }

    public Book Book { get; set; } = default!;
}
