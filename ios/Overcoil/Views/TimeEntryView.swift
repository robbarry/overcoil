import SwiftUI

struct ZoomPhoto: UIViewRepresentable {
    var image: UIImage
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView(); scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 6; scroll.backgroundColor = .clear
        scroll.accessibilityLabel = "Watch photograph. Pinch to zoom and drag to inspect the dial."
        let view = context.coordinator.imageView; view.contentMode = .scaleAspectFit; view.image = image
        scroll.addSubview(view)
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.imageView.image = image
        // Defer until SwiftUI's representable has its final bounds.
        DispatchQueue.main.async {
            if scroll.zoomScale == 1 {
                context.coordinator.imageView.frame = scroll.bounds
                scroll.contentSize = scroll.bounds.size
            }
        }
    }
}

struct TimeEntryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var image: UIImage
    var capture: CaptureMetadata
    var previousOffset: Double
    var saving: Bool
    var buttonTitle: String
    var prefillDescription: String
    var predictionLabel: String?
    var onSave: (WatchTime) -> Void
    @State private var entered: WatchTime
    @State private var manualDate = false
    @State private var manualPeriod = false
    @State private var expanded = false
    @State private var advanced = false
    private let twelveHour: Bool

    init(image: UIImage, capture: CaptureMetadata, initial: WatchTime, previousOffset: Double = 0,
         saving: Bool = false, buttonTitle: String,
         prefillDescription: String = "Prefilled from phone time at capture. It stays frozen while you read the dial.",
         predictionLabel: String? = nil, onSave: @escaping (WatchTime) -> Void) {
        self.image = image; self.capture = capture; self.previousOffset = previousOffset
        self.saving = saving; self.buttonTitle = buttonTitle; self.onSave = onSave
        self.prefillDescription = prefillDescription
        self.predictionLabel = predictionLabel
        _entered = State(initialValue: initial)
        twelveHour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZoomPhoto(image: image).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        Button("Expand photo", systemImage: "arrow.up.left.and.arrow.down.right") { expanded = true }
                            .labelStyle(.iconOnly).font(.system(size: 18)).padding(12).background(.ultraThinMaterial, in: Circle()).padding(8)
                    }
                Text("Photo captured · \(captureDescription(capture.reference, offset: capture.localUTCOffset))")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("What time does your watch show?").font(.headline)
                HStack(spacing: 0) {
                    VStack {
                        Text("HOUR").font(.caption).foregroundStyle(.secondary)
                        Picker("Hour", selection: hourBinding) {
                            ForEach(twelveHour ? Array(1...12) : Array(0...23), id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }.pickerStyle(.wheel).accessibilityIdentifier("hourPicker")
                    }
                    VStack {
                        Text("MIN").font(.caption).foregroundStyle(.secondary)
                        Picker("Minute", selection: componentBinding(\.minute)) {
                            ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }.pickerStyle(.wheel).accessibilityIdentifier("minutePicker")
                    }
                    VStack {
                        Text("SEC").font(.caption).foregroundStyle(.secondary)
                        Picker("Second", selection: componentBinding(\.second)) {
                            ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }.pickerStyle(.wheel).accessibilityIdentifier("secondPicker")
                    }
                }.frame(height: 140).monospacedDigit()
                if twelveHour {
                    Picker("AM or PM", selection: Binding(get: { entered.hour / 12 }, set: { manualPeriod = true; entered.hour = entered.hour % 12 + $0 * 12; inferDate() })) {
                        Text("AM").tag(0); Text("PM").tag(1)
                    }.pickerStyle(.segmented)
                }
                Text(prefillDescription).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                DisclosureGroup("Date and time zone", isExpanded: $advanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(entered.year)-\(String(format: "%02d", entered.month))-\(String(format: "%02d", entered.day)) · \(zoneDescription(entered.utcOffset))").font(.subheadline).monospacedDigit()
                        DatePicker("Watch date", selection: Binding(get: { entered.instant ?? capture.reference }, set: {
                            let parts = WatchTime.at($0, offset: entered.utcOffset)
                            entered.year = parts.year; entered.month = parts.month; entered.day = parts.day; manualDate = true
                        }), displayedComponents: .date).environment(\.timeZone, TimeZone(secondsFromGMT: entered.utcOffset) ?? .gmt)
                        Stepper("\(zoneDescription(entered.utcOffset))", value: $entered.utcOffset, in: -43200...50400, step: 900)
                            .accessibilityLabel("Watch time interpretation UTC offset")
                        Text("This is the watch's fixed time basis, not the phone's current location. Changing the hands physically requires a new run.").font(.caption).foregroundStyle(.secondary)
                        Button("Suggest closest date again") { manualDate = false; inferDate() }
                    }.padding(.top, 12)
                }.font(.subheadline)
                if capture.clockDiscontinuity {
                    Label("A phone-clock change was detected. This photo can be retained, but the run will end without a rate.", systemImage: "exclamationmark.triangle").font(.subheadline)
                }
                Text("Read the normal timekeeping seconds hand, including a small seconds subdial—not a stopped chronograph hand. If seconds are unclear, retake the photo.")
                    .font(.caption).foregroundStyle(.secondary)
                if dynamicTypeSize.isAccessibilitySize { saveSection }
            }.padding(18)
        }.background(Theme.ivory).foregroundStyle(Theme.ink)
            .environment(\.colorScheme, .light).preferredColorScheme(.light)
            .safeAreaInset(edge: .bottom) {
                if !dynamicTypeSize.isAccessibilitySize { saveSection.padding(16).background(Theme.ivory) }
            }
            .fullScreenCover(isPresented: $expanded) {
                NavigationStack {
                    ZoomPhoto(image: image).background(.black).toolbar { Button("Done") { expanded = false } }
                }
            }
    }
    private var saveSection: some View {
        VStack(spacing: 10) {
            if let predictionLabel { Text(predictionLabel).font(.caption).foregroundStyle(.secondary) }
            if let instant = entered.instant {
                Text(RunResult.displayOffset(instant.timeIntervalSince(capture.reference))).font(.headline).monospacedDigit().multilineTextAlignment(.center)
            }
            PrimaryButton(title: saving ? "Saving…" : buttonTitle) { onSave(entered) }.disabled(saving || entered.instant == nil)
        }
    }
    private var hourBinding: Binding<Int> {
        Binding(get: { twelveHour ? (entered.hour % 12 == 0 ? 12 : entered.hour % 12) : entered.hour }, set: {
            entered.hour = twelveHour ? $0 % 12 + (entered.hour / 12) * 12 : $0; inferDate()
        })
    }
    private func componentBinding(_ path: WritableKeyPath<WatchTime, Int>) -> Binding<Int> {
        Binding(get: { entered[keyPath: path] }, set: { entered[keyPath: path] = $0; inferDate() })
    }
    private func inferDate() {
        guard !manualDate else { return }
        entered = .nearest(hour: entered.hour, minute: entered.minute, second: entered.second, reference: capture.reference,
                           offset: entered.utcOffset, previousOffset: previousOffset, inferHalfDay: twelveHour && !manualPeriod)
    }
}
