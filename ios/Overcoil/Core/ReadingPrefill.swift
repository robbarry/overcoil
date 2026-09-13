import Foundation

// A suggestion only. Never changes the captured reference or creates an observation.
struct ReadingPrefill: Equatable {
    enum Source: Equatable { case phoneClock, lastOffset, measuredRate }
    var instant: Date
    var expectedOffset: Double
    var source: Source
    var rate: Double?

    static func predict(at reference: Date, readings: [Reading], clockCompromised: Bool = false) -> Self {
        let baseline = Self(instant: reference, expectedOffset: 0, source: .phoneClock, rate: nil)
        guard !clockCompromised else { return baseline }
        // Only measurements that existed at this capture instant inform the suggestion.
        let prior = readings.filter { $0.timingValid && !$0.capture.clockDiscontinuity && $0.reference <= reference }
            .sorted { $0.reference < $1.reference }
        guard let last = prior.last else { return baseline }
        let measuredRate = RunResult.calculate(prior).rate
        let elapsed = reference.timeIntervalSince(last.reference)
        let predictedOffset = last.offset + (measuredRate ?? 0) * elapsed / 86400
        guard predictedOffset.isFinite else { return baseline }
        return Self(instant: reference.addingTimeInterval(predictedOffset), expectedOffset: predictedOffset,
                    source: measuredRate == nil ? .lastOffset : .measuredRate, rate: measuredRate)
    }

    var shortLabel: String? {
        switch source {
        case .phoneClock: nil
        case .lastOffset: "Suggested from last offset"
        case .measuredRate: "Suggested from offset + drift"
        }
    }

    var explanation: String {
        switch source {
        case .phoneClock:
            "Prefilled from phone time at capture. It stays frozen while you read the dial."
        case .lastOffset:
            "Suggested from the watch’s last measured offset. Confirm it against the photo; it stays frozen."
        case .measuredRate:
            "Predicted from the last offset and measured drift (\(RunResult.displayRate(rate ?? 0)) s/day). Confirm the dial—this is a suggestion."
        }
    }
}
