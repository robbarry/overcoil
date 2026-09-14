import XCTest
@testable import OvercoilCore

extension CoreTests {
    func testDeleteCompletedRunPreservesCoverOtherRunsAndRecalculatesWatch() throws {
        let repo = try repository(), watch = Watch(name: "Test"), other = Watch(name: "Other")
        try repo.saveWatch(watch); try repo.saveWatch(other)
        let first = try save(repo, watch: watch.id, time: start)
        try save(repo, watch: watch.id, time: start.addingTimeInterval(86400), offset: 14)
        try repo.endRun(first, reason: "Finished")
        let second = try save(repo, watch: watch.id, time: start.addingTimeInterval(172800), offset: 40)
        try save(repo, watch: watch.id, time: start.addingTimeInterval(345600), offset: 64)
        try save(repo, watch: other.id, time: start)
        let cover = try XCTUnwrap(repo.database.watches[0].coverID)
        try repo.setCover(watchID: watch.id, photoID: cover, crop: CoverCrop(x: 0.4, y: 0.6, side: 0.5))
        let before = repo.database
        XCTAssertEqual(WatchStatistics.calculate(database: before, watchID: watch.id).rate, 10)
        let removed = try XCTUnwrap(before.readings(in: first).last).photoID
        try repo.deleteRun(first)
        XCTAssertEqual(repo.database.watches, before.watches)
        XCTAssertEqual(repo.database.runs, before.runs.filter { $0.id != first })
        XCTAssertEqual(repo.database.readings, before.readings.filter { $0.runID != first })
        XCTAssertEqual(repo.database.photos, before.photos.filter { $0.id != removed })
        XCTAssertEqual(repo.database.activeRun(for: watch.id)?.id, second)
        let stats = WatchStatistics.calculate(database: repo.database, watchID: watch.id)
        XCTAssertEqual(stats.rate, 12); XCTAssertEqual(stats.contributingRunCount, 1)
        XCTAssertEqual(stats.contributingReadingCount, 2); XCTAssertEqual(stats.measuredSeconds, 172800)
        XCTAssertEqual(stats.lastMeasurementDate, start.addingTimeInterval(345600))
        XCTAssertEqual(try Data(contentsOf: repo.imageURL(cover)), Data([1]))
        XCTAssertEqual(try Data(contentsOf: repo.thumbnailURL(cover)), Data([2]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.imageURL(removed).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.thumbnailURL(removed).path))
        XCTAssertEqual(try Repository(root: repo.root).database, repo.database)
        let manifest = try Data(contentsOf: repo.root.appendingPathComponent("store.json"))
        try repo.deleteRun(first) // Retrying an already-deleted run is a no-op.
        XCTAssertEqual(try Data(contentsOf: repo.root.appendingPathComponent("store.json")), manifest)
    }

    func testDeleteActiveRunDoesNotReopenHistoryAndStaleCaptureCannotSave() throws {
        let repo = try repository(), watch = Watch(name: "Test")
        try repo.saveWatch(watch)
        let completed = try save(repo, watch: watch.id, time: start)
        try repo.endRun(completed, reason: "Hands reset")
        let active = try save(repo, watch: watch.id, time: start.addingTimeInterval(86400))
        let history = repo.database.runs[0]
        try repo.deleteRun(active)
        XCTAssertNil(repo.database.activeRun(for: watch.id))
        XCTAssertEqual(repo.database.runs, [history])
        let c = capture(start.addingTimeInterval(172800))
        let photo = PhotoAsset(id: UUID(), watchID: watch.id, source: .timing, savedAt: start, width: 1, height: 1, orientation: 1, capture: c)
        XCTAssertThrowsError(try repo.saveReading(id: UUID(), watchID: watch.id, expectedRunID: active, photo: photo,
                                                bytes: Data([1]), thumbnail: Data([2]), entered: .at(c.reference, offset: 0)))
        let new = try save(repo, watch: watch.id, time: c.reference)
        XCTAssertNotEqual(new, completed); XCTAssertNotEqual(new, active)
        XCTAssertEqual(repo.database.runs[0], history)
    }

    func testFailedRunAndReadingDeletionPreserveManifestAndEveryPhoto() throws {
        let repo = try repository(), watch = Watch(name: "Test")
        try repo.saveWatch(watch)
        let run = try save(repo, watch: watch.id, time: start)
        try save(repo, watch: watch.id, time: start.addingTimeInterval(86400))
        let before = repo.database, manifestURL = repo.root.appendingPathComponent("store.json")
        let manifest = try Data(contentsOf: manifestURL)
        repo.beforeManifestWrite = { throw StoreError.invalid("Injected deletion failure") }
        XCTAssertThrowsError(try repo.deleteRun(run))
        XCTAssertThrowsError(try repo.deleteReading(before.readings[1].id))
        XCTAssertEqual(repo.database, before)
        XCTAssertEqual(try Data(contentsOf: manifestURL), manifest)
        XCTAssertEqual(try Repository(root: repo.root).database, before)
        for photo in before.photos {
            XCTAssertEqual(try Data(contentsOf: repo.imageURL(photo.id)), Data([1]))
            XCTAssertEqual(try Data(contentsOf: repo.thumbnailURL(photo.id)), Data([2]))
        }
        repo.beforeManifestWrite = nil
        try repo.deleteRun(run)
        XCTAssertTrue(repo.database.runs.isEmpty); XCTAssertTrue(repo.database.readings.isEmpty)
        XCTAssertEqual(repo.database.watches, before.watches)
        XCTAssertEqual(repo.database.photos.map(\.id), [before.watches[0].coverID!])
        XCTAssertNil(WatchStatistics.calculate(database: repo.database, watchID: watch.id).rate)
        XCTAssertEqual(try Repository(root: repo.root).database, repo.database)
    }

    func testDeleteReadingEndpointsRecalculatesWithoutChangingSurvivingEvidence() throws {
        let repo = try repository(), watch = Watch(name: "Test")
        try repo.saveWatch(watch)
        let run = try save(repo, watch: watch.id, time: start, offset: 8)
        try save(repo, watch: watch.id, time: start.addingTimeInterval(86400), offset: 14)
        try save(repo, watch: watch.id, time: start.addingTimeInterval(172800), offset: 32)
        let before = repo.database
        try repo.deleteReading(before.readings[0].id)
        XCTAssertEqual(repo.database.readings, Array(before.readings.dropFirst()))
        XCTAssertEqual(repo.database.runs, before.runs)
        XCTAssertEqual(RunResult.calculate(repo.database.readings(in: run)).rate, 18)
        XCTAssertEqual(WatchStatistics.calculate(database: repo.database, watchID: watch.id).rate, 18)
        try repo.deleteReading(before.readings[2].id)
        XCTAssertNil(WatchStatistics.calculate(database: repo.database, watchID: watch.id).rate)
        XCTAssertEqual(repo.database.readings, [before.readings[1]])
        try repo.deleteReading(before.readings[1].id)
        XCTAssertTrue(repo.database.runs.isEmpty)
        XCTAssertEqual(repo.database.watches, before.watches)
        XCTAssertEqual(repo.database.photos, [before.photos[0]])
        XCTAssertEqual(try Repository(root: repo.root).database, repo.database)
    }

    func testDeletingInvalidReadingDoesNotClearClockCompromise() throws {
        let repo = try repository(), watch = Watch(name: "Test")
        try repo.saveWatch(watch)
        let run = try save(repo, watch: watch.id, time: start)
        try save(repo, watch: watch.id, time: start.addingTimeInterval(86400), offset: 14)
        try save(repo, watch: watch.id, time: start.addingTimeInterval(172800), discontinuity: true)
        try repo.deleteReading(repo.database.readings[2].id)
        XCTAssertTrue(repo.database.runs[0].clockCompromised)
        XCTAssertFalse(repo.database.runs[0].isActive)
        XCTAssertEqual(repo.database.readings(in: run).count, 2)
        XCTAssertNil(WatchStatistics.calculate(database: repo.database, watchID: watch.id).rate)
    }
}
