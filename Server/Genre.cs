using System.Collections.Generic;
namespace Server;
public class Genre
{
    public int Id { get; set; }
    public string Name { get; set; } = default!;

    public List<Book> Books { get; set; } = new();
}
