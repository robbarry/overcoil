import Foundation

struct WatchStatistics: Equatable {
    var rate: Double?
    var measuredSeconds: Double
    var contributingRunCount: Int
    var contributingReadingCount: Int
    var totalReadingCount: Int
    var longestRunSeconds: Double
    var lastMeasurementDate: Date?
    var latestReading: Reading?
    var early: Bool { longestRunSeconds < 86400 }

    static func calculate(database: Database, watchID: UUID) -> Self {
        let runs = database.runs.filter { $0.watchID == watchID }
        let runIDs = Set(runs.map(\.id))
        let allReadings = database.readings.filter { runIDs.contains($0.runID) }
        var result = Self(rate: nil, measuredSeconds: 0, contributingRunCount: 0, contributingReadingCount: 0,
                          totalReadingCount: allReadings.count, longestRunSeconds: 0, lastMeasurementDate: nil,
                          latestReading: allReadings.max { $0.reference < $1.reference })
        var totalDrift = 0.0
        for run in runs where !run.clockCompromised {
            let readings = database.readings(in: run.id).filter { $0.timingValid && !$0.capture.clockDiscontinuity }
            guard readings.count >= 2, let first = readings.first, let last = readings.last else { continue }
            let elapsed = last.reference.timeIntervalSince(first.reference)
            guard elapsed > 0 else { continue }
            // Only differences WITHIN continuous runs are pooled. Initial offsets
            // after resetting the hands have no bearing on the overall rate.
            totalDrift += last.offset - first.offset
            result.measuredSeconds += elapsed
            result.longestRunSeconds = max(result.longestRunSeconds, elapsed)
            result.contributingRunCount += 1
            result.contributingReadingCount += readings.count
            result.lastMeasurementDate = max(result.lastMeasurementDate ?? last.reference, last.reference)
        }
        if result.measuredSeconds > 0 { result.rate = totalDrift * 86400 / result.measuredSeconds }
        return result
    }

    var durationText: String {
        if measuredSeconds < 3600 { return String(format: "%.0f min", measuredSeconds / 60) }
        if measuredSeconds < 172800 { return String(format: "%.1f h", measuredSeconds / 3600) }
        return String(format: "%.1f days", measuredSeconds / 86400)
    }
    var supportText: String {
        "\(contributingReadingCount) readings · \(contributingRunCount) \(contributingRunCount == 1 ? "run" : "runs") · \(durationText) measured"
    }
}
