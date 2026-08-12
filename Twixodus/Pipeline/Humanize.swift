// A faithful port of Python humanize.naturaldelta() (the subset the pipeline
// can hit), so "(sent two hours later)"-style notes come out byte-identical
// to the original script's output. Ported from humanize 4.x — note the
// round() calls, which use Python semantics (half-to-even).

import Foundation

enum Humanize {

    /// Python round(): banker's rounding, unlike Swift's default .rounded().
    private static func pyRound(_ value: Double) -> Int {
        Int(value.rounded(.toNearestOrEven))
    }

    /// humanize.naturaldelta(timedelta) with months enabled (the default).
    static func naturalDelta(_ interval: TimeInterval) -> String {
        let total = Int(abs(interval))
        // Mirror Python's timedelta normalization: .days and the leftover
        // in-day .seconds.
        let days = total / 86_400
        let seconds = total % 86_400

        let years = days / 365
        let remainingDays = days % 365
        let months = pyRound(Double(remainingDays) / 30.5)

        if years == 0 && days < 1 {
            if seconds == 0 { return "a moment" }
            if seconds == 1 { return "a second" }
            if seconds < 60 { return plural(seconds, "second") }
            if seconds < 3600 {
                let minutes = pyRound(Double(seconds) / 60)
                if minutes == 1 { return "a minute" }
                if minutes == 60 { return "an hour" }
                return plural(minutes, "minute")
            }
            let hours = pyRound(Double(seconds) / 3600)
            if hours == 1 { return "an hour" }
            if hours == 24 { return "a day" }
            return plural(hours, "hour")
        }
        if years == 0 {
            if remainingDays == 1 { return "a day" }
            if months == 0 { return plural(remainingDays, "day") }
            if months == 1 { return "a month" }
            if months == 12 { return "a year" }
            return plural(months, "month")
        }
        if years == 1 {
            if months == 0 && remainingDays == 0 { return "a year" }
            if months == 0 { return "1 year, " + plural(remainingDays, "day") }
            if months == 1 { return "1 year, 1 month" }
            if months == 12 { return "2 years" }
            return "1 year, \(months) months"
        }
        return plural(years, "year")
    }

    private static func plural(_ count: Int, _ unit: String) -> String {
        count == 1 ? "\(count) \(unit)" : "\(count) \(unit)s"
    }
}
