import Testing
@testable import DayPlan

@Suite("TimeParser")
struct TimeParserTests {
    @Test("Documented formats parse to whole minutes", arguments: [
        ("1.5h", 90), ("1,5 h", 90), ("90 min", 90), ("1h30", 90), ("1:30", 90),
        ("45", 45), ("2h", 120), ("0.5h", 30), ("30min", 30), ("45 m", 45),
        ("1h 30 min", 90), ("1 h 30", 90), ("2 hours", 120), ("  2H  ", 120)
    ])
    func documentedFormats(input: String, expected: Int) {
        #expect(TimeParser.parseMinutes(input) == expected)
    }

    @Test("Every result lands on the 15-minute grid", arguments: ["7", "23", "38", "52", "1:07", "3.4h"])
    func snapsToGrid(input: String) throws {
        let minutes = try #require(TimeParser.parseMinutes(input))
        #expect(minutes % 15 == 0)
    }

    @Test("A positive duration is lifted to one unit rather than discarded")
    func floorsToOneUnit() {
        #expect(TimeParser.parseMinutes("5 min") == 15)
        #expect(TimeParser.parseMinutes("2m") == 15)
        #expect(TimeParser.parseMinutes("0.0001h") == 15)
    }

    @Test("Non-durations are rejected", arguments: [
        "", "   ", "abc", "0", "-30", "nan", "1:99", "h", "1.5.5", "1h30x"
    ])
    func rejectsNonDurations(input: String) {
        #expect(TimeParser.parseMinutes(input) == nil)
    }

    /// Regression guard. Each of these used to reach `Int(Double)` with an
    /// infinite or out-of-Int64 value and trap, crashing the app *while the
    /// user was still typing* (the field parses on every keystroke to drive
    /// its enabled state). One case per parse branch, so a future refactor
    /// that validates per-branch instead of at the choke point still fails.
    @Test("Out-of-range input is rejected instead of trapping", arguments: [
        "99999999999999999999",     // bare number
        "99999999999999999999.5",   // bare decimal
        "1e300", "1e400",           // exponent notation
        "inf", "infinity",          // Double accepts both
        "999999999999999999999h",   // matchUnit, hours
        "999999999999999999999m",   // matchUnit, minutes
        "99999999999999999999h30",  // matchHoursAndMinutes
        "99999999999999999999:30"   // matchClock
    ])
    func rejectsOutOfRangeInsteadOfTrapping(input: String) {
        #expect(TimeParser.parseMinutes(input) == nil)
    }

    @Test("The overflow cap sits far above any real duration")
    func capBoundary() {
        #expect(TimeParser.parseMinutes("10000h") == 600_000)
        #expect(TimeParser.parseMinutes("10001h") == nil)
    }
}

@Suite("TimeFormatter")
struct TimeFormatterTests {
    @Test("shortLabel drops empty components", arguments: [
        (0, "0m"), (15, "15m"), (45, "45m"), (60, "1h"), (90, "1h 30m"), (135, "2h 15m"), (1440, "24h")
    ])
    func shortLabel(minutes: Int, expected: String) {
        #expect(TimeFormatter.shortLabel(minutes: minutes) == expected)
    }

    /// The decimal separator follows the user's locale by design, so assert the
    /// shape rather than the glyph — this must not fail on a German machine.
    @Test("hoursLabel is exact on the 15-minute grid in any locale")
    func hoursLabel() {
        #expect(TimeFormatter.hoursLabel(minutes: 120) == "2h")
        for (minutes, fraction) in [(90, "5"), (135, "25"), (105, "75")] {
            let label = TimeFormatter.hoursLabel(minutes: minutes)
            #expect(label.hasSuffix("h"))
            #expect(label.contains(fraction), "\(minutes)m produced \(label)")
        }
    }
}
