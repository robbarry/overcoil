import Foundation

struct CoverCrop: Codable, Equatable, Sendable {
    // Normalized center coordinates; side is a fraction of the shorter image edge.
    var x: Double = 0.5
    var y: Double = 0.5
    var side: Double = 1
}

struct Watch: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    // Compatibility title for schema-1 clients. New identities use nickname/brand/model.
    // nil nickname means a legacy record: preserve its original name without guessing.
    var name: String
    var brand = ""
    var model = ""
    var notes = ""
    var createdAt = Date()
    var coverID: UUID?
    var crop = CoverCrop()
    var coverWasAutomatic = false
    var nickname: String? = nil

    var displayName: String {
        guard let nickname else { return name }
        let label = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        let maker = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return maker.isEmpty ? model.trimmingCharacters(in: .whitespacesAndNewlines) : maker
    }
    var displaySubtitle: String {
        [brand, model].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.localizedCaseInsensitiveCompare(displayName) != .orderedSame }
            .joined(separator: " · ")
    }
    var editableNickname: String {
        get { nickname ?? name }
        set { nickname = newValue }
    }
    mutating func normalizeIdentity() {
        brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        nickname = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PhotoSource: String, Codable, Sendable { case timing, cameraCover, imported }
struct PhotoAsset: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var watchID: UUID
    var source: PhotoSource
    var savedAt: Date
    var width: Int
    var height: Int
    var orientation: Int
    var capture: CaptureMetadata?
    var fileName: String { "\(id.uuidString).image" }
    var thumbnailName: String { "\(id.uuidString).thumb" }
}

struct CaptureMetadata: Codable, Equatable, Sendable {
    var reference: Date
    var localUTCOffset: Int
    var rawValue: Int64
    var rawTimescale: Int32
    var rawEpoch: Int64
    var hostSeconds: Double
    var anchorHostSeconds: Double
    var anchorWall: Date
    var anchorBracketSeconds: Double
    var mappingResidualSeconds: Double
    // Random identifier scoped to uninterrupted foreground lifetime. Never persists
    // uptime comparability across suspension, relaunch, or reboot.
    var continuityID: UUID
    var clockDiscontinuity: Bool
    var pipeline: String? = nil
    var torchEnabled: Bool? = nil
    var minimumFocusDistanceMM: Int? = nil
    var videoZoomFactor: Double? = nil
}

struct TimingRun: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var watchID: UUID
    var basisUTCOffset: Int
    var createdAt: Date
    var endedAt: Date?
    var endReason: String?
    var clockCompromised = false
    var isActive: Bool { endedAt == nil }
}

struct WatchTime: Codable, Equatable, Sendable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var second: Int
    var utcOffset: Int

    var instant: Date? {
        guard (-64800...64800).contains(utcOffset), (0...23).contains(hour),
              (0...59).contains(minute), (0...59).contains(second),
              let zone = TimeZone(secondsFromGMT: utcOffset) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let d = cal.date(from: c), Self.at(d, offset: utcOffset) == self else { return nil }
        return d
    }

    static func at(_ date: Date, offset: Int) -> Self {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: offset) ?? .gmt
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return Self(year: c.year!, month: c.month!, day: c.day!, hour: c.hour!, minute: c.minute!, second: c.second!, utcOffset: offset)
    }

    static func nearest(hour: Int, minute: Int, second: Int, reference: Date,
                        offset: Int, previousOffset: Double = 0, inferHalfDay: Bool = false) -> Self {
        let expected = reference.addingTimeInterval(previousOffset)
        let hours = inferHalfDay ? [hour % 12, hour % 12 + 12] : [hour]
        let candidates = [-86400.0, 0, 86400].flatMap { shift in
            hours.map { h -> WatchTime in
                var value = Self.at(expected.addingTimeInterval(shift), offset: offset)
                value.hour = h; value.minute = minute; value.second = second
                return value
            }
        }
        return candidates.min { abs(($0.instant ?? .distantPast).timeIntervalSince(expected)) < abs(($1.instant ?? .distantPast).timeIntervalSince(expected)) }!
    }
}

struct Reading: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var runID: UUID
    var photoID: UUID
    var capture: CaptureMetadata
    var entered: WatchTime
    var createdAt: Date
    var updatedAt: Date
    var timingValid = true
    var reference: Date { capture.reference }
    var offset: Double { (entered.instant ?? reference).timeIntervalSince(reference) }
}

struct Database: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var watches: [Watch] = []
    var photos: [PhotoAsset] = []
    var runs: [TimingRun] = []
    var readings: [Reading] = []

    // Display order only: never reorder the persisted collection. Corrections
    // count as activity; capture/reference time remains measurement evidence.
    var watchesByLatestEntry: [Watch] {
        let watchForRun = Dictionary(runs.map { ($0.id, $0.watchID) }, uniquingKeysWith: { first, _ in first })
        var latest: [UUID: Date] = [:]
        for reading in readings {
            guard let watchID = watchForRun[reading.runID] else { continue }
            let activity = max(reading.createdAt, reading.updatedAt)
            latest[watchID] = max(latest[watchID] ?? activity, activity)
        }
        return watches.enumerated().sorted { a, b in
            switch (latest[a.element.id], latest[b.element.id]) {
            case let (left?, right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    func readings(in runID: UUID) -> [Reading] {
        readings.filter { $0.runID == runID }.sorted {
            $0.reference == $1.reference ? $0.id.uuidString < $1.id.uuidString : $0.reference < $1.reference
        }
    }
    func activeRun(for watchID: UUID) -> TimingRun? { runs.first { $0.watchID == watchID && $0.isActive } }
    func photos(for watchID: UUID) -> [PhotoAsset] {
        photos.filter { $0.watchID == watchID }.sorted {
            $0.savedAt == $1.savedAt ? $0.id.uuidString < $1.id.uuidString : $0.savedAt < $1.savedAt
        }
    }
}

struct RunResult: Equatable {
    var elapsed: Double
    var rate: Double?
    var early: Bool { elapsed < 86400 }

    static func calculate(_ readings: [Reading], clockCompromised: Bool = false) -> Self {
        let ordered = readings.filter(\.timingValid).sorted { $0.reference < $1.reference }
        guard let first = ordered.first, let last = ordered.last else { return Self(elapsed: 0, rate: nil) }
        let elapsed = last.reference.timeIntervalSince(first.reference)
        guard !clockCompromised, ordered.count >= 2, elapsed > 0 else { return Self(elapsed: max(0, elapsed), rate: nil) }
        return Self(elapsed: elapsed, rate: (last.offset - first.offset) * 86400 / elapsed)
    }

    static func displayRate(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == 0 ? "0.0" : String(format: "%+.1f", rounded)
    }
    static func displayOffset(_ value: Double) -> String {
        let rounded = abs(value).rounded()
        if rounded == 0 { return "Less than 1 second from phone time" }
        return "\(Int(rounded)) \(rounded == 1 ? "second" : "seconds") \(value > 0 ? "ahead" : "behind")"
    }
}

struct ClockAnchor: Equatable, Sendable {
    var hostSeconds: Double
    var wall: Date
    var bracketSeconds: Double
    func wallTime(for host: Double) -> Date { wall.addingTimeInterval(host - hostSeconds) }
    func residual(to other: Self) -> Double {
        other.wall.timeIntervalSince(wall) - (other.hostSeconds - hostSeconds)
    }
}

// Only prefer an ultra-wide sensor when it actually supports close autofocus.
// Fixed-focus/unknown-distance cameras must not be advertised as macro capable.
enum CaptureLensPolicy {
    static func preferUltraWide(ultraFocusMM: Int, ultraHasAutofocus: Bool, wideFocusMM: Int) -> Bool {
        ultraHasAutofocus && ultraFocusMM > 0 && ultraFocusMM <= 100 && (wideFocusMM <= 0 || ultraFocusMM < wideFocusMM)
    }
}
