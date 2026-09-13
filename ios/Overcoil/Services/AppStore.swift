import SwiftUI
import ImageIO

struct PhotoDraft: Identifiable {
    var id = UUID()
    var bytes: Data
    var thumbnail: Data
    var image: UIImage
    var capture: CaptureMetadata?
    var source: PhotoSource
    var sourceWidth: Int
    var sourceHeight: Int
    var sourceOrientation: Int

    init(bytes: Data, capture: CaptureMetadata? = nil, source: PhotoSource) throws {
        guard let original = UIImage(data: bytes), original.size.width > 0, original.size.height > 0,
              let imageSource = CGImageSourceCreateWithData(bytes as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let thumbnail = UIImage(cgImage: thumb).jpegData(compressionQuality: 0.85) else { throw StoreError.invalid("This image could not be opened. The existing photo is unchanged.") }
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        sourceWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? Int(original.size.width)
        sourceHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? Int(original.size.height)
        sourceOrientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        self.bytes = bytes; self.thumbnail = thumbnail; self.capture = capture; self.source = source
        // Display/crop in an orientation-corrected coordinate space. Source bytes stay immutable.
        if original.imageOrientation == .up { image = original }
        else {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            image = UIGraphicsImageRenderer(size: original.size, format: format).image { _ in original.draw(in: CGRect(origin: .zero, size: original.size)) }
        }
    }
    func asset(watchID: UUID) -> PhotoAsset {
        PhotoAsset(id: id, watchID: watchID, source: source, savedAt: Date(), width: sourceWidth, height: sourceHeight, orientation: sourceOrientation, capture: capture)
    }
}

@Observable @MainActor final class AppStore {
    private var repository: Repository?
    private var revision = 0
    var failure: String?
    var startupError: String?
    var cloudSync: ICloudDriveSync?
    private var activeEditors = 0
    private let cache = NSCache<NSString, UIImage>()
    var database: Database { _ = revision; return repository?.database ?? Database() }
    init() { load() }
    func load() {
        do {
            var directory = "Overcoil"
            #if targetEnvironment(simulator) && DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"), let raw = ProcessInfo.processInfo.environment["OVERCOIL_UI_STORAGE"], let id = UUID(uuidString: raw) { directory = "OvercoilUITest-\(id.uuidString)" }
            #endif
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent(directory, isDirectory: true)
            repository = try Repository(root: root)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--apply-watch-identities") {
                let input = root.appendingPathComponent("identity-corrections.json")
                do {
                    let request = try JSONDecoder().decode(WatchIdentityCorrections.self, from: Data(contentsOf: input))
                    try repository!.correctWatchIdentities(request)
                    let receipt = try JSONSerialization.data(withJSONObject: ["success": true, "count": request.corrections.count])
                    try receipt.write(to: root.appendingPathComponent("identity-corrections-result.json"), options: .atomic)
                    // Input retained privately for an idempotent retry if receipt transfer fails.
                } catch {
                    let receipt = try JSONSerialization.data(withJSONObject: ["success": false, "error": error.localizedDescription])
                    try receipt.write(to: root.appendingPathComponent("identity-corrections-result.json"), options: .atomic)
                    throw error
                }
            }
            #endif
            startupError = nil; revision += 1
            #if targetEnvironment(simulator) && DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
            #endif
            let sync = ICloudDriveSync(localRoot: root)
            sync.canImport = { [weak self] in self?.activeEditors == 0 }
            sync.applyDownload = { [weak self] document, staging, expected in
                guard let self, let repository = self.repository else { throw StoreError.invalid("Local storage is unavailable.") }
                try repository.replaceFromCloud(document, downloadedRoot: staging, expectedLocalRevision: expected)
                self.cache.removeAllObjects(); self.revision += 1
            }
            cloudSync = sync
            sync.update(repository!.database)
        } catch { startupError = error.localizedDescription }
    }
    @discardableResult func perform(_ body: (Repository) throws -> Void) -> Bool {
        guard let repository else { failure = "Storage is unavailable. Your data has not been changed."; return false }
        do { try body(repository); cache.removeAllObjects(); revision += 1; cloudSync?.update(repository.database); return true }
        catch { failure = error.localizedDescription; return false }
    }
    func beginEditing() { activeEditors += 1 }
    func endEditing() {
        activeEditors = max(0, activeEditors - 1)
        if activeEditors == 0 { cloudSync?.update(database) }
    }
    func becameActive() { cloudSync?.update(database); cloudSync?.syncNow() }
    func image(_ id: UUID?, thumbnail: Bool = false) -> UIImage? {
        guard let id, let repository else { return nil }
        let key = "\(id)-\(thumbnail)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let url = thumbnail ? repository.thumbnailURL(id) : repository.imageURL(id)
        guard let bytes = try? Data(contentsOf: url), let image = UIImage(data: bytes) else { return nil }
        let normalized: UIImage
        if image.imageOrientation == .up { normalized = image }
        else {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            normalized = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        }
        cache.setObject(normalized, forKey: key, cost: Int(normalized.size.width * normalized.size.height * 4))
        cache.totalCostLimit = 80 * 1024 * 1024
        return normalized
    }
}

extension CoverCrop {
    func rect(in size: CGSize) -> CGRect {
        let edge = min(size.width, size.height) * side
        return CGRect(x: max(0, min(size.width - edge, x * size.width - edge / 2)),
                      y: max(0, min(size.height - edge, y * size.height - edge / 2)), width: edge, height: edge)
    }
    func apply(to image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let rect = rect(in: CGSize(width: cg.width, height: cg.height)).integral
        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
    }
}
