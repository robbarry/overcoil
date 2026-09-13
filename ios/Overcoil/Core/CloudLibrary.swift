import Foundation
import CryptoKit

struct CloudPhotoFile: Codable, Equatable, Sendable {
    var id: UUID
    var fileExtension: String
    var originalSHA256: String
    var thumbnailSHA256: String
    var originalPath: String { "Photos/\(id.uuidString).\(fileExtension)" }
    var thumbnailPath: String { "Thumbnails/\(id.uuidString).jpg" }
}

struct CloudReadingSummary: Codable, Equatable, Sendable {
    var id: UUID
    var watch: String
    var referenceUTC: String
    var watchUTC: String
    var offsetSeconds: Double
    var photo: String
}

struct CloudWatchSummary: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var rateSecondsPerDay: Double?
    var measuredSeconds: Double
    var contributingReadings: Int
    var contributingRuns: Int
}

struct CloudLibrary: Codable, Sendable {
    var formatVersion = 1
    var revision: String
    var parentRevision: String?
    var publishedAt: Date
    var database: Database
    var photoFiles: [CloudPhotoFile]
    var readingsForInspection: [CloudReadingSummary]
    var watchesForInspection: [CloudWatchSummary]? = nil
    var dateEncodingNote = "The database preserves dates as exact seconds since 2001-01-01 UTC. readingsForInspection provides readable UTC timestamps; its values are derived, not editable inputs."

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func databaseData(_ db: Database) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(db)
    }
    static func revision(of db: Database) throws -> String { hash(try databaseData(db)) }
    static func fileExtension(for data: Data) -> String {
        if data.starts(with: [0xff, 0xd8, 0xff]) { return "jpg" }
        if data.starts(with: [0x89, 0x50, 0x4e, 0x47]) { return "png" }
        if data.starts(with: Array("GIF8".utf8)) { return "gif" }
        if data.count > 12, String(data: data[4..<8], encoding: .ascii) == "ftyp" {
            return String(data: data[8..<12], encoding: .ascii) == "avif" ? "avif" : "heic"
        }
        if data.starts(with: [0x49, 0x49, 0x2a, 0]) || data.starts(with: [0x4d, 0x4d, 0, 0x2a]) { return "tiff" }
        return "image"
    }
    static func build(database: Database, localRoot: URL, parentRevision: String?) throws -> Self {
        try Repository.validate(database)
        let photos = try database.photos.map { photo in
            let original = try Data(contentsOf: localRoot.appendingPathComponent("images/\(photo.fileName)"))
            let thumb = try Data(contentsOf: localRoot.appendingPathComponent("images/\(photo.thumbnailName)"))
            return CloudPhotoFile(id: photo.id, fileExtension: fileExtension(for: original), originalSHA256: hash(original), thumbnailSHA256: hash(thumb))
        }
        let summaries = database.readings.sorted { $0.reference < $1.reference }.map { reading in
            let run = database.runs.first { $0.id == reading.runID }
            let watch = database.watches.first { $0.id == run?.watchID }
            return CloudReadingSummary(id: reading.id, watch: watch?.name ?? "Watch", referenceUTC: reading.reference.ISO8601Format(.init(includingFractionalSeconds: true)), watchUTC: reading.entered.instant!.ISO8601Format(.init(includingFractionalSeconds: true)), offsetSeconds: reading.offset, photo: photos.first { $0.id == reading.photoID }!.originalPath)
        }
        let watches = database.watches.map { watch in
            let stats = WatchStatistics.calculate(database: database, watchID: watch.id)
            return CloudWatchSummary(id: watch.id, name: watch.name, rateSecondsPerDay: stats.rate,
                                     measuredSeconds: stats.measuredSeconds, contributingReadings: stats.contributingReadingCount, contributingRuns: stats.contributingRunCount)
        }
        return Self(revision: try revision(of: database), parentRevision: parentRevision, publishedAt: Date(), database: database, photoFiles: photos, readingsForInspection: summaries, watchesForInspection: watches)
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    static func decode(_ data: Data) throws -> Self {
        let document = try JSONDecoder().decode(Self.self, from: data)
        try document.validate()
        return document
    }
    func validate() throws {
        try Repository.validate(database)
        guard formatVersion == 1, revision == (try Self.revision(of: database)),
              Set(photoFiles.map(\.id)) == Set(database.photos.map(\.id)), Set(photoFiles.map(\.id)).count == photoFiles.count else {
            throw StoreError.invalid("The iCloud library is incomplete or was changed outside Overcoil. Local data has not been replaced.")
        }
        for photo in photoFiles {
            guard ["jpg", "png", "gif", "heic", "avif", "tiff", "image"].contains(photo.fileExtension),
                  photo.originalSHA256.count == 64, photo.thumbnailSHA256.count == 64,
                  photo.originalSHA256.allSatisfy(\.isHexDigit), photo.thumbnailSHA256.allSatisfy(\.isHexDigit) else {
                throw StoreError.invalid("The iCloud photo manifest is invalid.")
            }
        }
    }
    func verifyPhotos(in root: URL) throws {
        for photo in photoFiles {
            let original = try Data(contentsOf: root.appendingPathComponent(photo.originalPath))
            let thumb = try Data(contentsOf: root.appendingPathComponent(photo.thumbnailPath))
            guard Self.hash(original) == photo.originalSHA256, Self.hash(thumb) == photo.thumbnailSHA256 else {
                throw StoreError.invalid("An iCloud photo has not arrived intact yet. Your local library is unchanged.")
            }
        }
    }
}

enum CloudSyncDecision: Equatable {
    case upload, download, inSync, empty, conflict, remoteMissing
    static func choose(localRevision: String, remoteRevision: String?, baseline: String?, localIsEmpty: Bool) -> Self {
        guard let remoteRevision else {
            if baseline != nil { return .remoteMissing }
            return localIsEmpty ? .empty : .upload
        }
        if localRevision == remoteRevision { return .inSync }
        guard let baseline else { return localIsEmpty ? .download : .conflict }
        let localChanged = localRevision != baseline
        let remoteChanged = remoteRevision != baseline
        if localChanged && remoteChanged { return .conflict }
        return localChanged ? .upload : .download
    }
}
