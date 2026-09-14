import Foundation

enum ReadingAge {
    static func label(since date: Date, now: Date, spoken: Bool = false) -> String {
        let seconds = now.timeIntervalSince(date)
        let magnitude = abs(seconds)
        guard magnitude >= 60 else { return "Last reading just now" }
        let units: [(Double, String, String)] = [(31536000, "y", "year"), (2592000, "mo", "month"),
                                                (604800, "w", "week"), (86400, "d", "day"),
                                                (3600, "h", "hour"), (60, "m", "minute")]
        let unit = units.first { magnitude >= $0.0 }!
        let count = Int(magnitude / unit.0)
        let amount = spoken ? "\(count) \(unit.2)\(count == 1 ? "" : "s")" : "\(count)\(unit.1)"
        return seconds < 0 ? "Last reading in \(amount)" : "Last reading \(amount) ago"
    }
}

// Measured offsets at actual capture spacing—not interval rates, a fitted curve,
// or an uncertainty estimate. These are derived values; no evidence is modified.
struct RunPlot {
    struct Point {
        var id: UUID
        var x: Double
        var y: Double
        var offset: Double
        var valid: Bool
    }
    var points: [Point]
    var lower: Double
    var upper: Double
    var elapsed: Double
    var change: Double?
    var clockCompromised: Bool

    init(readings: [Reading], clockCompromised: Bool = false) {
        self.clockCompromised = clockCompromised
        let ordered = readings.filter { $0.reference.timeIntervalSince1970.isFinite && $0.offset.isFinite }.sorted {
            $0.reference == $1.reference ? $0.id.uuidString < $1.id.uuidString : $0.reference < $1.reference
        }
        let minimum = ordered.map(\.offset).min() ?? 0
        let maximum = ordered.map(\.offset).max() ?? 0
        let padding = max(2, (maximum - minimum) * 0.15)
        let low = floor(minimum - padding), high = ceil(maximum + padding)
        let span = max(0, (ordered.last?.reference ?? .distantPast).timeIntervalSince(ordered.first?.reference ?? .distantPast))
        lower = low; upper = high; elapsed = span
        let start = ordered.first?.reference ?? .distantPast
        points = ordered.map {
            Point(id: $0.id, x: span > 0 ? $0.reference.timeIntervalSince(start) / span : 0.5,
                  y: 1 - ($0.offset - low) / (high - low), offset: $0.offset,
                  valid: $0.timingValid && !$0.capture.clockDiscontinuity)
        }
        change = !clockCompromised && points.count > 1 && elapsed > 0 && points.allSatisfy(\.valid)
            ? points.last!.offset - points.first!.offset : nil
    }

    func connects(_ index: Int) -> Bool {
        guard !clockCompromised, index > 0, index < points.count else { return false }
        return points[index - 1].valid && points[index].valid && points[index].x > points[index - 1].x
    }

    static func seconds(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == 0 ? "0s" : String(format: "%+.1fs", rounded)
    }

    var duration: String {
        let minutes = Int(elapsed / 60), hours = minutes / 60, days = hours / 24
        if days > 0 { return "\(days)d\(hours % 24 == 0 ? "" : " \(hours % 24)h")" }
        if hours > 0 { return "\(hours)h\(minutes % 60 == 0 ? "" : " \(minutes % 60)m")" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(Int(elapsed))s"
    }
}
