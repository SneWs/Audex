namespace Grenis.AudioBooks.Server.Database.Tables;

public class PlaylistBook
{
    public int PlaylistId { get; set; }
    public int BookId { get; set; }
    public int Position { get; set; }
    public Playlist Playlist { get; set; } = default!;
    public Book Book { get; set; } = default!;
}
