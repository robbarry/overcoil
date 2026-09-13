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
    @ScaledMetric(relativeTo: .title2) private var wheelRowHeight = 38.0
    var image: UIImage
    var capture: CaptureMetadata
    var previousOffset: Double
    var saving: Bool
    var buttonTitle: String
    var prefillDescription: String
    var onSave: (WatchTime) -> Void
    @State private var entered: WatchTime
    @State private var manualDate = false
    @State private var manualPeriod = false
    @State private var expanded = false
    @State private var advanced = false
    @State private var help = false
    private let twelveHour: Bool

    init(image: UIImage, capture: CaptureMetadata, initial: WatchTime, previousOffset: Double = 0,
         saving: Bool = false, buttonTitle: String,
         prefillDescription: String = "Prefilled from phone time at capture. It stays frozen while you read the dial.",
         onSave: @escaping (WatchTime) -> Void) {
        self.image = image; self.capture = capture; self.previousOffset = previousOffset
        self.saving = saving; self.buttonTitle = buttonTitle; self.onSave = onSave
        self.prefillDescription = prefillDescription
        _entered = State(initialValue: initial)
        twelveHour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
    }
    var body: some View {
        GeometryReader { geometry in
            if dynamicTypeSize.isAccessibilitySize || geometry.size.height < 480 {
                // Accessibility sizes need a full-page scroll, never a nested
                // scrolling form under a fixed panel that hides its controls.
                ScrollView {
                    VStack(spacing: 14) {
                        entryControls(photoHeight: 200)
                        saveSection
                    }.padding(16)
                }.accessibilityIdentifier("accessibleEntryScroll")
            } else {
                VStack(spacing: 0) {
                    entryControls(photoHeight: min(300, max(120, geometry.size.height - 420)))
                        .padding(.horizontal, 18).padding(.top, 10)
                    Spacer(minLength: 8)
                    saveSection.padding(.horizontal, 16).padding(.vertical, 8)
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }
        }.background(Theme.ivory).foregroundStyle(Theme.ink)
            .environment(\.colorScheme, .light).preferredColorScheme(.light)
            .fullScreenCover(isPresented: $expanded) {
                NavigationStack {
                    ZoomPhoto(image: image).background(.black).toolbar { Button("Done") { expanded = false } }
                }
            }
            .sheet(isPresented: $advanced) { dateAndZoneSheet }
            .sheet(isPresented: $help) { helpSheet }
    }

    private func entryControls(photoHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            ZoomPhoto(image: image).frame(height: photoHeight).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    Button("Expand photo", systemImage: "arrow.up.left.and.arrow.down.right") { expanded = true }
                        .labelStyle(.iconOnly).font(.system(size: 18)).padding(12).background(.ultraThinMaterial, in: Circle()).padding(6)
                }
            Text("Photo captured · \(captureDescription(capture.reference, offset: capture.localUTCOffset))")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("What time does your watch show?").font(.headline)
            VStack(spacing: 0) {
                HStack {
                    ForEach(["HOUR", "MIN", "SEC"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                }.accessibilityHidden(true)
                CyclicTimePicker(time: entered, twelveHour: twelveHour, rowHeight: wheelRowHeight) { component, value in
                    entered = TimeWheelMath.selecting(value, component: component, in: entered, twelveHour: twelveHour)
                    inferDate()
                }.frame(height: wheelRowHeight * 3).clipped()
            }
            if twelveHour {
                Picker("AM or PM", selection: Binding(get: { entered.hour / 12 }, set: {
                    manualPeriod = true; entered.hour = entered.hour % 12 + $0 * 12; inferDate()
                })) { Text("AM").tag(0); Text("PM").tag(1) }
                    .pickerStyle(.segmented).accessibilityIdentifier("periodPicker")
            }
            HStack {
                Button("Date and time zone") { advanced = true }.font(.subheadline).frame(minHeight: 36)
                Spacer()
                Button("Reading tips", systemImage: "info.circle") { help = true }
                    .labelStyle(.iconOnly).frame(width: 44, height: 36).accessibilityIdentifier("readingTips")
            }
            if capture.clockDiscontinuity {
                Label("Phone clock changed. This reading cannot establish a rate.", systemImage: "exclamationmark.triangle").font(.caption)
            }
        }
    }
    private var saveSection: some View {
        VStack(spacing: 6) {
            if let instant = entered.instant {
                Text(RunResult.displayOffset(instant.timeIntervalSince(capture.reference)))
                    .font(.subheadline.weight(.semibold)).monospacedDigit().multilineTextAlignment(.center)
                    .accessibilityIdentifier("readingOffset")
            }
            PrimaryButton(title: saving ? "Saving…" : buttonTitle) { onSave(entered) }.disabled(saving || entered.instant == nil)
        }
    }
    private var dateAndZoneSheet: some View {
        NavigationStack {
            Form {
                Section("Interpretation") {
                    Text("\(entered.year)-\(String(format: "%02d", entered.month))-\(String(format: "%02d", entered.day)) · \(zoneDescription(entered.utcOffset))").monospacedDigit()
                    DatePicker("Watch date", selection: Binding(get: { entered.instant ?? capture.reference }, set: {
                        let parts = WatchTime.at($0, offset: entered.utcOffset)
                        entered.year = parts.year; entered.month = parts.month; entered.day = parts.day; manualDate = true
                    }), displayedComponents: .date).environment(\.timeZone, TimeZone(secondsFromGMT: entered.utcOffset) ?? .gmt)
                    Stepper("\(zoneDescription(entered.utcOffset))", value: $entered.utcOffset, in: -43200...50400, step: 900)
                        .accessibilityLabel("Watch time interpretation UTC offset")
                }
                Section {
                    Text("This is the watch’s fixed time basis, not the phone’s current location. Physically changing the hands requires a new run.")
                    Button("Suggest closest date again") { manualDate = false; inferDate() }
                }
            }.navigationTitle("Date and time zone").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { advanced = false } }
        }.preferredColorScheme(.light)
    }
    private var helpSheet: some View {
        NavigationStack {
            List {
                Section("Suggested time") { Text(prefillDescription) }
                Section("Read the dial") {
                    Text("Use the normal running seconds hand or small seconds subdial—not a stopped chronograph hand. If seconds are unclear, retake the photo.")
                    Text("Each wheel wraps in both directions independently. Moving seconds through 59 to 00 does not change the minutes or hours.")
                }
            }.navigationTitle("Reading tips").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { help = false } }
        }.preferredColorScheme(.light)
    }
    private func inferDate() {
        guard !manualDate else { return }
        entered = .nearest(hour: entered.hour, minute: entered.minute, second: entered.second, reference: capture.reference,
                           offset: entered.utcOffset, previousOffset: previousOffset, inferHalfDay: twelveHour && !manualPeriod)
    }
}
