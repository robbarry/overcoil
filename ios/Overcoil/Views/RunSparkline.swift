import SwiftUI

struct RunSparkline: View {
    var readings: [Reading]
    var clockCompromised = false
    var compact = false
    private var plot: RunPlot { RunPlot(readings: readings, clockCompromised: clockCompromised) }

    var body: some View {
        let plot = plot
        if !plot.points.isEmpty {
            VStack(alignment: .leading, spacing: compact ? 5 : 10) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Offset · seconds")
                        Spacer(minLength: 8)
                        if let change = plot.change { Text("\(RunPlot.seconds(change)) over \(plot.duration)").monospacedDigit() }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Offset · seconds")
                        if let change = plot.change { Text("\(RunPlot.seconds(change)) over \(plot.duration)").monospacedDigit() }
                    }
                }.font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Canvas { context, size in
                        let inset: CGFloat = 5
                        func location(_ point: RunPlot.Point) -> CGPoint {
                            CGPoint(x: inset + point.x * max(0, size.width - 2 * inset),
                                    y: inset + point.y * max(0, size.height - 2 * inset))
                        }
                        // A quiet baseline is a scale aid, not an uncertainty band.
                        var guide = Path()
                        guide.move(to: CGPoint(x: inset, y: size.height - inset))
                        guide.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
                        context.stroke(guide, with: .color(Theme.ink.opacity(0.10)), lineWidth: 1)
                        for index in plot.points.indices where plot.connects(index) {
                            var line = Path()
                            line.move(to: location(plot.points[index - 1])); line.addLine(to: location(plot.points[index]))
                            context.stroke(line, with: .color(Theme.orange.opacity(0.75)),
                                           style: StrokeStyle(lineWidth: compact ? 1.5 : 2, lineCap: .round, lineJoin: .round))
                        }
                        for point in plot.points {
                            let center = location(point), radius: CGFloat = compact ? 2.5 : 3.5
                            let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                            if point.valid && !clockCompromised { context.fill(dot, with: .color(Theme.orange)) }
                            else { context.stroke(dot, with: .color(Theme.ink.opacity(0.5)), lineWidth: 1.5) }
                        }
                    }
                    .frame(height: compact ? 42 : 112)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Recorded offset chart")
                    .accessibilityValue(accessibilitySummary(plot))
                    .accessibilityIdentifier("runSparkline")
                    if !compact {
                        VStack(alignment: .trailing) {
                            Text(RunPlot.seconds(plot.upper))
                            Spacer()
                            Text(RunPlot.seconds(plot.lower))
                        }.font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if !compact {
                    HStack { Text("Start"); Spacer(); Text(plot.duration) }
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }

    private func accessibilitySummary(_ plot: RunPlot) -> String {
        guard let first = plot.points.first, let last = plot.points.last else { return "No readings" }
        let warning = clockCompromised || plot.points.contains(where: { !$0.valid }) ? ". Clock alignment compromised" : ""
        return "\(plot.points.count) readings over \(plot.duration). First \(RunResult.displayOffset(first.offset)); latest \(RunResult.displayOffset(last.offset))\(warning)"
    }
}
