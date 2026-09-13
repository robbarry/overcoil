import SwiftUI

enum Theme {
    static let ivory = Color(red: 0.975, green: 0.965, blue: 0.94)
    static let orange = Color(red: 0.84, green: 0.22, blue: 0.035)
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.09)
}

struct PrimaryButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).multilineTextAlignment(.center)
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(PrimaryActionStyle())
    }
}

private struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white)
            .background(Theme.orange.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct SecondaryButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).multilineTextAlignment(.center).padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Theme.orange)
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("overcoil").font(.system(.title2, design: .serif).italic())
            Hairspring().stroke(lineWidth: 1).frame(width: 23, height: 23).accessibilityHidden(true)
        }.accessibilityLabel("Overcoil")
    }
}
struct Hairspring: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for step in 0...240 {
            let t = Double(step) / 240
            let angle = t * .pi * 7
            let r = (0.04 + t * 0.44) * min(rect.width, rect.height)
            let point = CGPoint(x: rect.midX + cos(angle) * r, y: rect.midY + sin(angle) * r)
            if step == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }
}

struct WatchCover: View {
    @Environment(AppStore.self) private var store
    var watch: Watch
    var body: some View {
        ZStack {
            Color(red: 0.91, green: 0.90, blue: 0.86)
            if let image = store.image(watch.coverID, thumbnail: true) {
                Image(uiImage: watch.crop.apply(to: image)).resizable().scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 38, weight: .ultraLight))
                    Text("Your watch, your photo").font(.caption)
                }.foregroundStyle(.secondary)
            }
        }.aspectRatio(1, contentMode: .fit).clipped().accessibilityLabel("Reference photo for \(watch.displayName)")
    }
}

struct RunSummary: View {
    var run: TimingRun
    var readings: [Reading]
    var compact = false
    var body: some View {
        let result = RunResult.calculate(readings, clockCompromised: run.clockCompromised)
        VStack(alignment: .leading, spacing: 12) {
            if run.clockCompromised {
                Label("Phone clock changed", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text("Readings retained. A new run is needed; no rate is published for this run.").font(.subheadline)
            } else if let rate = result.rate {
                Text(RunResult.displayRate(rate))
                    .font(.system(size: compact ? 42 : 76, weight: .regular, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    .accessibilityLabel("Estimated \(RunResult.displayRate(rate)) seconds per day").accessibilityIdentifier("rateValue")
                Text("seconds / day").font(compact ? .subheadline : .title3)
                Text(abs(rate) < 0.05 ? "Approximately steady—not perfect accuracy" : rate > 0 ? "Gaining time" : "Losing time")
                    .foregroundStyle(Theme.orange).font(.subheadline)
                if result.early { Label("Early estimate", systemImage: "clock.badge.exclamationmark").font(.caption.bold()) }
                if !compact {
                    Text("Average since the first reading").font(.caption).foregroundStyle(.secondary)
                    if result.early { Text("Add another reading tomorrow. Longer intervals reduce the effect of reading error.").font(.caption).foregroundStyle(.secondary) }
                }
            } else if let first = readings.first {
                Text(RunResult.displayOffset(first.offset)).font(.title2).monospacedDigit()
                Text("\(readings.count) reading\(readings.count == 1 ? "" : "s") saved").font(.subheadline)
                Text(readings.count == 1 ? "Add another reading to measure the rate." : "Readings need different capture times to measure the rate.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

func captureDescription(_ date: Date, offset: Int) -> String {
    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .medium
    f.timeZone = TimeZone(secondsFromGMT: offset)
    return f.string(from: date)
}
func zoneDescription(_ seconds: Int) -> String {
    let sign = seconds < 0 ? "−" : "+"
    return String(format: "UTC%@%02d:%02d", sign, abs(seconds) / 3600, (abs(seconds) % 3600) / 60)
}

// Shared by the real camera and the simulator capture fixture, so transition
// tests exercise the same appearance boundary as a physical photo capture.
struct CameraSurface: ViewModifier {
    func body(content: Content) -> some View {
        // Keep dark styling local to the camera. preferredColorScheme propagates
        // to the entire presentation and can leak into the ivory reading screen.
        content.foregroundStyle(.white).background(.black).environment(\.colorScheme, .dark)
    }
}

struct CloudEditingGuard: ViewModifier {
    @Environment(AppStore.self) private var store
    @State private var active = false
    func body(content: Content) -> some View {
        content.onAppear { if !active { active = true; store.beginEditing() } }
            .onDisappear { if active { active = false; store.endEditing() } }
    }
}
