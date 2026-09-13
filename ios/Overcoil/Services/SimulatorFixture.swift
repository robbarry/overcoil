#if targetEnvironment(simulator) && DEBUG
import SwiftUI

// Deterministic test seam only. Not compiled into iPhone builds, never enabled by
// default, and visibly labeled. This tests UI/data flow, NOT camera alignment.
@MainActor enum SimulatorFixture {
    static var sequence = 0
    static func photo(coverOnly: Bool) throws -> PhotoDraft {
        let index = sequence; sequence += 1
        let rollover = ProcessInfo.processInfo.arguments.contains("--ui-rollover")
        let base = rollover ? 1_789_300_859.0 : 1_789_294_080.0
        let reference = Date(timeIntervalSince1970: base + Double(index) * 86400)
        let shown = WatchTime.at(reference.addingTimeInterval(rollover ? 2 : Double(8 + 6 * index)), offset: 0)
        let size = CGSize(width: 900, height: 900)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let c = context.cgContext
            UIColor(red: 0.85, green: 0.83, blue: 0.77, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill(); c.fillEllipse(in: CGRect(x: 70, y: 70, width: 760, height: 760))
            UIColor.darkGray.setStroke(); c.setLineWidth(14); c.strokeEllipse(in: CGRect(x: 70, y: 70, width: 760, height: 760))
            for i in 0..<60 {
                let angle = Double(i) * .pi / 30 - .pi / 2
                let inner = i % 5 == 0 ? 318.0 : 342.0
                c.setLineWidth(i % 5 == 0 ? 7 : 2)
                c.move(to: CGPoint(x: 450 + cos(angle) * inner, y: 450 + sin(angle) * inner))
                c.addLine(to: CGPoint(x: 450 + cos(angle) * 359, y: 450 + sin(angle) * 359)); c.strokePath()
            }
            func hand(_ fraction: Double, length: Double, width: CGFloat, color: UIColor) {
                let angle = fraction * 2 * .pi - .pi / 2
                color.setStroke(); c.setLineWidth(width); c.setLineCap(.round)
                c.move(to: CGPoint(x: 450, y: 450)); c.addLine(to: CGPoint(x: 450 + cos(angle) * length, y: 450 + sin(angle) * length)); c.strokePath()
            }
            hand((Double(shown.hour % 12) + Double(shown.minute) / 60) / 12, length: 200, width: 18, color: .black)
            hand(Double(shown.minute) / 60, length: 290, width: 11, color: .black)
            hand(Double(shown.second) / 60, length: 310, width: 4, color: .systemOrange)
            ("SIMULATOR TEST" as NSString).draw(at: CGPoint(x: 288, y: 610), withAttributes: [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: UIColor.darkGray])
        }
        let capture = CaptureMetadata(reference: reference, localUTCOffset: 0, rawValue: Int64(index * 86400), rawTimescale: 1, rawEpoch: 0, hostSeconds: Double(index) * 86400, anchorHostSeconds: Double(index) * 86400, anchorWall: reference, anchorBracketSeconds: 0, mappingResidualSeconds: 0, continuityID: UUID(), clockDiscontinuity: false)
        return try PhotoDraft(bytes: image.jpegData(compressionQuality: 0.9)!, capture: coverOnly ? nil : capture, source: coverOnly ? .cameraCover : .timing)
    }
}

struct SimulatorCameraView: View {
    var coverOnly: Bool
    var onClose: () -> Void
    var onPhoto: (PhotoDraft) -> Void
    @State private var error: String?
    var body: some View {
        VStack(spacing: 30) {
            Text("SIMULATOR TEST CAMERA").font(.headline)
            Text("Synthetic image and timestamp. Does not validate AVFoundation or capture accuracy.").multilineTextAlignment(.center)
            Button("Take simulator test photo") {
                do { onPhoto(try SimulatorFixture.photo(coverOnly: coverOnly)) } catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent)
            Button("Close", action: onClose)
            if let error { Text(error) }
        }.padding(30).modifier(CameraSurface())
    }
}
#endif
