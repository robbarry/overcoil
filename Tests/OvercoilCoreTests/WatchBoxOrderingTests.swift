import XCTest
@testable import OvercoilCore

extension CoreTests {
    func testWatchBoxOrdersByLatestSavedOrCorrectedEntryAcrossAllRuns() throws {
        let repo = try repository(), first = Watch(name: "First"), second = Watch(name: "Second"), empty = Watch(name: "Empty")
        for watch in [first, second, empty] { try repo.saveWatch(watch) }
        let a = try save(repo, watch: first.id, time: start.addingTimeInterval(86400))
        try repo.endRun(a, reason: "Finished")
        // A later save with an earlier capture still represents newer entry activity.
        try save(repo, watch: second.id, time: start)
        var db = repo.database
        db.readings[0].createdAt = start; db.readings[0].updatedAt = start
        db.readings[1].createdAt = start.addingTimeInterval(10); db.readings[1].updatedAt = start.addingTimeInterval(10)
        XCTAssertEqual(db.watchesByLatestEntry.map(\.id), [second.id, first.id, empty.id])
        // Corrections in completed runs also count; invalid timing is still an entry.
        db.readings[0].updatedAt = start.addingTimeInterval(20)
        db.readings[0].timingValid = false
        XCTAssertEqual(db.watchesByLatestEntry.map(\.id), [first.id, second.id, empty.id])
        let before = try CloudLibrary.databaseData(db)
        _ = db.watchesByLatestEntry
        XCTAssertEqual(try CloudLibrary.databaseData(db), before)
        XCTAssertEqual(db.watches.map(\.id), [first.id, second.id, empty.id])
    }

    func testWatchBoxTiesAndWatchesWithoutEntriesKeepStoredOrder() {
        let a = Watch(name: "Z"), b = Watch(name: "A"), c = Watch(name: "New")
        let ra = TimingRun(watchID: a.id, basisUTCOffset: 0, createdAt: start)
        let rb = TimingRun(watchID: b.id, basisUTCOffset: 0, createdAt: start)
        var db = Database(); db.watches = [c, a, b]; db.runs = [ra, rb]
        XCTAssertEqual(db.watchesByLatestEntry, db.watches)
        var first = reading(start, offset: 8), second = reading(start, offset: 14)
        first.runID = ra.id; second.runID = rb.id
        db.readings = [second, first]
        XCTAssertEqual(db.watchesByLatestEntry.map(\.id), [a.id, b.id, c.id])
    }

    func testWatchBoxDeletionFallsBackToRemainingEntriesAndSurvivesReload() throws {
        let repo = try repository(), a = Watch(name: "A"), b = Watch(name: "B")
        try repo.saveWatch(a); try repo.saveWatch(b)
        try save(repo, watch: a.id, time: start)
        let aReading = repo.database.readings[0]
        let bRun = try save(repo, watch: b.id, time: start)
        try repo.correctReading(aReading.id, entered: aReading.entered)
        XCTAssertEqual(repo.database.watchesByLatestEntry.map(\.id), [a.id, b.id])
        try repo.deleteReading(aReading.id)
        XCTAssertEqual(repo.database.watchesByLatestEntry.map(\.id), [b.id, a.id])
        XCTAssertEqual(try Repository(root: repo.root).database.watchesByLatestEntry, repo.database.watchesByLatestEntry)
        try repo.deleteRun(bRun)
        XCTAssertEqual(repo.database.watchesByLatestEntry.map(\.id), [a.id, b.id])
    }
}
