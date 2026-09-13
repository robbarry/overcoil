import Foundation
import Darwin

enum StoreError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

// Single-owner repository. A mutation commits files first, then one atomic manifest;
// the visible in-memory state changes only after the manifest commit succeeds.
final class Repository {
    private(set) var database: Database
    let root: URL
    private let fm = FileManager.default
    var beforeManifestWrite: (() throws -> Void)? // Fault-injection seam for tests.

    init(root: URL) throws {
        self.root = root
        try fm.createDirectory(at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
        let manifest = root.appendingPathComponent("store.json")
        if fm.fileExists(atPath: manifest.path) {
            database = try JSONDecoder().decode(Database.self, from: Data(contentsOf: manifest))
            try Self.validate(database)
            for photo in database.photos {
                guard fm.fileExists(atPath: imageURL(photo.id).path), fm.fileExists(atPath: thumbnailURL(photo.id).path) else {
                    throw StoreError.invalid("A saved photo is missing. Existing data has been preserved; do not reset storage.")
                }
            }
        } else { database = Database() }
        // Cleanup only our UUID-named assets, and only after a valid manifest load.
        cleanupOrphans()
    }

    func imageURL(_ id: UUID) -> URL { root.appendingPathComponent("images/\(id.uuidString).image") }
    func thumbnailURL(_ id: UUID) -> URL { root.appendingPathComponent("images/\(id.uuidString).thumb") }

    private func writeDurably(_ data: Data, to destination: URL) throws {
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).pending")
        defer { try? fm.removeItem(at: temp) }
        guard fm.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw StoreError.invalid("Could not create a storage file. Your draft has not been saved.")
        }
        let handle = try FileHandle(forWritingTo: temp)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        guard rename(temp.path, destination.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private func commit(_ next: Database) throws {
        try Self.validate(next)
        try beforeManifestWrite?()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try writeDurably(encoder.encode(next), to: root.appendingPathComponent("store.json"))
        database = next
        cleanupOrphans()
    }

    static func validate(_ db: Database) throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw StoreError.invalid(message) }
        }
        try require(db.schemaVersion == 1, "Unsupported data version. Storage has not been changed.")
        try require(Set(db.watches.map(\.id)).count == db.watches.count && Set(db.photos.map(\.id)).count == db.photos.count && Set(db.runs.map(\.id)).count == db.runs.count && Set(db.readings.map(\.id)).count == db.readings.count, "Duplicate record identifiers.")
        for watch in db.watches {
            try require(!watch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "A watch needs a name.")
            try require(db.runs.filter { $0.watchID == watch.id && $0.isActive }.count <= 1, "Only one active run is allowed per watch.")
            if let id = watch.coverID { try require(db.photos.contains { $0.id == id && $0.watchID == watch.id }, "The reference photo is missing.") }
            try require(watch.crop.x.isFinite && watch.crop.y.isFinite && watch.crop.side.isFinite && watch.crop.x >= 0 && watch.crop.y >= 0 && watch.crop.side > 0 && watch.crop.side <= 1 && watch.crop.x <= 1 && watch.crop.y <= 1, "Invalid cover crop.")
        }
        for photo in db.photos { try require(db.watches.contains { $0.id == photo.watchID }, "Photo has no watch.") }
        for run in db.runs {
            try require(db.watches.contains { $0.id == run.watchID }, "Run has no watch.")
            try require(db.readings.contains { $0.runID == run.id }, "Empty runs are not saved.")
        }
        for reading in db.readings {
            guard let run = db.runs.first(where: { $0.id == reading.runID }) else { throw StoreError.invalid("Reading has no run.") }
            try require(db.photos.contains { $0.id == reading.photoID && $0.watchID == run.watchID && $0.source == .timing && $0.capture == reading.capture }, "Reading evidence is missing or mismatched.")
            try require(reading.entered.instant != nil && reading.reference.timeIntervalSince1970.isFinite, "Invalid reading time.")
        }
    }

    private func cleanupOrphans() {
        let keep = Set(database.photos.flatMap { [$0.fileName, $0.thumbnailName] })
        guard let files = try? fm.contentsOfDirectory(at: root.appendingPathComponent("images"), includingPropertiesForKeys: nil) else { return }
        for file in files where !keep.contains(file.lastPathComponent) {
            let ownAsset = ["image", "thumb"].contains(file.pathExtension) && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil
            let ownDraft = file.pathExtension == "pending" && UUID(uuidString: String(file.deletingPathExtension().lastPathComponent.dropFirst())) != nil
            if ownAsset || ownDraft { try? fm.removeItem(at: file) }
        }
    }

    @discardableResult func saveWatch(_ watch: Watch, cover: PhotoAsset? = nil, bytes: Data? = nil, thumbnail: Data? = nil) throws -> UUID {
        var next = database
        if let i = next.watches.firstIndex(where: { $0.id == watch.id }) { next.watches[i] = watch }
        else { next.watches.append(watch) }
        if let cover {
            guard cover.watchID == watch.id, cover.source != .timing, !next.photos.contains(where: { $0.id == cover.id }),
                  let bytes, let thumbnail, let index = next.watches.firstIndex(where: { $0.id == watch.id }) else { throw StoreError.invalid("Invalid reference photo.") }
            next.photos.append(cover)
            next.watches[index].coverID = cover.id; next.watches[index].crop = CoverCrop(); next.watches[index].coverWasAutomatic = false
            try Self.validate(next)
            try writePhoto(cover, bytes: bytes, thumbnail: thumbnail)
        }
        try commit(next)
        return watch.id
    }

    private func writePhoto(_ photo: PhotoAsset, bytes: Data, thumbnail: Data) throws {
        guard !bytes.isEmpty, !thumbnail.isEmpty else { throw StoreError.invalid("The photo could not be read.") }
        try writeDurably(bytes, to: imageURL(photo.id))
        try writeDurably(thumbnail, to: thumbnailURL(photo.id))
    }

    @discardableResult
    func saveReading(id: UUID, watchID: UUID, expectedRunID: UUID?, photo: PhotoAsset,
                     bytes: Data, thumbnail: Data, entered: WatchTime, newRunReason: String? = nil) throws -> UUID {
        if let saved = database.readings.first(where: { $0.id == id }) { return saved.runID }
        guard photo.watchID == watchID, photo.source == .timing, let capture = photo.capture, entered.instant != nil,
              let wi = database.watches.firstIndex(where: { $0.id == watchID }) else { throw StoreError.invalid("The reading is incomplete.") }
        let active = database.activeRun(for: watchID)
        guard active?.id == expectedRunID else { throw StoreError.invalid("The run changed while this photo was open. Close and capture again.") }
        if active?.clockCompromised == true && newRunReason == nil { throw StoreError.invalid("The phone clock changed. Start a new run.") }
        var next = database
        let now = Date()
        var run = active
        if let reason = newRunReason, let oldID = run?.id, let index = next.runs.firstIndex(where: { $0.id == oldID }) {
            next.runs[index].endedAt = now; next.runs[index].endReason = reason; run = nil
        }
        if run == nil {
            let new = TimingRun(watchID: watchID, basisUTCOffset: entered.utcOffset, createdAt: now)
            next.runs.append(new); run = new
        }
        let runID = run!.id
        var valid = !capture.clockDiscontinuity
        if let previous = next.readings(in: runID).last, previous.capture.continuityID == capture.continuityID {
            let wallDelta = capture.reference.timeIntervalSince(previous.reference)
            let hostDelta = capture.hostSeconds - previous.capture.hostSeconds
            if abs(wallDelta - hostDelta) > 0.5 { valid = false }
        }
        if !valid, let index = next.runs.firstIndex(where: { $0.id == runID }) {
            next.runs[index].clockCompromised = true
            next.runs[index].endedAt = now
            next.runs[index].endReason = "Phone clock discontinuity detected"
        }
        guard !next.photos.contains(where: { $0.id == photo.id }) else { throw StoreError.invalid("This image is already saved.") }
        next.photos.append(photo)
        next.readings.append(Reading(id: id, runID: runID, photoID: photo.id, capture: capture, entered: entered, createdAt: now, updatedAt: now, timingValid: valid))
        if next.watches[wi].coverID == nil {
            next.watches[wi].coverID = photo.id
            next.watches[wi].coverWasAutomatic = true
            next.watches[wi].crop = CoverCrop()
        }
        try writePhoto(photo, bytes: bytes, thumbnail: thumbnail)
        try commit(next)
        return runID
    }

    func setCover(watchID: UUID, photoID: UUID, crop: CoverCrop) throws {
        var next = database
        guard let i = next.watches.firstIndex(where: { $0.id == watchID }), next.photos.contains(where: { $0.id == photoID && $0.watchID == watchID }) else { throw StoreError.invalid("Reference photo not found.") }
        next.watches[i].coverID = photoID; next.watches[i].crop = crop; next.watches[i].coverWasAutomatic = false
        try commit(next)
    }

    func importCover(_ photo: PhotoAsset, bytes: Data, thumbnail: Data, crop: CoverCrop) throws {
        var next = database
        guard let i = next.watches.firstIndex(where: { $0.id == photo.watchID }), photo.source != .timing else { throw StoreError.invalid("Invalid cover import.") }
        guard !next.photos.contains(where: { $0.id == photo.id }) else { throw StoreError.invalid("Photo is already saved.") }
        next.photos.append(photo)
        next.watches[i].coverID = photo.id; next.watches[i].crop = crop; next.watches[i].coverWasAutomatic = false
        try writePhoto(photo, bytes: bytes, thumbnail: thumbnail)
        try commit(next)
    }

    func endRun(_ id: UUID, reason: String) throws {
        var next = database
        guard let i = next.runs.firstIndex(where: { $0.id == id && $0.isActive }) else { return }
        next.runs[i].endedAt = Date(); next.runs[i].endReason = reason
        try commit(next)
    }

    func correctReading(_ id: UUID, entered: WatchTime) throws {
        var next = database
        guard let i = next.readings.firstIndex(where: { $0.id == id }) else { throw StoreError.invalid("Reading not found.") }
        next.readings[i].entered = entered; next.readings[i].updatedAt = Date()
        try commit(next)
    }

    func deleteReading(_ id: UUID) throws {
        var next = database
        guard let reading = next.readings.first(where: { $0.id == id }) else { return }
        next.readings.removeAll { $0.id == id }
        if !next.readings.contains(where: { $0.runID == reading.runID }) { next.runs.removeAll { $0.id == reading.runID } }
        if !next.watches.contains(where: { $0.coverID == reading.photoID }) && !next.readings.contains(where: { $0.photoID == reading.photoID }) {
            next.photos.removeAll { $0.id == reading.photoID }
        }
        try commit(next)
    }

    func deletePhoto(_ id: UUID) throws {
        guard !database.readings.contains(where: { $0.photoID == id }) else { throw StoreError.invalid("This photo is evidence for a reading. Delete the reading first.") }
        var next = database
        next.photos.removeAll { $0.id == id }
        for i in next.watches.indices where next.watches[i].coverID == id {
            next.watches[i].coverID = next.photos(for: next.watches[i].id).first?.id
            next.watches[i].crop = CoverCrop(); next.watches[i].coverWasAutomatic = true
        }
        try commit(next)
    }
}
