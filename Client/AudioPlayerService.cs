using System.Net.Http.Json;
using Grenis.AudioBooks.Core;

namespace Grenis.AudioBooks.Client;

public class AudioPlayerService
{
    private readonly HttpClient _http;

    public AudioPlayerService(HttpClient http) => _http = http;

    public BookDetailDto? Current { get; private set; }
    public int CurrentChapterIndex { get; private set; }

    public ChapterDto? CurrentChapter =>
        Current is null ? null :
        (CurrentChapterIndex >= 0 && CurrentChapterIndex < Current.Chapters.Count
            ? Current.Chapters[CurrentChapterIndex]
            : null);

    public bool HasNext => Current is not null && CurrentChapterIndex + 1 < Current.Chapters.Count;
    public bool HasPrevious => Current is not null && CurrentChapterIndex > 0;

    public int PendingSeekSec { get; private set; }

    public event Action? Changed;
    public event Action? Closed;

    public async Task PlayAsync(int bookId)
    {
        Current = await _http.GetFromJsonAsync<BookDetailDto>($"/api/books/{bookId}");
        CurrentChapterIndex = 0;
        PendingSeekSec = 0;

        if (Current is not null && Current.ResumeChapterId is int resumeId && !Current.IsCompleted)
        {
            var idx = Current.Chapters.FindIndex(c => c.Id == resumeId);
            if (idx >= 0)
            {
                CurrentChapterIndex = idx;
                PendingSeekSec = Current.ResumePositionSec;
            }
        }

        Changed?.Invoke();
    }

    public int ConsumePendingSeek()
    {
        var s = PendingSeekSec;
        PendingSeekSec = 0;
        return s;
    }

    public void PlayChapter(int index)
    {
        if (Current is null || index < 0 || index >= Current.Chapters.Count) return;
        CurrentChapterIndex = index;
        Changed?.Invoke();
    }

    public bool Next()
    {
        if (!HasNext) return false;
        CurrentChapterIndex++;
        Changed?.Invoke();
        return true;
    }

    public bool Previous()
    {
        if (!HasPrevious) return false;
        CurrentChapterIndex--;
        Changed?.Invoke();
        return true;
    }

    public void Close()
    {
        Current = null;
        CurrentChapterIndex = 0;
        Closed?.Invoke();
        Changed?.Invoke();
    }
}
