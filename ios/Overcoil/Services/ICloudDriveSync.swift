import SwiftUI

private struct CloudPreferences: Codable {
    var enabled = true
    var baseline: String?
    var accountArchive: Data?
    var lastUploaded: Date?
}

struct CloudVersionChoice: Identifiable, Sendable {
    var id: String
    var watchCount: Int
    var readingCount: Int
    var date: Date
}

private enum CloudResolution: Sendable { case local, cloud(String) }
private enum CloudWorkerResult: Sendable {
    case settled(revision: String?, uploaded: Bool)
    case downloaded(CloudLibrary, root: URL, expectedLocalRevision: String)
    case conflict([CloudVersionChoice])
    case waiting(String)
    case failed(String)
}
private enum CloudWorkError: LocalizedError {
    case waiting, changed, cancelled
    var errorDescription: String? {
        switch self {
        case .waiting: "Waiting for iCloud to download the library or its photos. Local data is unchanged."
        case .changed: "The library changed during sync. Checking again without overwriting either copy."
        case .cancelled: "Sync paused."
        }
    }
}
private final class CloudCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws { lock.lock(); defer { lock.unlock() }; if cancelled { throw CloudWorkError.cancelled } }
}

// Every cloud read/write goes through coordination on this serial worker. The
// authoritative document changes atomically, after its immutable photos exist.
private final class CloudDriveWorker: @unchecked Sendable {
    static let container = "iCloud.com.robbarry.overcoil"
    private let queue = DispatchQueue(label: "com.robbarry.overcoil.icloud")
    private let fm = FileManager.default
    private let coordinator = NSFileCoordinator(filePresenter: nil)

    func resolve(completion: @escaping @MainActor @Sendable (URL?, Data?, String?) -> Void) {
        queue.async { [self] in
            guard let token = fm.ubiquityIdentityToken else {
                Task { @MainActor in completion(nil, nil, "Sign into iCloud and enable iCloud Drive on this device. Your local Watch Box remains available.") }; return
            }
            do {
                let archive = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
                guard let root = fm.url(forUbiquityContainerIdentifier: Self.container)?.appendingPathComponent("Documents") else {
                    Task { @MainActor in completion(nil, archive, "Overcoil’s iCloud Drive container is not available yet. Check iCloud Drive and the app’s iCloud access.") }; return
                }
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                Task { @MainActor in completion(root, archive, nil) }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in completion(nil, nil, message) }
            }
        }
    }
    static func sameAccount(_ first: Data, _ second: Data) -> Bool {
        func object(_ data: Data) -> NSObject? {
            guard let decoder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
            decoder.requiresSecureCoding = false
            defer { decoder.finishDecoding() }
            return decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSObject
        }
        if let a = object(first), let b = object(second) { return a.isEqual(b) }
        return first == second
    }
    private func read(_ url: URL) throws -> Data? {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if let downloadStatus = values?.ubiquitousItemDownloadingStatus, downloadStatus != .current {
            try fm.startDownloadingUbiquitousItem(at: url); throw CloudWorkError.waiting
        }
        guard fm.fileExists(atPath: url.path) else { return nil }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { location in
            result = Result { try Data(contentsOf: location) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CloudWorkError.waiting }
        return try result.get()
    }
    private func write(_ bytes: Data, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { location in
            do { try bytes.write(to: location, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
    private func immutable(_ bytes: Data, to url: URL, cancellation: CloudCancellation) throws {
        try cancellation.check()
        if let old = try read(url) {
            guard old == bytes else { throw StoreError.invalid("An iCloud photo or recovery file has conflicting contents. Nothing was overwritten.") }
        } else { try write(bytes, to: url) }
    }
    private func downloaded(_ document: CloudLibrary, cloudRoot: URL, localRoot: URL, cancellation: CloudCancellation) throws -> URL {
        let staging = localRoot.appendingPathComponent("SyncDownloads/\(document.revision)")
        for photo in document.photoFiles {
            for (path, hash) in [(photo.originalPath, photo.originalSHA256), (photo.thumbnailPath, photo.thumbnailSHA256)] {
                try cancellation.check()
                let target = staging.appendingPathComponent(path)
                if let cached = try? Data(contentsOf: target), CloudLibrary.hash(cached) == hash { continue }
                guard let bytes = try read(cloudRoot.appendingPathComponent(path)) else { throw CloudWorkError.waiting }
                guard CloudLibrary.hash(bytes) == hash else { throw StoreError.invalid("An iCloud photo does not match its recorded checksum. Local evidence is unchanged.") }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: target, options: .atomic)
            }
        }
        try document.verifyPhotos(in: staging)
        return staging
    }
    private func recovery(_ data: Data, document: CloudLibrary, cloudRoot: URL, localRoot: URL, includePhotos: Bool, cancellation: CloudCancellation) throws {
        try cancellation.check()
        let local = localRoot.appendingPathComponent("CloudRecovery/\(document.revision)")
        try fm.createDirectory(at: local, withIntermediateDirectories: true)
        try data.write(to: local.appendingPathComponent("Library.overcoil.json"), options: .atomic)
        if includePhotos {
            let source = try downloaded(document, cloudRoot: cloudRoot, localRoot: localRoot, cancellation: cancellation)
            for photo in document.photoFiles {
                for path in [photo.originalPath, photo.thumbnailPath] {
                    let target = local.appendingPathComponent(path)
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: source.appendingPathComponent(path), to: target) }
                }
            }
        }
        // Recovery filenames include the raw-document checksum, so two versions
        // with identical records but different metadata never overwrite each other.
        try immutable(data, to: cloudRoot.appendingPathComponent("Recovery/\(CloudLibrary.hash(data)).json"), cancellation: cancellation)
    }
    private func publish(_ document: CloudLibrary, sourceRoot: URL, sourceIsDownloaded: Bool, cloudRoot: URL,
                         expectedData: Data?, force: Bool, cancellation: CloudCancellation) throws {
        for photo in document.photoFiles {
            let original = sourceIsDownloaded ? sourceRoot.appendingPathComponent(photo.originalPath) : sourceRoot.appendingPathComponent("images/\(photo.id.uuidString).image")
            let thumb = sourceIsDownloaded ? sourceRoot.appendingPathComponent(photo.thumbnailPath) : sourceRoot.appendingPathComponent("images/\(photo.id.uuidString).thumb")
            try immutable(Data(contentsOf: original), to: cloudRoot.appendingPathComponent(photo.originalPath), cancellation: cancellation)
            try immutable(Data(contentsOf: thumb), to: cloudRoot.appendingPathComponent(photo.thumbnailPath), cancellation: cancellation)
        }
        let url = cloudRoot.appendingPathComponent("Library.overcoil.json")
        let bytes = try document.encoded()
        try cancellation.check()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { location in
            do {
                let current = try? Data(contentsOf: location)
                guard force || current == expectedData else { throw CloudWorkError.changed }
                try cancellation.check()
                try bytes.write(to: location, options: .atomic)
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
    private func uploaded(_ document: CloudLibrary, root: URL) throws -> Bool {
        let paths = ["Library.overcoil.json"] + document.photoFiles.flatMap { [$0.originalPath, $0.thumbnailPath] }
        let allUploaded = try paths.allSatisfy { path in
            guard let values = try? root.appendingPathComponent(path).resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey]) else { return false }
            if let error = values.ubiquitousItemUploadingError { throw error }
            return values.ubiquitousItemIsUploaded == true
        }
        guard allUploaded else { return false }
        for photo in document.photoFiles {
            for (path, expected) in [(photo.originalPath, photo.originalSHA256), (photo.thumbnailPath, photo.thumbnailSHA256)] {
                guard let data = try read(root.appendingPathComponent(path)), CloudLibrary.hash(data) == expected else {
                    throw StoreError.invalid("An uploaded iCloud photo does not match the library checksum. Local data is safe; the cloud copy needs attention.")
                }
            }
        }
        return true
    }
    func run(database: Database, localRoot: URL, cloudRoot: URL, baseline: String?, resolution: CloudResolution?,
             cancellation: CloudCancellation, completion: @escaping @MainActor @Sendable (CloudWorkerResult) -> Void) {
        queue.async { [self] in
            let result: CloudWorkerResult
            do {
                try cancellation.check()
                let localRevision = try CloudLibrary.revision(of: database)
                let url = cloudRoot.appendingPathComponent("Library.overcoil.json")
                let remoteData = try read(url)
                let remote = try remoteData.map { try CloudLibrary.decode($0) }
                let fileVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
                var versions: [(CloudLibrary, Data)] = []
                if let remote, let remoteData { versions.append((remote, remoteData)) }
                for version in fileVersions {
                    if let data = try read(version.url) { versions.append((try CloudLibrary.decode(data), data)) }
                }
                if let resolution {
                    // A conflict is resolved only after preserving every readable
                    // cloud version and its photos locally, plus recovery metadata
                    // in Drive. Existing cloud photos are never garbage-collected.
                    for (document, data) in versions {
                        try recovery(data, document: document, cloudRoot: cloudRoot, localRoot: localRoot, includePhotos: true, cancellation: cancellation)
                    }
                    switch resolution {
                    case .local:
                        let document = try CloudLibrary.build(database: database, localRoot: localRoot, parentRevision: remote?.revision)
                        try publish(document, sourceRoot: localRoot, sourceIsDownloaded: false, cloudRoot: cloudRoot, expectedData: remoteData, force: false, cancellation: cancellation)
                        for version in fileVersions { version.isResolved = true }
                        result = .settled(revision: document.revision, uploaded: try uploaded(document, root: cloudRoot))
                    case .cloud(let revision):
                        guard var selected = versions.first(where: { $0.0.revision == revision })?.0 else { throw CloudWorkError.changed }
                        let staging = try downloaded(selected, cloudRoot: cloudRoot, localRoot: localRoot, cancellation: cancellation)
                        selected.parentRevision = remote?.revision; selected.publishedAt = Date()
                        try publish(selected, sourceRoot: staging, sourceIsDownloaded: true, cloudRoot: cloudRoot, expectedData: remoteData, force: false, cancellation: cancellation)
                        for version in fileVersions { version.isResolved = true }
                        result = .downloaded(selected, root: staging, expectedLocalRevision: localRevision)
                    }
                } else {
                    let decision = CloudSyncDecision.choose(localRevision: localRevision, remoteRevision: remote?.revision,
                                                          baseline: baseline, localIsEmpty: database.watches.isEmpty)
                    if !fileVersions.isEmpty || decision == .conflict || decision == .remoteMissing {
                        var seen = Set<String>()
                        let choices = versions.compactMap { document, _ -> CloudVersionChoice? in
                            guard seen.insert(document.revision).inserted else { return nil }
                            return CloudVersionChoice(id: document.revision, watchCount: document.database.watches.count,
                                                      readingCount: document.database.readings.count, date: document.publishedAt)
                        }
                        result = .conflict(choices)
                    } else {
                        switch decision {
                        case .empty: result = .settled(revision: nil, uploaded: false)
                        case .inSync:
                            result = .settled(revision: remote?.revision, uploaded: try remote.map { try uploaded($0, root: cloudRoot) } ?? false)
                        case .download:
                            guard let remote else { throw CloudWorkError.changed }
                            let staging = try downloaded(remote, cloudRoot: cloudRoot, localRoot: localRoot, cancellation: cancellation)
                            result = .downloaded(remote, root: staging, expectedLocalRevision: localRevision)
                        case .upload:
                            if let remote, let remoteData { try recovery(remoteData, document: remote, cloudRoot: cloudRoot, localRoot: localRoot, includePhotos: false, cancellation: cancellation) }
                            let document = try CloudLibrary.build(database: database, localRoot: localRoot, parentRevision: remote?.revision)
                            try publish(document, sourceRoot: localRoot, sourceIsDownloaded: false, cloudRoot: cloudRoot, expectedData: remoteData, force: false, cancellation: cancellation)
                            let readme = "Overcoil iCloud library\n\nLibrary.overcoil.json holds the complete shared Watch Box, runs, readings, and photo checksums. Photos/ contains originals; Thumbnails/ contains previews. The same iCloud account and iCloud Drive must be enabled on each Overcoil device.\n\nTreat these app-managed files as read-only. Copy them elsewhere before editing. Recovery/ preserves older metadata, and originals are retained for recovery even after a reading is deleted. Do not remove photos referenced by the current library. Local app data remains available offline.\n"
                            let readmeURL = cloudRoot.appendingPathComponent("README.txt")
                            if !fm.fileExists(atPath: readmeURL.path) { try write(Data(readme.utf8), to: readmeURL) }
                            result = .settled(revision: document.revision, uploaded: try uploaded(document, root: cloudRoot))
                        case .conflict, .remoteMissing: result = .conflict([])
                        }
                    }
                }
            } catch CloudWorkError.waiting { result = .waiting(CloudWorkError.waiting.localizedDescription) }
            catch CloudWorkError.changed { result = .waiting(CloudWorkError.changed.localizedDescription) }
            catch CloudWorkError.cancelled { result = .waiting("Sync paused.") }
            catch { result = .failed(error.localizedDescription) }
            Task { @MainActor in completion(result) }
        }
    }
}

@Observable @MainActor final class ICloudDriveSync {
    var status = "Checking iCloud Drive…" { didSet { recordStatus() } }
    var isEnabled: Bool
    var isWorking = false
    var lastUploaded: Date?
    var conflictChoices: [CloudVersionChoice] = []
    var hasConflict = false
    var accountChanged = false
    private(set) var documentsURL: URL?
    private let localRoot: URL
    private let worker = CloudDriveWorker()
    private var preferences: CloudPreferences
    private var database = Database()
    private var metadataReady = false
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var queryObservers: [NSObjectProtocol] = []
    private var scheduled: Task<Void, Never>?
    private var cancellation = CloudCancellation()
    private var needsAnotherPass = false
    private var pendingAccount: Data?
    private var generation = 0
    private var autoRestoreCheck = false
    var canImport: () -> Bool = { true }
    var applyDownload: ((CloudLibrary, URL, String) throws -> Void)?

    init(localRoot: URL) {
        self.localRoot = localRoot
        let preferencesURL = localRoot.appendingPathComponent("cloud-preferences.json")
        let loaded: CloudPreferences
        var settingsFailed = false
        if FileManager.default.fileExists(atPath: preferencesURL.path) {
            if let data = try? Data(contentsOf: preferencesURL), let decoded = try? JSONDecoder().decode(CloudPreferences.self, from: data) { loaded = decoded }
            else { loaded = CloudPreferences(enabled: false); settingsFailed = true }
        } else { loaded = CloudPreferences() }
        preferences = loaded
        isEnabled = loaded.enabled; lastUploaded = loaded.lastUploaded
        if settingsFailed { status = "Sync settings could not be read. Sync is off until you enable it again; local data is safe." }
        #if DEBUG
        autoRestoreCheck = ProcessInfo.processInfo.arguments.contains("--verify-icloud-restore")
        #endif
        observers.append(NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restart() }
        })
    }
    private func recordStatus() {
        let report: [String: Any] = ["checkedAtUTC": Date().ISO8601Format(), "status": status, "enabled": isEnabled,
            "working": isWorking, "metadataReady": metadataReady, "hasConflict": hasConflict,
            "accountChanged": accountChanged, "hasContainerURL": documentsURL != nil]
        // Local, best-effort diagnostics only: no account token, watch names,
        // readings, or photo bytes, and never included in the cloud document.
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]) {
            try? data.write(to: localRoot.appendingPathComponent("cloud-status.json"), options: .atomic)
        }
    }
    private func persist() throws {
        try JSONEncoder().encode(preferences).write(to: localRoot.appendingPathComponent("cloud-preferences.json"), options: .atomic)
    }
    func update(_ database: Database) { self.database = database; schedule() }
    func setEnabled(_ enabled: Bool) {
        let old = preferences.enabled; preferences.enabled = enabled
        do { try persist(); isEnabled = enabled; restart() }
        catch { preferences.enabled = old; status = error.localizedDescription }
    }
    func confirmCurrentAccount() {
        guard let pendingAccount else { return }
        preferences.accountArchive = pendingAccount; preferences.baseline = nil
        do { try persist(); accountChanged = false; restart() } catch { status = error.localizedDescription }
    }
    func restart() {
        generation += 1; cancellation.cancel(); cancellation = CloudCancellation()
        scheduled?.cancel(); query?.stop(); query = nil
        queryObservers.forEach { NotificationCenter.default.removeObserver($0) }; queryObservers = []
        metadataReady = false; documentsURL = nil; isWorking = false
        guard isEnabled else { status = "iCloud sync is off. Local data and existing cloud copies are retained."; return }
        let current = generation
        status = "Checking iCloud Drive…"; isWorking = true
        worker.resolve { [weak self] root, account, error in
            guard let self, self.generation == current else { return }
            self.isWorking = false
            guard let root, let account else { self.status = error ?? "iCloud Drive is unavailable."; return }
            if let previous = self.preferences.accountArchive, !CloudDriveWorker.sameAccount(previous, account) {
                self.pendingAccount = account; self.accountChanged = true
                self.status = "The iCloud account changed. Sync is paused until you confirm where this Watch Box should go."; return
            }
            self.preferences.accountArchive = account
            do { try self.persist() } catch { self.status = error.localizedDescription; return }
            self.documentsURL = root; self.beginQuery(root)
        }
    }
    private func beginQuery(_ root: URL) {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // Entitlements restrict this query to accessible document containers. A
        // change only triggers work against the explicit Overcoil root above;
        // never derive read/write targets from unrelated metadata results.
        query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*")
        query.notificationBatchingInterval = 0.5
        let current = generation
        queryObservers.append(NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self, self.generation == current else { return }; self.metadataReady = true; self.schedule() }
        })
        queryObservers.append(NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self, self.generation == current else { return }; self.schedule() }
        })
        self.query = query
        if !query.start() { status = "iCloud metadata is not ready. Tap Sync now to retry." }
        else { status = "Discovering the shared iCloud library…" }
    }
    private func schedule() {
        guard isEnabled, !accountChanged else { return }
        guard documentsURL != nil else { if !isWorking { restart() }; return }
        guard metadataReady else { return }
        if isWorking { needsAnotherPass = true; return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.run(resolution: nil)
        }
    }
    func syncNow() { if documentsURL == nil || !metadataReady { restart() } else { run(resolution: nil) } }
    func verifyRestore() {
        guard isEnabled, !accountChanged, !isWorking, metadataReady, let root = documentsURL else { return }
        isWorking = true; status = "Verifying restore into a separate local check copy…"
        let current = generation
        let before = try? CloudLibrary.revision(of: database)
        let probeRoot = localRoot.appendingPathComponent("SyncRestoreChecks/\(UUID().uuidString)")
        // An empty read-only replica can only download or wait; it never publishes
        // an empty library. It has no AppStore/controller that could queue uploads.
        worker.run(database: Database(), localRoot: probeRoot, cloudRoot: root, baseline: nil, resolution: nil, cancellation: cancellation) { [weak self] result in
            guard let self, self.generation == current else { return }
            self.isWorking = false
            do {
                guard case let .downloaded(document, staging, expected) = result else {
                    self.status = "Restore check is waiting for a complete, conflict-free iCloud library."; return
                }
                let check = try Repository(root: probeRoot)
                try check.replaceFromCloud(document, downloadedRoot: staging, expectedLocalRevision: expected)
                let restored = try CloudLibrary.revision(of: check.database)
                let after = try CloudLibrary.revision(of: self.database)
                guard restored == document.revision else { throw StoreError.invalid("The restored check copy did not match the cloud revision.") }
                let receipt: [String: Any] = ["success": true, "checkedAtUTC": Date().ISO8601Format(), "cloudRevision": document.revision,
                    "watches": check.database.watches.count, "readings": check.database.readings.count, "photos": check.database.photos.count,
                    "originalLibraryUnchanged": before == after]
                try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys, .prettyPrinted]).write(to: self.localRoot.appendingPathComponent("sync-restore-check.json"), options: .atomic)
                self.status = "Restore verified: \(check.database.watches.count) watches, \(check.database.readings.count) readings, \(check.database.photos.count) photos. The check used a separate local copy."
            } catch { self.status = "Restore check needs attention: " + error.localizedDescription }
            if self.needsAnotherPass { self.needsAnotherPass = false; self.schedule() }
        }
    }
    func keepThisDevice() { run(resolution: .local) }
    func useCloud(_ revision: String) { run(resolution: .cloud(revision)) }
    private func run(resolution: CloudResolution?) {
        guard isEnabled, !accountChanged, let root = documentsURL, metadataReady else { return }
        guard !isWorking else { needsAnotherPass = true; return }
        if resolution != nil && !canImport() { status = "Finish the open edit before resolving the sync conflict."; return }
        scheduled?.cancel(); isWorking = true; needsAnotherPass = false
        status = "Syncing Watch Box and photos…"
        let current = generation
        worker.run(database: database, localRoot: localRoot, cloudRoot: root, baseline: preferences.baseline,
                   resolution: resolution, cancellation: cancellation) { [weak self] result in
            guard let self, self.generation == current else { return }
            self.isWorking = false
            switch result {
            case .settled(let revision, let uploaded):
                self.hasConflict = false; self.conflictChoices = []
                self.preferences.baseline = revision
                if uploaded { self.preferences.lastUploaded = Date(); self.lastUploaded = self.preferences.lastUploaded }
                do { try self.persist() } catch { self.status = error.localizedDescription; return }
                self.status = revision == nil ? "Ready. Saved watches will sync automatically." : uploaded ? "Current Watch Box and photos are uploaded to iCloud Drive." : "Saved in iCloud Drive; waiting for Apple to finish uploading."
                if uploaded && self.autoRestoreCheck { self.autoRestoreCheck = false; self.verifyRestore(); return }
            case .downloaded(let document, let staging, let expected):
                guard self.canImport() else { self.status = "iCloud has updates. They will be applied after you finish editing."; return }
                do {
                    guard let apply = self.applyDownload else { throw StoreError.invalid("The local library is not ready for restore.") }
                    try apply(document, staging, expected)
                    self.database = document.database; self.preferences.baseline = document.revision
                    try self.persist(); self.hasConflict = false; self.conflictChoices = []
                    self.status = "Restored the iCloud library. Checking upload status…"; self.needsAnotherPass = true
                } catch { self.status = error.localizedDescription }
            case .conflict(let choices):
                self.hasConflict = true; self.conflictChoices = choices
                self.status = "This device and iCloud differ, or the cloud library is missing. Neither copy has been overwritten. Choose which library to use; recovery copies are kept."
            case .waiting(let message): self.status = message
            case .failed(let message): self.status = "Sync needs attention: " + message
            }
            if self.needsAnotherPass { self.needsAnotherPass = false; self.schedule() }
        }
    }
}
