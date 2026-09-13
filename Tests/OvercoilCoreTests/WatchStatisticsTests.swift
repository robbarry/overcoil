import XCTest
@testable import OvercoilCore

final class WatchStatisticsTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func reading(runID: UUID, time: Date, offset: Double) -> Reading {
        let capture = CaptureMetadata(reference: time, localUTCOffset: 0, rawValue: 0, rawTimescale: 1, rawEpoch: 0,
                                      hostSeconds: 0, anchorHostSeconds: 0, anchorWall: time, anchorBracketSeconds: 0,
                                      mappingResidualSeconds: 0, continuityID: UUID(), clockDiscontinuity: false)
        return Reading(id: UUID(), runID: runID, photoID: UUID(), capture: capture,
                       entered: .at(time.addingTimeInterval(offset), offset: 0), createdAt: time, updatedAt: time)
    }
    func testDurationWeightedRunsIgnoreResetOffsetsAndEndDates() {
        let watch = Watch(name: "Test")
        let a = TimingRun(watchID: watch.id, basisUTCOffset: 0, createdAt: base, endedAt: base.addingTimeInterval(900000))
        let b = TimingRun(watchID: watch.id, basisUTCOffset: 0, createdAt: base.addingTimeInterval(172800))
        var db = Database(); db.watches = [watch]; db.runs = [a, b]
        db.readings = [reading(runID: a.id, time: base, offset: 5000), reading(runID: a.id, time: base.addingTimeInterval(86400), offset: 5006),
                       reading(runID: b.id, time: base.addingTimeInterval(172800), offset: -6000), reading(runID: b.id, time: base.addingTimeInterval(345600), offset: -5976)]
        let stats = WatchStatistics.calculate(database: db, watchID: watch.id)
        XCTAssertEqual(stats.rate, 10) // (6 s + 24 s) / (1 day + 2 days), NOT (6 + 12) / 2.
        XCTAssertEqual(stats.measuredSeconds, 259200)
        XCTAssertEqual(stats.contributingRunCount, 2); XCTAssertEqual(stats.contributingReadingCount, 4)
        XCTAssertFalse(stats.early)
    }
    func testSingleReadingAndCompromisedRunsDoNotContribute() {
        let watch = Watch(name: "Test"), other = Watch(name: "Same model")
        let good = TimingRun(watchID: watch.id, basisUTCOffset: 0, createdAt: base)
        var compromised = TimingRun(watchID: watch.id, basisUTCOffset: 0, createdAt: base); compromised.clockCompromised = true
        let singleton = TimingRun(watchID: watch.id, basisUTCOffset: 0, createdAt: base)
        let unrelated = TimingRun(watchID: other.id, basisUTCOffset: 0, createdAt: base)
        var db = Database(); db.watches = [watch, other]; db.runs = [good, compromised, singleton, unrelated]
        db.readings = [reading(runID: good.id, time: base, offset: 8), reading(runID: good.id, time: base.addingTimeInterval(43200), offset: 14),
                       reading(runID: compromised.id, time: base, offset: 0), reading(runID: compromised.id, time: base.addingTimeInterval(86400), offset: 10000),
                       reading(runID: singleton.id, time: base.addingTimeInterval(200000), offset: 99999),
                       reading(runID: unrelated.id, time: base, offset: 0), reading(runID: unrelated.id, time: base.addingTimeInterval(86400), offset: -1000)]
        let stats = WatchStatistics.calculate(database: db, watchID: watch.id)
        XCTAssertEqual(stats.rate, 12); XCTAssertEqual(stats.contributingRunCount, 1)
        XCTAssertEqual(stats.contributingReadingCount, 2); XCTAssertEqual(stats.totalReadingCount, 5)
        XCTAssertEqual(stats.lastMeasurementDate, base.addingTimeInterval(43200)); XCTAssertTrue(stats.early)
    }
    func testTwoSingletonRunsCannotEstablishRateAndEditsRecalculate() {
        let watch = Watch(name: "Test")
        let a = TimingRun(watchID: watch.id, basisUTCOffset: 0, createdAt: base)
        let b = TimingRun(watchID: watch.id, basisUTCOffset: 0, createdAt: base)
        var db = Database(); db.watches = [watch]; db.runs = [a, b]
        db.readings = [reading(runID: a.id, time: base, offset: 8), reading(runID: b.id, time: base.addingTimeInterval(86400), offset: 14)]
        XCTAssertNil(WatchStatistics.calculate(database: db, watchID: watch.id).rate)
        db.readings[1].runID = a.id
        XCTAssertEqual(WatchStatistics.calculate(database: db, watchID: watch.id).rate, 6)
        db.readings[1].entered = .at(base.addingTimeInterval(86420), offset: 0)
        XCTAssertEqual(WatchStatistics.calculate(database: db, watchID: watch.id).rate, 12)
        db.readings.removeLast()
        XCTAssertNil(WatchStatistics.calculate(database: db, watchID: watch.id).rate)
    }
}
