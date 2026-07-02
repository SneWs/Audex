namespace Grenis.AudioBooks.Core;

// Auth / account
public record LoginRequest(string Email, string Password);
public record AuthResponse(string Token);
public record AccountDto(int Id, string Email);
public record ChangeEmailRequest(string NewEmail, string CurrentPassword);
public record ChangePasswordRequest(string CurrentPassword, string NewPassword);
public record EmailChangeResponse(string Token, string Email);

// Generic responses
public record MessageResponse(string Message);
public record FavoriteResponse(bool IsFavorite);
public record RescanResponse(int Count);

// Progress
public class ProgressDto
{
    public int BookId { get; set; }
    public int ChapterId { get; set; }
    public int PositionSec { get; set; }
}

// Books / chapters / genres
public class ChapterDto
{
    public int Id { get; init; }
    public string Title { get; init; } = default!;
    public int DurationSec { get; init; }
    public int TrackNumber { get; init; }
}

public class BookDto
{
    public int Id { get; init; }
    public string Title { get; init; } = default!;
    public string Author { get; init; } = default!;
    public string? ReadBy { get; init; }
    public int DurationSec { get; init; }
    public int ChapterCount { get; init; }
    public bool HasCover { get; init; }
    public string? Description { get; init; }
    public DateTime AddedAt { get; init; }
    public int ProgressSec { get; init; }
    public bool IsCompleted { get; init; }
    public bool IsFavorite { get; set; }
    public DateTime? LastPlayedAt { get; init; }
    public int? ResumeChapterId { get; init; }
    public int ResumePositionSec { get; init; }
    public List<string> Genres { get; init; } = new();
    public bool IsStarted => LastPlayedAt is not null;
}

public class BookDetailDto : BookDto
{
    public List<ChapterDto> Chapters { get; init; } = new();
}

public class GenreDto
{
    public string Name { get; init; } = default!;
    public int Count { get; init; }
}
