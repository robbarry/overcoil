import XCTest
@testable import OvercoilCore

final class CloudCoreTests: XCTestCase {
    func testSyncDecisionProtectsDivergentAndMissingLibraries() {
        XCTAssertEqual(CloudSyncDecision.choose(localRevision: "a", remoteRevision: nil, baseline: nil, localIsEmpty: false), .upload)
        XCTAssertEqual(CloudSyncDecision.choose(localRevision: "empty", remoteRevision: "a", baseline: nil, localIsEmpty: true), .download)
        XCTAssertEqual(CloudSyncDecision.choose(localRevision: "a", remoteRevision: "a", baseline: nil, localIsEmpty: false), .inSync)
        XCTAssertEqual(CloudSyncDecision.choose(localRevision: "a", remoteRevision: "b", baseline: "a", localIsEmpty: false), .download)
        XCTAssertEqual(CloudSyncDecision.choose(localRevision: "b", remoteRevision: "a", baseline: "a", localIsEmpty: false), .upload)
        XCTAssertEqual(CloudSyncDecision.choose(localRevision: "b", remoteRevision: "c", baseline: "a", localIsEmpty: false), .conflict)
        XCTAssertEqual(CloudSyncDecision.choose(localRevision: "a", remoteRevision: nil, baseline: "a", localIsEmpty: false), .remoteMissing)
    }
    func testCloudDocumentRejectsTamperingAndImportProtectsLocalEdits() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("overcoil-cloud-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: base) }
        let source = try Repository(root: base.appendingPathComponent("source"))
        try source.saveWatch(Watch(name: "Original"))
        let snapshot = try CloudLibrary.build(database: source.database, localRoot: source.root, parentRevision: nil)
        XCTAssertEqual(try CloudLibrary.decode(snapshot.encoded()).database, source.database)
        var changed = snapshot; changed.database.watches[0].name = "Tampered"
        XCTAssertThrowsError(try changed.validate())
        let target = try Repository(root: base.appendingPathComponent("target"))
        let emptyRevision = try CloudLibrary.revision(of: target.database)
        try target.replaceFromCloud(snapshot, downloadedRoot: base, expectedLocalRevision: emptyRevision)
        XCTAssertEqual(target.database, source.database)
        try target.saveWatch(Watch(name: "New local edit"))
        XCTAssertThrowsError(try target.replaceFromCloud(snapshot, downloadedRoot: base, expectedLocalRevision: snapshot.revision))
        XCTAssertEqual(target.database.watches.count, 2)
    }
}

extension CloudCoreTests {
    private func addReading(_ repo: Repository, watchID: UUID, reference: Date, offset: Int) throws {
        let capture = CaptureMetadata(reference: reference, localUTCOffset: 0, rawValue: 123, rawTimescale: 1000, rawEpoch: 0,
                                      hostSeconds: 100, anchorHostSeconds: 100, anchorWall: reference, anchorBracketSeconds: 0,
                                      mappingResidualSeconds: 0, continuityID: UUID(), clockDiscontinuity: false)
        let photo = PhotoAsset(id: UUID(), watchID: watchID, source: .timing, savedAt: reference, width: 1, height: 1, orientation: 1, capture: capture)
        try repo.saveReading(id: UUID(), watchID: watchID, expectedRunID: repo.database.activeRun(for: watchID)?.id, photo: photo,
                             bytes: Data([0xff,0xd8,0xff,0xd9]), thumbnail: Data([1,2,3]), entered: .at(reference.addingTimeInterval(Double(offset)), offset: 0))
    }
    private func stage(_ doc: CloudLibrary, from repo: Repository, into folder: URL) throws {
        for photo in doc.photoFiles {
            for (source, path) in [(repo.imageURL(photo.id),photo.originalPath),(repo.thumbnailURL(photo.id),photo.thumbnailPath)] {
                let target = folder.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contentsOf: source).write(to: target)
            }
        }
    }
    func testTwoReplicasRestoreAndSyncWithoutChangingEvidence() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("overcoil-replicas-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = try Repository(root: folder.appendingPathComponent("a")), b = try Repository(root: folder.appendingPathComponent("b"))
        let watch = Watch(name: "Two-way test"); try a.saveWatch(watch)
        let date = Date(timeIntervalSince1970: 1800000000.125)
        try addReading(a, watchID: watch.id, reference: date, offset: 8)
        let original = a.database.readings[0]
        let first = try CloudLibrary.build(database: a.database, localRoot: a.root, parentRevision: nil)
        let shared = folder.appendingPathComponent("cloud")
        try stage(first, from: a, into: shared)
        let decoded = try CloudLibrary.decode(first.encoded())
        XCTAssertEqual(decoded.database.readings[0].capture, original.capture)
        try b.replaceFromCloud(decoded, downloadedRoot: shared, expectedLocalRevision: CloudLibrary.revision(of: b.database))
        XCTAssertEqual(b.database, a.database)
        try addReading(b, watchID: watch.id, reference: date.addingTimeInterval(86400), offset: 14)
        let second = try CloudLibrary.build(database: b.database, localRoot: b.root, parentRevision: first.revision)
        try stage(second, from: b, into: shared)
        XCTAssertEqual(CloudSyncDecision.choose(localRevision: first.revision, remoteRevision: second.revision, baseline: first.revision, localIsEmpty: false), .download)
        try a.replaceFromCloud(second, downloadedRoot: shared, expectedLocalRevision: first.revision)
        XCTAssertEqual(a.database, b.database)
        XCTAssertEqual(a.database.readings.first?.capture, original.capture)
        XCTAssertEqual(WatchStatistics.calculate(database: a.database, watchID: watch.id).rate, 6)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.root.appendingPathComponent("SyncRecovery/\(first.revision)/store.json").path))
    }
    func testMissingOrCorruptCloudPhotoCannotReplaceLocalTimings() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("overcoil-corrupt-cloud-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try Repository(root: folder.appendingPathComponent("source")), target = try Repository(root: folder.appendingPathComponent("target"))
        let watch = Watch(name: "Keep evidence"); try source.saveWatch(watch)
        try addReading(source, watchID: watch.id, reference: Date(timeIntervalSince1970: 1800000000), offset: 8)
        let document = try CloudLibrary.build(database: source.database, localRoot: source.root, parentRevision: nil)
        let before = target.database
        let staging = folder.appendingPathComponent("staging")
        XCTAssertThrowsError(try target.replaceFromCloud(document, downloadedRoot: staging, expectedLocalRevision: CloudLibrary.revision(of: before)))
        try stage(document, from: source, into: staging)
        try Data([9,9,9]).write(to: staging.appendingPathComponent(document.photoFiles[0].originalPath))
        XCTAssertThrowsError(try target.replaceFromCloud(document, downloadedRoot: staging, expectedLocalRevision: CloudLibrary.revision(of: before)))
        XCTAssertEqual(target.database, before)
    }
}
