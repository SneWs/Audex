using System.Text.RegularExpressions;
using HtmlAgilityPack;

namespace Grenis.AudioBooks.Server;

public interface IAudibleBookScraper
{
    Task<AudibleBookScrapeResult?> ScrapeAsync(string title, string? author = null, int? year = null, CancellationToken ct = default);
}

public class AudibleBookScrapeResult
{
    public string? Title { get; init; }
    public string? Author { get; init; }
    public int? Year { get; init; }
    public string? CoverUrl { get; init; }
    public string? AudibleUrl { get; init; }
}

public class AudibleBookScraper : IAudibleBookScraper
{
    private static readonly Regex MultiSpace = new("\\s+", RegexOptions.Compiled);
    private static readonly Regex YearRegex = new("\\b(19|20)\\d{2}\\b", RegexOptions.Compiled);

    private readonly HttpClient _http;
    private readonly ILogger<AudibleBookScraper> _logger;

    public AudibleBookScraper(HttpClient http, ILogger<AudibleBookScraper> logger)
    {
        _http = http;
        _logger = logger;
    }

    public async Task<AudibleBookScrapeResult?> ScrapeAsync(string title, string? author = null, int? year = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(title))
            return null;

        var terms = title.Trim();
        if (!string.IsNullOrWhiteSpace(author) && !string.Equals(author, "Unknown", StringComparison.OrdinalIgnoreCase))
            terms += " " + author.Trim();
        if (year != null)
            terms += " " + year.Value;

        var url = $"https://www.audible.co.uk/search?keywords={Uri.EscapeDataString(terms)}";
        _logger.LogInformation(
            "Audible scrape starting. Title='{Title}', Author='{Author}', Year={Year}, Url='{Url}'",
            title,
            author ?? "?",
            year,
            url);

        try
        {
            var response = await _http.GetAsync(url, ct).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogDebug("Audible returned {Status} for query '{Title}'", (int)response.StatusCode, title);
                return null;
            }

            var html = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(html))
                return null;

            var doc = new HtmlDocument();
            doc.LoadHtml(html);

            var candidates = doc.DocumentNode.SelectNodes("//a[contains(@href,'/pd/')]");
            if (candidates == null || candidates.Count == 0)
            {
                _logger.LogInformation(
                    "Audible scrape found no '/pd/' candidates. Title='{Title}', Author='{Author}', Year={Year}",
                    title,
                    author ?? "?",
                    year);
                return null;
            }

            _logger.LogDebug(
                "Audible scrape found {CandidateCount} raw candidates for Title='{Title}'",
                candidates.Count,
                title);

            var bestScore = int.MinValue;
            AudibleBookScrapeResult? best = null;
            var scoredCandidates = new List<(int Score, string? Title, string? Author, int? Year, string Url)>();

            foreach (var link in candidates.Take(40))
            {
                var href = link.GetAttributeValue("href", string.Empty);
                var absoluteUrl = ToAbsoluteUrl(href);
                if (string.IsNullOrWhiteSpace(absoluteUrl))
                    continue;

                var container = link.Ancestors()
                    .FirstOrDefault(n => n.Name == "li" || n.Name == "article") ?? link.ParentNode;

                var candidateTitle = ExtractCandidateTitle(link, container);
                var candidateAuthor = ExtractCandidateAuthor(container);
                var candidateYear = ExtractCandidateYear(container);
                var candidateCover = ExtractCandidateCover(container);

                var score = ScoreCandidate(candidateTitle, candidateAuthor, candidateYear, title, author, year);
                scoredCandidates.Add((score, candidateTitle, candidateAuthor, candidateYear, absoluteUrl));
                if (score <= bestScore)
                    continue;

                bestScore = score;
                best = new AudibleBookScrapeResult
                {
                    Title = candidateTitle,
                    Author = candidateAuthor,
                    Year = candidateYear,
                    CoverUrl = candidateCover,
                    AudibleUrl = absoluteUrl
                };
            }

            foreach (var entry in scoredCandidates
                .OrderByDescending(x => x.Score)
                .Take(5))
            {
                _logger.LogDebug(
                    "Audible candidate score={Score}, title='{CandidateTitle}', author='{CandidateAuthor}', year={CandidateYear}, url='{Url}'",
                    entry.Score,
                    entry.Title ?? "?",
                    entry.Author ?? "?",
                    entry.Year,
                    entry.Url);
            }

            if (best == null || bestScore < 20)
            {
                _logger.LogInformation(
                    "Audible scrape found no confident match. BestScore={BestScore}, Title='{Title}', Author='{Author}', Year={Year}",
                    bestScore,
                    title,
                    author ?? "?",
                    year);
                return null;
            }

            _logger.LogInformation(
                "Audible scrape matched. Score={Score}, MatchedTitle='{MatchedTitle}', MatchedAuthor='{MatchedAuthor}', MatchedYear={MatchedYear}, Url='{Url}'",
                bestScore,
                best.Title ?? "?",
                best.Author ?? "?",
                best.Year,
                best.AudibleUrl ?? "?");

            return best;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Audible scrape failed for '{Title}'", title);
            return null;
        }
    }

    private static string? ExtractCandidateTitle(HtmlNode link, HtmlNode? container)
    {
        var aria = CleanText(link.GetAttributeValue("aria-label", string.Empty));
        if (!string.IsNullOrWhiteSpace(aria))
            return aria;

        var fromHeading = CleanText(container?.SelectSingleNode(".//h2|.//h3")?.InnerText ?? string.Empty);
        if (!string.IsNullOrWhiteSpace(fromHeading))
            return fromHeading;

        var fromLink = CleanText(link.InnerText);
        return string.IsNullOrWhiteSpace(fromLink) ? null : fromLink;
    }

    private static string? ExtractCandidateAuthor(HtmlNode? container)
    {
        if (container == null)
            return null;

        var authorNode = container.SelectSingleNode(".//a[contains(@href,'searchAuthor')]")
            ?? container.SelectSingleNode(".//*[contains(@class,'author')]//a")
            ?? container.SelectSingleNode(".//*[contains(@class,'author')]");

        var value = CleanText(authorNode?.InnerText ?? string.Empty);
        return string.IsNullOrWhiteSpace(value) ? null : value;
    }

    private static int? ExtractCandidateYear(HtmlNode? container)
    {
        if (container == null)
            return null;

        var text = CleanText(container.InnerText);
        if (string.IsNullOrWhiteSpace(text))
            return null;

        var m = YearRegex.Match(text);
        if (!m.Success)
            return null;

        return int.TryParse(m.Value, out var y) ? y : null;
    }

    private static string? ExtractCandidateCover(HtmlNode? container)
    {
        if (container == null)
            return null;

        var img = container.SelectSingleNode(".//img");
        if (img == null)
            return null;

        var src = img.GetAttributeValue("src", string.Empty);
        if (string.IsNullOrWhiteSpace(src))
            src = img.GetAttributeValue("data-src", string.Empty);
        if (string.IsNullOrWhiteSpace(src))
            src = img.GetAttributeValue("data-lazy", string.Empty);

        return ToAbsoluteUrl(src);
    }

    private static string? ToAbsoluteUrl(string? url)
    {
        if (string.IsNullOrWhiteSpace(url))
            return null;

        if (url.StartsWith("//", StringComparison.Ordinal))
            return "https:" + url;

        if (Uri.TryCreate(url, UriKind.Absolute, out var absolute))
            return absolute.ToString();

        if (url.StartsWith("/", StringComparison.Ordinal))
            return "https://www.audible.co.uk" + url;

        return null;
    }

    private static int ScoreCandidate(string? candidateTitle, string? candidateAuthor, int? candidateYear, string requestedTitle, string? requestedAuthor, int? requestedYear)
    {
        var score = 0;

        var normalizedRequestedTitle = Normalize(requestedTitle);
        var normalizedCandidateTitle = Normalize(candidateTitle);

        if (!string.IsNullOrWhiteSpace(normalizedCandidateTitle) && !string.IsNullOrWhiteSpace(normalizedRequestedTitle))
        {
            if (normalizedCandidateTitle.Contains(normalizedRequestedTitle, StringComparison.OrdinalIgnoreCase))
                score += 60;

            score += TokenOverlapScore(normalizedRequestedTitle, normalizedCandidateTitle, 40);
        }

        if (!string.IsNullOrWhiteSpace(requestedAuthor) && !string.Equals(requestedAuthor, "Unknown", StringComparison.OrdinalIgnoreCase))
        {
            var normalizedRequestedAuthor = Normalize(requestedAuthor);
            var normalizedCandidateAuthor = Normalize(candidateAuthor);
            if (!string.IsNullOrWhiteSpace(normalizedCandidateAuthor) && normalizedCandidateAuthor.Contains(normalizedRequestedAuthor, StringComparison.OrdinalIgnoreCase))
                score += 20;
            else
                score -= 8;
        }

        if (requestedYear != null)
        {
            if (candidateYear == requestedYear)
                score += 20;
            else if (candidateYear != null)
                score -= 5;
        }

        return score;
    }

    private static int TokenOverlapScore(string left, string right, int maxScore)
    {
        var leftTokens = left.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Where(t => t.Length > 2)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (leftTokens.Length == 0)
            return 0;

        var matched = leftTokens.Count(t => right.Contains(t, StringComparison.OrdinalIgnoreCase));
        return (int)Math.Round((double)matched / leftTokens.Length * maxScore);
    }

    private static string Normalize(string? value)
    {
        var clean = CleanText(value ?? string.Empty).ToLowerInvariant();
        return clean;
    }

    private static string CleanText(string value)
    {
        var decoded = HtmlEntity.DeEntitize(value ?? string.Empty).Trim();
        return MultiSpace.Replace(decoded, " ");
    }
}