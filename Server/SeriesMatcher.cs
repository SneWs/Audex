using System.Text.RegularExpressions;

namespace Grenis.AudioBooks.Server;

public readonly record struct SeriesMembership(int BookId, int Number);

public readonly record struct SeriesGroup(string Name, IReadOnlyList<SeriesMembership> Books);

public static class SeriesMatcher
{
    // HH01 - Title, HHA01 - Title, SoS1 - Title, WoS2 - Title
    private static readonly Regex CodeNumberDash = new(
        @"^(?<series>[A-Za-z]{2,10})(?<num>\d{1,3})\s*[-–:]\s*(?<rest>.+)$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    // Eagles of the Empire [01] Title
    private static readonly Regex NameBracketNumber = new(
        @"^(?<series>.+?)\s*\[(?<num>\d{1,3})\]\s*(?<rest>.+)$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    // Simon Scarrow [Eagles of the Empire 21] Title
    private static readonly Regex BracketSeriesNumber = new(
        @"^.*?\s*\[(?<series>.+?)\s+(?<num>\d{1,3})\]\s*(?<rest>.+)$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    // Honor Harrington 01 - Title
    private static readonly Regex NameNumberDash = new(
        @"^(?<series>.+?)\s+(?<num>\d{1,3})\s*[-–:]\s*(?<rest>.+)$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public static IReadOnlyList<SeriesGroup> GroupBooks(
        IEnumerable<(int Id, string FolderPath, string Title, string? CustomTitle)> books)
    {
        var buckets = new Dictionary<string, (string DisplayName, List<SeriesMembership> Members)>(
            StringComparer.OrdinalIgnoreCase);

        foreach (var book in books)
        {
            if (!TryAssignSeries(book, out var seriesName, out var number))
                continue;

            var key = seriesName.ToLowerInvariant();
            if (!buckets.TryGetValue(key, out var bucket))
            {
                bucket = (seriesName, new List<SeriesMembership>());
                buckets[key] = bucket;
            }

            bucket.Members.Add(new SeriesMembership(book.Id, number));
        }

        return buckets.Values
            .Where(bucket => bucket.Members.Count >= 2)
            .Select(bucket => new SeriesGroup(
                bucket.DisplayName,
                bucket.Members
                    .OrderBy(member => member.Number)
                    .ThenBy(member => member.BookId)
                    .ToList()))
            .OrderBy(group => group.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public static bool TryParse(string name, out string seriesName, out int number)
    {
        seriesName = "";
        number = 0;
        if (string.IsNullOrWhiteSpace(name))
            return false;

        var value = name.Trim();
        if (TryMatch(CodeNumberDash, value, out seriesName, out number))
            return true;
        if (TryMatch(NameBracketNumber, value, out seriesName, out number))
            return true;
        if (TryMatch(BracketSeriesNumber, value, out seriesName, out number))
            return true;
        if (TryMatch(NameNumberDash, value, out seriesName, out number)
            && seriesName.Any(char.IsLetter))
            return true;

        return false;
    }

    private static bool TryAssignSeries(
        (int Id, string FolderPath, string Title, string? CustomTitle) book,
        out string seriesName,
        out int number)
    {
        foreach (var candidate in CandidateNames(book.FolderPath, book.CustomTitle, book.Title))
        {
            if (TryParse(candidate, out seriesName, out number))
                return true;
        }

        seriesName = "";
        number = 0;
        return false;
    }

    private static IEnumerable<string> CandidateNames(string folderPath, string? customTitle, string title)
    {
        var folderName = folderPath.Replace('\\', '/').Split('/', StringSplitOptions.RemoveEmptyEntries).LastOrDefault();
        if (!string.IsNullOrWhiteSpace(folderName))
            yield return folderName;
        if (!string.IsNullOrWhiteSpace(customTitle))
            yield return customTitle;
        if (!string.IsNullOrWhiteSpace(title))
            yield return title;
    }

    private static bool TryMatch(Regex regex, string value, out string seriesName, out int number)
    {
        seriesName = "";
        number = 0;
        var match = regex.Match(value);
        if (!match.Success)
            return false;

        var rawName = Regex.Replace(match.Groups["series"].Value.Trim(), @"\s+", " ");
        if (rawName.Length < 2 || !int.TryParse(match.Groups["num"].Value, out number) || number < 1)
            return false;

        seriesName = rawName;
        return true;
    }
}
