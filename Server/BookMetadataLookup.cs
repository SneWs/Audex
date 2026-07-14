using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Grenis.AudioBooks.Server;

/// <summary>
/// Looks up book metadata from external sources (Audible, Open Library)
/// to fill in missing information not available in local audio file tags.
/// </summary>
public class BookMetadataLookup
{
    private readonly HttpClient _http;
    private readonly IAudibleBookScraper _audibleBookScraper;
    private readonly ILogger<BookMetadataLookup> _logger;

    public BookMetadataLookup(HttpClient http, IAudibleBookScraper audibleBookScraper, ILogger<BookMetadataLookup> logger)
    {
        _http = http;
        _audibleBookScraper = audibleBookScraper;
        _logger = logger;
    }

    // Throttle to avoid rate limiting during bulk scans.
    private static readonly SemaphoreSlim _throttle = new(1, 1);
    private static DateTime _lastRequest = DateTime.MinValue;
    private const int MinDelayMs = 1200; // ~50 requests/minute

    public async Task<ExternalMetadata?> LookupAsync(string title, string? author, int? year = null, CancellationToken ct = default)
    {
        await _throttle.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            var elapsed = (DateTime.UtcNow - _lastRequest).TotalMilliseconds;
            if (elapsed < MinDelayMs)
                await Task.Delay(MinDelayMs - (int)elapsed, ct).ConfigureAwait(false);

            var audibleResult = await _audibleBookScraper.ScrapeAsync(title, author, year, ct).ConfigureAwait(false);
            var olResult = await TryOpenLibraryAsync(title, author, ct).ConfigureAwait(false);

            ExternalMetadata? result = null;

            // Prefer Audible as the primary source.
            if (audibleResult != null)
            {
                result = new ExternalMetadata
                {
                    Source = "Audible",
                    CoverUrl = audibleResult.CoverUrl,
                    PublishedDate = audibleResult.Year?.ToString(),
                    InfoUrl = audibleResult.AudibleUrl,
                    AudibleInfoUrl = audibleResult.AudibleUrl
                };
            }

            if (result == null)
            {
                result = olResult;
            }
            else if (olResult is not null)
            {
                // Supplement Audible data with Open Library data where available.
                result.Rating ??= olResult.Rating;
                result.RatingCount ??= olResult.RatingCount;
                result.Description ??= olResult.Description;
                result.CoverUrl ??= olResult.CoverUrl;
                // Merge categories from both sources.
                if (olResult.Categories is { Count: > 0 })
                {
                    result.Categories ??= new List<string>();
                    foreach (var cat in olResult.Categories)
                    {
                        if (!result.Categories.Contains(cat, StringComparer.OrdinalIgnoreCase))
                            result.Categories.Add(cat);
                    }
                }
                // Store the Open Library URL separately.
                if (olResult.InfoUrl is not null)
                    result.OpenLibraryInfoUrl = olResult.InfoUrl;
            }

            _lastRequest = DateTime.UtcNow;

            if (result is not null)
                _logger.LogInformation("External metadata found for '{Title}' by '{Author}' via {Source} (rating: {Rating})",
                    title, author ?? "?", result.Source, result.Rating?.ToString("0.0") ?? "none");
            else
                _logger.LogWarning("No external metadata found for '{Title}' by '{Author}'", title, author ?? "?");

            return result;
        }
        finally
        {
            _throttle.Release();
        }
    }

    // ── Open Library ─────────────────────────────────────────────────

    private async Task<ExternalMetadata?> TryOpenLibraryAsync(string title, string? author, CancellationToken ct)
    {
        try
        {
            var url = $"https://openlibrary.org/search.json?title={Uri.EscapeDataString(title)}"
                    + "&fields=key,title,author_name,subject,first_publish_year,cover_i"
                    + "&limit=1";
            if (!string.IsNullOrWhiteSpace(author) && author != "Unknown")
                url += $"&author={Uri.EscapeDataString(author)}";

            var response = await _http.GetAsync(url, ct).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Open Library returned {StatusCode} for '{Title}'", (int)response.StatusCode, title);
                return null;
            }

            var data = await response.Content.ReadFromJsonAsync<OpenLibrarySearchResponse>(ct).ConfigureAwait(false);
            var doc = data?.Docs?.FirstOrDefault();
            if (doc is null) return null;

            string? coverUrl = doc.CoverId > 0
                ? $"https://covers.openlibrary.org/b/id/{doc.CoverId}-L.jpg"
                : null;

            // Fetch description from the works endpoint.
            string? description = null;
            if (!string.IsNullOrWhiteSpace(doc.Key))
            {
                description = await FetchOpenLibraryDescriptionAsync(doc.Key, ct).ConfigureAwait(false);
            }

            // Filter out noisy subjects (NYT lists, overly long ones, etc.)
            var categories = doc.Subjects?
                .Where(s => !s.StartsWith("nyt:", StringComparison.OrdinalIgnoreCase)
                         && s.Length < 60)
                .Take(10)
                .ToList();

            // Fetch ratings from Open Library.
            double? rating = null;
            int? ratingCount = null;
            if (!string.IsNullOrWhiteSpace(doc.Key))
            {
                (rating, ratingCount) = await FetchOpenLibraryRatingAsync(doc.Key, ct).ConfigureAwait(false);
            }

            return new ExternalMetadata
            {
                Source = "OpenLibrary",
                Description = description,
                Categories = categories,
                CoverUrl = coverUrl,
                Rating = rating,
                RatingCount = ratingCount,
                InfoUrl = doc.Key is not null ? $"https://openlibrary.org{doc.Key}" : null
            };
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Open Library lookup failed for '{Title}'", title);
            return null;
        }
    }

    private async Task<string?> FetchOpenLibraryDescriptionAsync(string workKey, CancellationToken ct)
    {
        try
        {
            var url = $"https://openlibrary.org{workKey}.json";
            var response = await _http.GetAsync(url, ct).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode) return null;

            using var doc = await JsonDocument.ParseAsync(
                await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false), cancellationToken: ct)
                .ConfigureAwait(false);

            if (!doc.RootElement.TryGetProperty("description", out var descEl))
                return null;

            // description can be a plain string or an object with a "value" property.
            if (descEl.ValueKind == JsonValueKind.String)
                return descEl.GetString();

            if (descEl.ValueKind == JsonValueKind.Object && descEl.TryGetProperty("value", out var valEl))
                return valEl.GetString();

            return null;
        }
        catch
        {
            return null;
        }
    }

    private async Task<(double? Rating, int? Count)> FetchOpenLibraryRatingAsync(string workKey, CancellationToken ct)
    {
        try
        {
            var url = $"https://openlibrary.org{workKey}/ratings.json";
            var response = await _http.GetAsync(url, ct).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode) return (null, null);

            using var doc = await JsonDocument.ParseAsync(
                await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false), cancellationToken: ct)
                .ConfigureAwait(false);

            if (!doc.RootElement.TryGetProperty("summary", out var summary))
                return (null, null);

            double? average = null;
            int? count = null;

            if (summary.TryGetProperty("average", out var avgEl) && avgEl.ValueKind == JsonValueKind.Number)
                average = avgEl.GetDouble();

            if (summary.TryGetProperty("count", out var cntEl) && cntEl.ValueKind == JsonValueKind.Number)
                count = cntEl.GetInt32();

            if (count is null or 0) return (null, null);

            return (average, count);
        }
        catch
        {
            return (null, null);
        }
    }

    // ── Result DTO ───────────────────────────────────────────────────

    public class ExternalMetadata
    {
        public string Source { get; set; } = default!;
        public string? Description { get; set; }
        public string? Subtitle { get; set; }
        public List<string>? Categories { get; set; }
        public string? CoverUrl { get; set; }
        public string? Publisher { get; set; }
        public string? PublishedDate { get; set; }
        public string? Language { get; set; }
        public string? Isbn10 { get; set; }
        public string? Isbn13 { get; set; }
        public int? PageCount { get; set; }
        public double? Rating { get; set; }
        public int? RatingCount { get; set; }
        public string? InfoUrl { get; set; }
        public string? OpenLibraryInfoUrl { get; set; }
        public string? AudibleInfoUrl { get; set; }
    }

    // ── JSON models ──────────────────────────────────────────────────

    private class OpenLibrarySearchResponse
    {
        [JsonPropertyName("docs")]
        public List<OpenLibraryDoc>? Docs { get; set; }
    }

    private class OpenLibraryDoc
    {
        [JsonPropertyName("key")]
        public string? Key { get; set; }

        [JsonPropertyName("title")]
        public string? Title { get; set; }

        [JsonPropertyName("author_name")]
        public string[]? AuthorName { get; set; }

        [JsonPropertyName("subject")]
        public string[]? Subjects { get; set; }

        [JsonPropertyName("first_publish_year")]
        public int? FirstPublishYear { get; set; }

        [JsonPropertyName("cover_i")]
        public int CoverId { get; set; }
    }
}
