import Foundation

enum DurationFormat {
    static func clock(_ seconds: Int) -> String {
        let value = max(0, seconds)
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let secs = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func clock(_ time: TimeInterval) -> String {
        clock(Int(time.rounded(.towardZero)))
    }

    static func short(_ seconds: Int) -> String {
        let value = max(0, seconds)
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(value)s"
    }

    static func short(_ time: TimeInterval) -> String {
        short(Int((time + 0.999).rounded(.towardZero)))
    }
}

enum HTMLText {
    static func plain(_ html: String?) -> String {
        guard var text = html, !text.isEmpty else { return "" }
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'")
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum JWTClaims {
    static func payload(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    static func userID(from token: String) -> Int? {
        let payload = payload(from: token)
        let nameID = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"
        if let value = payload?[nameID] as? String { return Int(value) }
        if let value = payload?[nameID] as? Int { return value }
        if let value = payload?["sub"] as? String { return Int(value) }
        if let value = payload?["sub"] as? Int { return value }
        return nil
    }

    static func isNearExpiry(_ token: String, threshold: TimeInterval = 300) -> Bool {
        guard let payload = payload(from: token) else { return true }
        let exp: TimeInterval
        if let value = payload["exp"] as? TimeInterval {
            exp = value
        } else if let value = payload["exp"] as? Int {
            exp = TimeInterval(value)
        } else {
            return true
        }
        return Date().timeIntervalSince1970 + threshold >= exp
    }
}

enum FileName {
    static func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "book" : trimmed
        return fallback.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    }
}
