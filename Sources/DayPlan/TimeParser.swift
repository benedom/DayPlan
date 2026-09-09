import Foundation

/// Parses free-form duration input ("1.5h", "1,5 h", "90 min", "1h30", "1:30",
/// a bare "45") into whole minutes, snapped to the nearest 15-minute step.
/// 15 minutes is also the floor: anything that would round to zero (under 7.5
/// minutes, e.g. "5 min" or "2m") is lifted to one unit rather than discarded.
enum TimeParser {
    static func parseMinutes(_ input: String) -> Int? {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return nil }
        // European decimal comma reads the same as a dot here.
        let normalized = raw.replacingOccurrences(of: ",", with: ".")

        let minutes: Double
        if let combined = matchHoursAndMinutes(normalized) {
            minutes = combined
        } else if let clock = matchClock(normalized) {
            minutes = clock
        } else if let hours = matchUnit(normalized, word: #"h(?:ours?|rs?)?"#) {
            minutes = hours * 60
        } else if let mins = matchUnit(normalized, word: #"m(?:in(?:utes?)?)?"#) {
            minutes = mins
        } else if let bare = Double(normalized) {
            // No unit at all: read as plain minutes, the fastest thing to type.
            minutes = bare
        } else {
            return nil
        }

        // `Int(Double)` traps on infinite or out-of-Int64 values, and the bare
        // number branch above reaches both: `Double("inf")`, `Double("1e300")`
        // and a pasted twenty-digit number all parse. Reject them here rather
        // than let the conversion below crash the app mid-keystroke.
        guard minutes > 0, minutes.isFinite, minutes <= Double(maxMinutes) else { return nil }
        let stepped = Int((minutes / 15).rounded()) * 15
        return max(15, stepped)
    }

    /// Only a guard against typos and paste accidents, deliberately far above
    /// any duration worth logging, so no plausible input changes meaning.
    private static let maxMinutes = 10_000 * 60

    /// "1h30", "1h30m", "1 h 30 min"
    private static func matchHoursAndMinutes(_ s: String) -> Double? {
        let pattern = #"^(\d+(?:\.\d+)?)\s*h(?:ours?|rs?)?\s*(\d+(?:\.\d+)?)\s*m?(?:in(?:utes?)?)?$"#
        guard let groups = firstMatch(pattern, in: s),
              let h = Double(groups[1]), let m = Double(groups[2]) else { return nil }
        return h * 60 + m
    }

    /// "1:30"
    private static func matchClock(_ s: String) -> Double? {
        let pattern = #"^(\d+):([0-5]?\d)$"#
        guard let groups = firstMatch(pattern, in: s),
              let h = Double(groups[1]), let m = Double(groups[2]) else { return nil }
        return h * 60 + m
    }

    /// "0.5h", "2 hours", "30min", "45 m"
    private static func matchUnit(_ s: String, word: String) -> Double? {
        let pattern = "^(\\d+(?:\\.\\d+)?)\\s*\(word)$"
        guard let groups = firstMatch(pattern, in: s), let value = Double(groups[1]) else { return nil }
        return value
    }

    private static func firstMatch(_ pattern: String, in s: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
        else { return nil }
        return (0..<match.numberOfRanges).map {
            guard let range = Range(match.range(at: $0), in: s) else { return "" }
            return String(s[range])
        }
    }
}
