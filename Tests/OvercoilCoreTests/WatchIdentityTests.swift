import XCTest
@testable import OvercoilCore

extension CoreTests {
    func testLegacyIdentityDecodesWithoutRewritingCloudRevision() throws {
        let legacy = Watch(name: "My daily watch", brand: "Maker", model: "Series 1")
        let bytes = try CloudLibrary.databaseData(Database(watches: [legacy]))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("nickname"))
        let decoded = try JSONDecoder().decode(Database.self, from: bytes)
        XCTAssertNil(decoded.watches[0].nickname)
        XCTAssertEqual(decoded.watches[0].displayName, "My daily watch")
        XCTAssertEqual(try CloudLibrary.databaseData(decoded), bytes)
    }
    func testIdentityTitlesAndNameOnlyCreation() throws {
        let repo = try repository()
        var watch = Watch(name: "", brand: " Maker ", model: " Series 1 ", nickname: "")
        try repo.saveWatch(watch)
        let saved = repo.database.watches[0]
        XCTAssertEqual(saved.name, "Maker"); XCTAssertEqual(saved.displaySubtitle, "Series 1")
        XCTAssertEqual(saved.nickname, "")
        watch = saved; watch.editableNickname = " Daily "; try repo.saveWatch(watch)
        XCTAssertEqual(repo.database.watches[0].displayName, "Daily")
        watch = repo.database.watches[0]; watch.editableNickname = ""; watch.brand = ""
        try repo.saveWatch(watch)
        XCTAssertEqual(repo.database.watches[0].displayName, "Series 1")
        XCTAssertEqual(repo.database.watches[0].displaySubtitle, "")
        watch.model = "  "; XCTAssertThrowsError(try repo.saveWatch(watch))
        let nicknameOnly = Watch(name: "", nickname: "Grandfather’s watch")
        try repo.saveWatch(nicknameOnly)
        XCTAssertEqual(repo.database.watches.last?.displayName, "Grandfather’s watch")
        XCTAssertEqual(try Repository(root: repo.root).database, repo.database)
    }
    func testIdentityCorrectionsPreserveEvidenceAndRoundTripCloud() throws {
        let repo = try repository(); let watch = Watch(name: "Old label", brand: "Series", notes: "Keep this note")
        try repo.saveWatch(watch)
        try save(repo, watch: watch.id, time: start)
        try save(repo, watch: watch.id, time: start.addingTimeInterval(86400), offset: 14)
        let before = repo.database
        let files = try Dictionary(uniqueKeysWithValues: before.photos.flatMap { p in
            try [repo.imageURL(p.id), repo.thumbnailURL(p.id)].map { ($0, try Data(contentsOf: $0)) }
        })
        let correction = WatchIdentityCorrection(watchID: watch.id, expected: WatchIdentityFields(watch), brand: "Maker", model: "Series", nickname: "")
        let request = WatchIdentityCorrections(corrections: [correction])
        try repo.correctWatchIdentities(request)
        XCTAssertEqual(repo.database.readings, before.readings); XCTAssertEqual(repo.database.runs, before.runs)
        XCTAssertEqual(repo.database.photos, before.photos)
        var expected = before.watches[0]; expected.brand = "Maker"; expected.model = "Series"; expected.nickname = ""; expected.normalizeIdentity()
        XCTAssertEqual(repo.database.watches, [expected])
        for (url, data) in files { XCTAssertEqual(try Data(contentsOf: url), data) }
        let after = repo.database; try repo.correctWatchIdentities(request); XCTAssertEqual(repo.database, after)
        XCTAssertEqual(try Repository(root: repo.root).database, after)
        let doc = try CloudLibrary.build(database: after, localRoot: repo.root, parentRevision: nil)
        let decoded = try JSONDecoder().decode(CloudLibrary.self, from: JSONEncoder().encode(doc))
        XCTAssertEqual(decoded.database, after)
        XCTAssertEqual(decoded.revision, try CloudLibrary.revision(of: decoded.database))
        let recovery = try FileManager.default.contentsOfDirectory(at: repo.root.appendingPathComponent("IdentityRecovery"), includingPropertiesForKeys: nil)
        XCTAssertEqual(recovery.count, 1)
        XCTAssertEqual(try JSONDecoder().decode(Database.self, from: Data(contentsOf: recovery[0])), before)
    }
    func testIdentityCorrectionsRejectStaleBatchAndFailedWrites() throws {
        let repo = try repository(); let a = Watch(name: "First"), b = Watch(name: "Second")
        try repo.saveWatch(a); try repo.saveWatch(b)
        let before = repo.database
        let ca = WatchIdentityCorrection(watchID: a.id, expected: WatchIdentityFields(a), brand: "Maker", model: "One", nickname: "")
        var cb = WatchIdentityCorrection(watchID: b.id, expected: WatchIdentityFields(b), brand: "Maker", model: "Two", nickname: "")
        cb.expected.name = "Stale"
        XCTAssertThrowsError(try repo.correctWatchIdentities(.init(corrections: [ca, cb])))
        XCTAssertEqual(repo.database, before)
        XCTAssertThrowsError(try repo.correctWatchIdentities(.init(corrections: [ca, ca])))
        repo.beforeManifestWrite = { throw StoreError.invalid("Disk full") }
        XCTAssertThrowsError(try repo.correctWatchIdentities(.init(corrections: [ca])))
        XCTAssertEqual(repo.database, before)
        XCTAssertEqual(try Repository(root: repo.root).database, before)
    }
}
