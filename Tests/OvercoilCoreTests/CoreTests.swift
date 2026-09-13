import XCTest
@testable import OvercoilCore

final class CoreTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func capture(_ t: Date, continuity: UUID = UUID(), discontinuity: Bool = false) -> CaptureMetadata {
        CaptureMetadata(reference: t, localUTCOffset: -14400, rawValue: 123, rawTimescale: 1000, rawEpoch: 0, hostSeconds: t.timeIntervalSince1970, anchorHostSeconds: t.timeIntervalSince1970, anchorWall: t, anchorBracketSeconds: 0.0001, mappingResidualSeconds: 0, continuityID: continuity, clockDiscontinuity: discontinuity)
    }
    func reading(_ reference: Date, offset: Int) -> Reading {
        Reading(id: UUID(), runID: UUID(), photoID: UUID(), capture: capture(reference), entered: .at(reference.addingTimeInterval(Double(offset)), offset: 0), createdAt: start, updatedAt: start)
    }
    func repository() throws -> Repository {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("overcoil-test-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try Repository(root: root)
    }
    @discardableResult func save(_ repo: Repository, watch: UUID, time: Date, offset: Int = 8, id: UUID = UUID(), discontinuity: Bool = false) throws -> UUID {
        let c = capture(time, discontinuity: discontinuity)
        let p = PhotoAsset(id: UUID(), watchID: watch, source: .timing, savedAt: time, width: 1, height: 1, orientation: 1, capture: c)
        return try repo.saveReading(id: id, watchID: watch, expectedRunID: repo.database.activeRun(for: watch)?.id, photo: p, bytes: Data([1]), thumbnail: Data([2]), entered: .at(time.addingTimeInterval(Double(offset)), offset: 0))
    }
    func testRatesAndNoRateWithOneOrZeroElapsed() {
        let first = reading(start, offset: 8)
        XCTAssertNil(RunResult.calculate([first]).rate)
        XCTAssertNil(RunResult.calculate([first, first]).rate)
        XCTAssertEqual(RunResult.calculate([reading(start.addingTimeInterval(86400), offset: 14), first]).rate, 6)
        XCTAssertEqual(RunResult.calculate([first, reading(start.addingTimeInterval(43200), offset: 14)]).rate, 12)
        XCTAssertEqual(RunResult.calculate([first, reading(start.addingTimeInterval(3600), offset: 100), reading(start.addingTimeInterval(86400), offset: 14)]).rate, 6)
        XCTAssertNil(RunResult.calculate([first, reading(start.addingTimeInterval(86400), offset: 14)], clockCompromised: true).rate)
        XCTAssertEqual(RunResult.displayRate(-0.01), "0.0")
    }
    func testMidnightYearRolloverAndNoon() throws {
        let ref = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-01-01T00:00:02Z"))
        let near = WatchTime.nearest(hour: 23, minute: 59, second: 58, reference: ref, offset: 0)
        XCTAssertEqual(near.year, 2026); XCTAssertEqual(near.month, 12); XCTAssertEqual(near.day, 31)
        XCTAssertEqual(try XCTUnwrap(near.instant).timeIntervalSince(ref), -4)
        let noon = WatchTime.at(ref.addingTimeInterval(43200), offset: 0)
        XCTAssertEqual(noon.hour, 12)
        let next = WatchTime.nearest(hour: 0, minute: 0, second: 3, reference: ref.addingTimeInterval(-4), offset: 0)
        XCTAssertEqual(try XCTUnwrap(next.instant).timeIntervalSince(ref), 1)
    }
    func testTwelveHourNoonInference() throws {
        let ref = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-13T11:59:58Z"))
        let noon = WatchTime.nearest(hour: 12, minute: 0, second: 2, reference: ref, offset: 0, inferHalfDay: true)
        XCTAssertEqual(noon.hour, 12)
        XCTAssertEqual(try XCTUnwrap(noon.instant).timeIntervalSince(ref), 4)
        let midnightRef = ref.addingTimeInterval(43200)
        let midnight = WatchTime.nearest(hour: 12, minute: 0, second: 2, reference: midnightRef, offset: 0, inferHalfDay: true)
        XCTAssertEqual(midnight.hour, 0)
        XCTAssertEqual(try XCTUnwrap(midnight.instant).timeIntervalSince(midnightRef), 4)
    }
    func testFixedOffsetTravelAndPreviousOffset() throws {
        let initial = WatchTime.at(start, offset: -14400)
        XCTAssertEqual(initial.instant, start)
        let travel = WatchTime.at(start, offset: 32400)
        XCTAssertNotEqual(initial.hour, travel.hour)
        XCTAssertEqual(WatchTime.at(start, offset: -14400), initial)
        let expected = start.addingTimeInterval(18 * 3600)
        let parts = WatchTime.at(expected, offset: 0)
        let inferred = WatchTime.nearest(hour: parts.hour, minute: parts.minute, second: parts.second, reference: start, offset: 0, previousOffset: 18 * 3600)
        XCTAssertEqual(inferred.instant, expected)
        var bad = initial; bad.month = 2; bad.day = 30
        XCTAssertNil(bad.instant)
    }
    func testContinuityTokenDoesNotCrossSuspensionOrProcessLifetime() {
        let tracker = ClockContinuity()
        let initial = ClockAnchor(hostSeconds: 100, wall: start, bracketSeconds: 0.001)
        let (token, changed) = tracker.inspect(initial)
        XCTAssertFalse(changed); XCTAssertTrue(tracker.isCurrent(token))
        let (_, jumped) = tracker.inspect(ClockAnchor(hostSeconds: 110, wall: start.addingTimeInterval(15), bracketSeconds: 0.001))
        XCTAssertTrue(jumped)
        tracker.reset()
        XCTAssertFalse(tracker.isCurrent(token))
        let (newToken, afterReset) = tracker.inspect(ClockAnchor(hostSeconds: 1, wall: start.addingTimeInterval(10000), bracketSeconds: 0))
        XCTAssertNotEqual(token, newToken); XCTAssertFalse(afterReset)
        XCTAssertFalse(ClockContinuity().isCurrent(newToken))
    }
    func testCyclicSecondsWrapWithoutChangingOtherFields() {
        let original = WatchTime(year: 2026, month: 9, day: 13, hour: 12, minute: 0, second: 59, utcOffset: 0)
        let one = TimeWheelMath.value(forRow: 961, period: 60)
        XCTAssertEqual(one, 1)
        let selected = TimeWheelMath.selecting(one, component: 2, in: original, twelveHour: true)
        XCTAssertEqual(selected.hour, 12); XCTAssertEqual(selected.minute, 0); XCTAssertEqual(selected.second, 1)
        XCTAssertEqual(TimeWheelMath.selecting(59, component: 2, in: selected, twelveHour: true), original)
        XCTAssertEqual(TimeWheelMath.value(forRow: -1, period: 60), 59)
    }
    func testIndependentMinuteAndHourWheelsPreserveDateAndPeriod() {
        let original = WatchTime(year: 2026, month: 12, day: 31, hour: 23, minute: 59, second: 59, utcOffset: -14400)
        var expected = original; expected.minute = 0
        XCTAssertEqual(TimeWheelMath.selecting(0, component: 1, in: original, twelveHour: true), expected)
        expected = original; expected.hour = 12
        XCTAssertEqual(TimeWheelMath.selecting(0, component: 0, in: original, twelveHour: true), expected)
        expected = original; expected.hour = 0
        XCTAssertEqual(TimeWheelMath.selecting(0, component: 0, in: original, twelveHour: false), expected)
    }
    func testPrefillStartsWithPhoneThenUsesOffsetThenDrift() {
        let first = reading(start, offset: 8)
        let second = reading(start.addingTimeInterval(86400), offset: 14)
        let target = start.addingTimeInterval(172800)
        let empty = ReadingPrefill.predict(at: target, readings: [])
        XCTAssertEqual(empty.instant, target); XCTAssertEqual(empty.source, .phoneClock)
        let one = ReadingPrefill.predict(at: target, readings: [first])
        XCTAssertEqual(one.expectedOffset, 8); XCTAssertEqual(one.source, .lastOffset)
        let two = ReadingPrefill.predict(at: target, readings: [second, first])
        XCTAssertEqual(two.expectedOffset, 20); XCTAssertEqual(two.rate, 6); XCTAssertEqual(two.source, .measuredRate)
        XCTAssertEqual(two.instant, target.addingTimeInterval(20))
        let halfDay = ReadingPrefill.predict(at: second.reference.addingTimeInterval(43200), readings: [first, second])
        XCTAssertEqual(halfDay.expectedOffset, 17)
        XCTAssertEqual(first.offset, 8); XCTAssertEqual(second.offset, 14)
    }
    func testPrefillUsesActualIntervalsAndIgnoresFutureOrInvalidMeasurements() {
        let first = reading(start, offset: 8)
        let second = reading(start.addingTimeInterval(43200), offset: 14)
        let target = second.reference.addingTimeInterval(21600)
        let predicted = ReadingPrefill.predict(at: target, readings: [first, second, reading(target.addingTimeInterval(1), offset: 500)])
        XCTAssertEqual(predicted.expectedOffset, 17); XCTAssertEqual(predicted.rate, 12)
        var invalid = second; invalid.timingValid = false
        XCTAssertEqual(ReadingPrefill.predict(at: target, readings: [first, invalid]).expectedOffset, 8)
        XCTAssertEqual(ReadingPrefill.predict(at: target, readings: [first, second], clockCompromised: true).source, .phoneClock)
        let inferred = WatchTime.at(predicted.instant, offset: -14400)
        XCTAssertEqual(inferred.instant, target.addingTimeInterval(17))
    }
    func testCloseFocusLensSelectionRequiresRealAutofocus() {
        XCTAssertTrue(CaptureLensPolicy.preferUltraWide(ultraFocusMM: 20, ultraHasAutofocus: true, wideFocusMM: 150))
        XCTAssertFalse(CaptureLensPolicy.preferUltraWide(ultraFocusMM: 20, ultraHasAutofocus: false, wideFocusMM: 150))
        XCTAssertFalse(CaptureLensPolicy.preferUltraWide(ultraFocusMM: -1, ultraHasAutofocus: true, wideFocusMM: 150))
        XCTAssertFalse(CaptureLensPolicy.preferUltraWide(ultraFocusMM: 200, ultraHasAutofocus: true, wideFocusMM: 150))
        XCTAssertTrue(CaptureLensPolicy.preferUltraWide(ultraFocusMM: 20, ultraHasAutofocus: true, wideFocusMM: -1))
    }
    func testClockMappingSubsecondsAndDiscontinuity() {
        let a = ClockAnchor(hostSeconds: 100, wall: start, bracketSeconds: 0.0001)
        XCTAssertEqual(a.wallTime(for: 100.125).timeIntervalSince(start), 0.125)
        XCTAssertEqual(a.residual(to: ClockAnchor(hostSeconds: 200, wall: start.addingTimeInterval(105), bracketSeconds: 0)), 5)
    }
    func testAutomaticCoverIdempotenceAndRelaunch() throws {
        let repo = try repository(), watch = Watch(name: "Watch")
        try repo.saveWatch(watch)
        XCTAssertTrue(repo.database.runs.isEmpty)
        let id = UUID()
        let run = try save(repo, watch: watch.id, time: start, id: id)
        let cover = repo.database.watches[0].coverID
        XCTAssertNotNil(cover); XCTAssertTrue(repo.database.watches[0].coverWasAutomatic)
        _ = try save(repo, watch: watch.id, time: start, id: id)
        XCTAssertEqual(repo.database.readings.count, 1)
        try save(repo, watch: watch.id, time: start.addingTimeInterval(86400), offset: 14)
        XCTAssertEqual(repo.database.watches[0].coverID, cover)
        let before = RunResult.calculate(repo.database.readings(in: run))
        try repo.endRun(run, reason: "Finished")
        XCTAssertEqual(RunResult.calculate(repo.database.readings(in: run)), before)
        let reloaded = try Repository(root: repo.root)
        XCTAssertEqual(reloaded.database, repo.database)
    }
    func testCoverChangesAndReadingDeletionPreserveEvidence() throws {
        let repo = try repository(), watch = Watch(name: "Same model")
        try repo.saveWatch(watch); try repo.saveWatch(Watch(name: "Same model"))
        let run = try save(repo, watch: watch.id, time: start)
        let original = repo.database.readings[0]
        let photo = PhotoAsset(id: UUID(), watchID: watch.id, source: .imported, savedAt: start.addingTimeInterval(1), width: 1, height: 1, orientation: 1)
        try repo.importCover(photo, bytes: Data([3]), thumbnail: Data([4]), crop: CoverCrop(x: 0.1, y: 0.1, side: 0.5))
        XCTAssertEqual(repo.database.readings[0], original)
        try repo.setCover(watchID: watch.id, photoID: original.photoID, crop: CoverCrop())
        try repo.deleteReading(original.id)
        XCTAssertTrue(repo.database.runs.filter { $0.id == run }.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.imageURL(original.photoID).path))
        try repo.deletePhoto(original.photoID)
        XCTAssertEqual(repo.database.watches[0].coverID, photo.id)
        XCTAssertEqual(repo.database.watches.count, 2)
    }
    func testFailedSaveRetainsCommittedStateAndRetryWorks() throws {
        let repo = try repository(), watch = Watch(name: "Test")
        try repo.saveWatch(watch)
        let before = repo.database
        repo.beforeManifestWrite = { throw StoreError.invalid("Injected disk failure") }
        XCTAssertThrowsError(try save(repo, watch: watch.id, time: start))
        XCTAssertEqual(repo.database, before)
        XCTAssertEqual(try Repository(root: repo.root).database, before)
        repo.beforeManifestWrite = nil
        try save(repo, watch: watch.id, time: start)
        XCTAssertEqual(repo.database.readings.count, 1)
    }
    func testCorrectionsAndDeletionRecalculateEndedRun() throws {
        let repo = try repository(), watch = Watch(name: "Test")
        try repo.saveWatch(watch)
        let run = try save(repo, watch: watch.id, time: start)
        try save(repo, watch: watch.id, time: start.addingTimeInterval(86400), offset: 14)
        try repo.endRun(run, reason: "Reset")
        let latest = repo.database.readings(in: run).last!
        try repo.correctReading(latest.id, entered: .at(latest.reference.addingTimeInterval(20), offset: 0))
        XCTAssertEqual(RunResult.calculate(repo.database.readings(in: run)).rate, 12)
        XCTAssertEqual(repo.database.readings(in: run).last?.capture, latest.capture)
        try repo.deleteReading(latest.id)
        XCTAssertNil(RunResult.calculate(repo.database.readings(in: run)).rate)
        XCTAssertEqual(repo.database.readings.count, 1)
    }
    func testClockCompromiseRetainsReadingAndEndsRun() throws {
        let repo = try repository(), watch = Watch(name: "Test")
        try repo.saveWatch(watch)
        let run = try save(repo, watch: watch.id, time: start)
        try save(repo, watch: watch.id, time: start.addingTimeInterval(86400), discontinuity: true)
        XCTAssertTrue(repo.database.runs[0].clockCompromised)
        XCTAssertFalse(repo.database.runs[0].isActive)
        XCTAssertEqual(repo.database.readings(in: run).count, 2)
        XCTAssertNil(RunResult.calculate(repo.database.readings(in: run), clockCompromised: true).rate)
    }
    func testChosenCreationCoverIsAtomicAndNeverReplaced() throws {
        let repo = try repository(), watch = Watch(name: "With a cover")
        let photo = PhotoAsset(id: UUID(), watchID: watch.id, source: .imported, savedAt: start, width: 1, height: 1, orientation: 1)
        repo.beforeManifestWrite = { throw StoreError.invalid("Injected write failure") }
        XCTAssertThrowsError(try repo.saveWatch(watch, cover: photo, bytes: Data([1]), thumbnail: Data([2])))
        XCTAssertTrue(repo.database.watches.isEmpty)
        repo.beforeManifestWrite = nil
        try repo.saveWatch(watch, cover: photo, bytes: Data([1]), thumbnail: Data([2]))
        try save(repo, watch: watch.id, time: start)
        XCTAssertEqual(repo.database.watches[0].coverID, photo.id)
        XCTAssertFalse(repo.database.watches[0].coverWasAutomatic)
    }
    func testActiveRunUniquenessAndStaleDraftRejected() throws {
        let repo = try repository(), watch = Watch(name: "Test")
        try repo.saveWatch(watch)
        let run = try save(repo, watch: watch.id, time: start)
        let photo = PhotoAsset(id: UUID(), watchID: watch.id, source: .timing, savedAt: start, width: 1, height: 1, orientation: 1, capture: capture(start))
        XCTAssertThrowsError(try repo.saveReading(id: UUID(), watchID: watch.id, expectedRunID: nil, photo: photo, bytes: Data([1]), thumbnail: Data([2]), entered: .at(start, offset: 0)))
        XCTAssertEqual(repo.database.runs.count, 1)
        _ = try repo.saveReading(id: UUID(), watchID: watch.id, expectedRunID: run, photo: photo, bytes: Data([1]), thumbnail: Data([2]), entered: .at(start, offset: 0), newRunReason: "Reset")
        XCTAssertEqual(repo.database.runs.count, 2)
        XCTAssertEqual(repo.database.runs.filter(\.isActive).count, 1)
        XCTAssertEqual(repo.database.readings(in: run).count, 1)
    }
    func testUnsortedSavesAndSubsecondReference() throws {
        let repo = try repository(), watch = Watch(name: "Test")
        try repo.saveWatch(watch)
        let run = try save(repo, watch: watch.id, time: start.addingTimeInterval(86400), offset: 14)
        try save(repo, watch: watch.id, time: start, offset: 8)
        XCTAssertEqual(RunResult.calculate(repo.database.readings(in: run)).rate, 6)
        let reference = start.addingTimeInterval(0.375)
        let r = reading(reference, offset: 8)
        XCTAssertEqual(r.offset, 7.625)
    }
    func testCorruptManifestIsNotReplaced() throws {
        let repo = try repository()
        let bad = Data("not json".utf8)
        try bad.write(to: repo.root.appendingPathComponent("store.json"))
        XCTAssertThrowsError(try Repository(root: repo.root))
        XCTAssertEqual(try Data(contentsOf: repo.root.appendingPathComponent("store.json")), bad)
    }
}
