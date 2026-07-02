namespace Grenis.AudioBooks.Server.Database.Tables;
public class Genre
{
    public int Id { get; set; }
    public string Name { get; set; } = default!;

    public List<Book> Books { get; set; } = new();
}
