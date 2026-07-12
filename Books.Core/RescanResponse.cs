namespace Grenis.AudioBooks.Core;

public record RescanResponse(int Count)
{
    public string? Message { get; init; }
}