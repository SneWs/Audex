using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Components;

namespace Grenis.AudioBooks.Client;

public static partial class HtmlSanitizer
{
    private static readonly HashSet<string> AllowedTags = new(StringComparer.OrdinalIgnoreCase)
    {
        "b", "i", "em", "strong", "br"
    };

    [GeneratedRegex(@"<(/?)(\w+)(\s[^>]*)?>", RegexOptions.IgnoreCase)]
    private static partial Regex TagRegex();

    public static MarkupString SanitizeToMarkup(string? html)
    {
        if (string.IsNullOrWhiteSpace(html))
            return new MarkupString(string.Empty);

        var sanitized = TagRegex().Replace(html, match =>
        {
            var tagName = match.Groups[2].Value;
            if (!AllowedTags.Contains(tagName))
                return string.Empty;

            var slash = match.Groups[1].Value;
            // Self-closing br
            if (tagName.Equals("br", StringComparison.OrdinalIgnoreCase))
                return "<br />";

            return $"<{slash}{tagName}>";
        });

        return new MarkupString(sanitized);
    }
}
