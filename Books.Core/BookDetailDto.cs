namespace Grenis.AudioBooks.Core;

public class BookDetailDto : BookDto
{
    public List<ChapterDto> Chapters { get; init; } = new();
}