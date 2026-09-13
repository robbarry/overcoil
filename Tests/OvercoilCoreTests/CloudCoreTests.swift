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
