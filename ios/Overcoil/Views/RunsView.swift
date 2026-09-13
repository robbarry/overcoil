import SwiftUI

struct RunsView: View {
    @Environment(AppStore.self) private var store
    var watchID: UUID?
    var body: some View {
        let runs = store.database.runs.filter { watchID == nil || $0.watchID == watchID }.sorted {
            if $0.isActive != $1.isActive { return $0.isActive }
            return $0.createdAt > $1.createdAt
        }
        List {
            if runs.isEmpty { ContentUnavailableView("No timing runs yet", systemImage: "clock", description: Text("Start with a photo from your Watch Box.")) }
            ForEach(runs) { run in
                NavigationLink { RunDetailView(runID: run.id) } label: {
                    HStack(spacing: 12) {
                        if let watch = store.database.watches.first(where: { $0.id == run.watchID }) {
                            WatchCover(watch: watch).frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(watch.name).font(.headline)
                                Text(run.isActive ? "Run in progress" : "Completed").font(.subheadline)
                                if let first = store.database.readings(in: run.id).first {
                                    Text(first.reference.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                                if run.clockCompromised { Text("Phone clock changed — no rate").font(.caption) }
                            }
                        }
                    }
                }.listRowBackground(Theme.ivory)
            }
        }.scrollContentBackground(.hidden).background(Theme.ivory).navigationTitle(watchID == nil ? "Runs" : "Run history")
    }
}

struct RunDetailView: View {
    @Environment(AppStore.self) private var store
    var runID: UUID
    @State private var capturing = false
    @State private var ending = false
    private var run: TimingRun? { store.database.runs.first { $0.id == runID } }
    var body: some View {
        if let run {
            let readings = store.database.readings(in: runID)
            let result = RunResult.calculate(readings, clockCompromised: run.clockCompromised)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label(run.isActive ? "Run in progress" : "Completed run", systemImage: run.isActive ? "circle.fill" : "checkmark.circle").font(.subheadline).foregroundStyle(Theme.orange)
                    RunSummary(run: run, readings: readings)
                    Divider()
                    HStack {
                        VStack(alignment: .leading) { Text(elapsed(result.elapsed)).font(.title3.bold()); Text("Measured span").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        VStack { Text("\(readings.count)").font(.title3.bold()); Text("Readings").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let reason = run.endReason { Text("Ended: \(reason)").font(.subheadline).foregroundStyle(.secondary) }
                    Divider()
                    Text("Readings").font(.headline)
                    ForEach(readings.reversed()) { reading in
                        NavigationLink { ReadingDetailView(readingID: reading.id) } label: {
                            HStack(spacing: 14) {
                                if let image = store.image(reading.photoID, thumbnail: true) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 66, height: 66).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(captureDescription(reading.reference, offset: reading.capture.localUTCOffset)).font(.subheadline)
                                    Text(RunResult.displayOffset(reading.offset)).font(.headline).foregroundStyle(Theme.orange)
                                    if !reading.timingValid { Text("Clock alignment compromised").font(.caption) }
                                }
                                Spacer(); Image(systemName: "chevron.right").font(.caption)
                            }.foregroundStyle(Theme.ink).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if run.isActive {
                        PrimaryButton(title: "Add reading") { capturing = true }
                        SecondaryButton(title: "End run") { ending = true }
                    } else {
                        Text("New captures belong to a new run. You can still correct these saved readings.").font(.caption).foregroundStyle(.secondary)
                        if let active = store.database.activeRun(for: run.watchID) {
                            NavigationLink("Go to active run") { RunDetailView(runID: active.id) }
                        } else { PrimaryButton(title: "Start a new run") { capturing = true } }
                        NavigationLink("Go to watch") { WatchDetailView(watchID: run.watchID) }
                    }
                }.padding(22)
            }.background(Theme.ivory).navigationTitle(store.database.watches.first { $0.id == run.watchID }?.name ?? "Timing run").navigationBarTitleDisplayMode(.inline)
                .fullScreenCover(isPresented: $capturing) { CaptureFlow(watchID: run.watchID, runID: store.database.activeRun(for: run.watchID)?.id) }
                .confirmationDialog("End run? The rate remains based on the first and latest photos.", isPresented: $ending, titleVisibility: .visible) {
                    ForEach(["Finished", "Hands reset", "Watch stopped"], id: \.self) { reason in Button(reason) { _ = store.perform { try $0.endRun(runID, reason: reason) } } }
                    Button("Cancel", role: .cancel) {}
                }
        } else { ContentUnavailableView("Run removed", systemImage: "clock", description: Text("This run no longer has any readings. Your watch remains in Watch Box.")) }
    }
    private func elapsed(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.0f seconds", seconds) }
        if seconds < 3600 { return String(format: "%.1f minutes", seconds / 60) }
        if seconds < 172800 { return String(format: "%.1f hours", seconds / 3600) }
        return String(format: "%.1f days", seconds / 86400)
    }
}

struct ReadingDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var readingID: UUID
    @State private var editing = false
    @State private var deleting = false
    @State private var editError: String?
    private var reading: Reading? { store.database.readings.first { $0.id == readingID } }
    var body: some View {
        if let reading {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let image = store.image(reading.photoID) { ZoomPhoto(image: image).frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    Text(RunResult.displayOffset(reading.offset)).font(.title2.bold())
                    LabeledContent("Photo captured", value: captureDescription(reading.reference, offset: reading.capture.localUTCOffset))
                    LabeledContent("Capture time zone", value: zoneDescription(reading.capture.localUTCOffset))
                    if let instant = reading.entered.instant { LabeledContent("Watch time", value: captureDescription(instant, offset: reading.entered.utcOffset)) }
                    LabeledContent("Watch time basis", value: zoneDescription(reading.entered.utcOffset))
                    if !reading.timingValid { Label("Timing invalid: detected clock discontinuity", systemImage: "exclamationmark.triangle") }
                    PrimaryButton(title: "Correct entered time") { editing = true }
                    Text("Corrections keep the original image and capture timestamp unchanged.").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Capture diagnostics") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let pipeline = reading.capture.pipeline { Text("Pipeline: \(pipeline)") }
                            if let distance = reading.capture.minimumFocusDistanceMM { Text("Lens minimum focus distance: \(distance) mm") }
                            if let zoom = reading.capture.videoZoomFactor { Text("Lens zoom factor: \(zoom, specifier: "%.1f")") }
                            if let torch = reading.capture.torchEnabled { Text("Torch: \(torch ? "on" : "off")") }
                            Text("Raw capture: \(reading.capture.rawValue) / \(reading.capture.rawTimescale), epoch \(reading.capture.rawEpoch)")
                            Text("Host seconds: \(reading.capture.hostSeconds, specifier: "%.6f")")
                            Text("Anchor bracket: \(reading.capture.anchorBracketSeconds * 1000, specifier: "%.3f") ms")
                            Text("Wall/host residual: \(reading.capture.mappingResidualSeconds, specifier: "%.6f") s")
                            Text("Capture alignment is not yet physically validated. These are diagnostic timestamps, not a certified error bound.")
                        }.font(.caption).monospacedDigit().padding(.top, 8)
                    }
                    Button("Delete reading…", role: .destructive) { deleting = true }.frame(maxWidth: .infinity)
                }.padding(20)
            }.background(Theme.ivory).navigationTitle("Reading").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $editing) {
                    if let image = store.image(reading.photoID) {
                        NavigationStack {
                            TimeEntryView(image: image, capture: reading.capture, initial: reading.entered, previousOffset: reading.offset, buttonTitle: "Save correction") { entered in
                                if store.perform({ try $0.correctReading(readingID, entered: entered) }) { editing = false }
                                else { editError = store.failure; store.failure = nil }
                            }.navigationTitle("Correct reading").navigationBarTitleDisplayMode(.inline)
                                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } } }
                                .alert("Correction not saved", isPresented: Binding(get: { editError != nil }, set: { if !$0 { editError = nil } })) { Button("OK") { editError = nil } } message: { Text(editError ?? "") }
                        }
                    }
                }
                .confirmationDialog("Delete this measurement? Its photo is retained if it is your current cover. If this is the last reading, the empty run will also be removed; your watch stays.", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete reading", role: .destructive) { if store.perform({ try $0.deleteReading(readingID) }) { dismiss() } }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
}
