namespace Grenis.AudioBooks.Core;

public class PlaylistRequest
{
    public string Name { get; init; } = string.Empty;
    public List<int> BookIds { get; init; } = new();
}
