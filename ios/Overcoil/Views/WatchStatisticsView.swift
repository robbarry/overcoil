import SwiftUI

struct WatchStatisticsView: View {
    var stats: WatchStatistics
    @State private var explanation = false
    var body: some View {
        if let rate = stats.rate {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Overall watch rate").font(.headline)
                    Spacer()
                    Button("About the overall rate", systemImage: "info.circle") { explanation = true }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(RunResult.displayRate(rate)).font(.system(size: 54, weight: .regular, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                        .accessibilityLabel("Overall estimated \(RunResult.displayRate(rate)) seconds per day").accessibilityIdentifier("rateValue")
                    Text("seconds / day").font(.subheadline)
                }
                Text(abs(rate) < 0.05 ? "Approximately steady" : rate > 0 ? "Gaining time" : "Losing time").foregroundStyle(Theme.orange)
                Text(stats.supportText).font(.caption).foregroundStyle(.secondary)
                if stats.early { Label("Early estimate", systemImage: "clock").font(.caption) }
                if let date = stats.lastMeasurementDate { Text("Latest measurement: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            }.padding(16).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                .alert("Overall watch rate", isPresented: $explanation) { Button("OK", role: .cancel) {} } message: {
                    Text("Combines drift within all valid timing runs, weighted by their measured duration. It never compares offsets across a reset between runs. One-reading runs and compromised phone clocks do not contribute.\n\nReading count and duration show how much data supports the estimate—not a validated confidence percentage. Servicing boundaries will come later.")
                }
        }
    }
}
