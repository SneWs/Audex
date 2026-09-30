namespace Grenis.AudioBooks.Core;

public class PlaylistDto
{
    public int Id { get; init; }
    public string Name { get; init; } = string.Empty;
    public DateTime CreatedAt { get; init; }
    public DateTime UpdatedAt { get; init; }
    public List<BookDto> Books { get; init; } = new();
}
