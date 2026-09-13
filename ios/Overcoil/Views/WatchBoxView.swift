import SwiftUI
import PhotosUI

struct WatchBoxView: View {
    @Environment(AppStore.self) private var store
    @State private var adding = false
    @State private var path: [UUID] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Wordmark().padding(.top, 8)
                Text("Watch Box").font(.system(.largeTitle, design: .serif)).bold()
                Text("\(store.database.watches.count) \(store.database.watches.count == 1 ? "watch" : "watches")").foregroundStyle(.secondary)
                if store.database.watches.isEmpty {
                    ContentUnavailableView {
                        Label("A place for your watches", systemImage: "clock")
                    } description: {
                        Text("Photograph a dial. Read the frozen time. Discover how your watch runs in everyday life.")
                    } actions: { PrimaryButton(title: "Add your first watch") { beginAdding() } }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
                        ForEach(store.database.watches) { watch in
                            NavigationLink { WatchDetailView(watchID: watch.id) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    WatchCover(watch: watch).clipShape(RoundedRectangle(cornerRadius: 10))
                                    Text(watch.name).font(.headline).foregroundStyle(Theme.ink)
                                    if !watch.model.isEmpty { Text(watch.model).font(.subheadline).foregroundStyle(.secondary) }
                                    status(watch).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(20)
        }.background(Theme.ivory).toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Add watch", systemImage: "plus") { beginAdding() }.labelStyle(.iconOnly).accessibilityIdentifier("addWatch") }
        }.sheet(isPresented: $adding, onDismiss: { store.endEditing() }) { WatchForm { watch in
            adding = false
            // The detail opens immediately; cover choice is never a prerequisite.
            path = [watch.id]
        } }
        .navigationDestination(isPresented: Binding(get: { !path.isEmpty }, set: { if !$0 { path = [] } })) {
            if let id = path.first { WatchDetailView(watchID: id) }
        }
    }
    private func beginAdding() {
        guard !adding else { return }; store.beginEditing(); adding = true
    }
    @ViewBuilder private func status(_ watch: Watch) -> some View {
        let stats = WatchStatistics.calculate(database: store.database, watchID: watch.id)
        if let rate = stats.rate {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("\(RunResult.displayRate(rate)) s/day").font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Theme.ink).accessibilityIdentifier("watchBoxOverallRate")
                    if store.database.activeRun(for: watch.id) != nil { Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Theme.orange).accessibilityLabel("Active run") }
                }
                Text("\(stats.contributingReadingCount) readings · \(stats.durationText)").font(.caption2)
                if stats.early { Text("Early estimate").font(.caption2) }
                if let date = stats.lastMeasurementDate { Text("As of \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption2) }
            }
        } else if let reading = stats.latestReading, reading.timingValid {
            Text(RunResult.displayOffset(reading.offset))
            Text("\(stats.totalReadingCount) \(stats.totalReadingCount == 1 ? "reading" : "readings") · no rate yet").font(.caption2)
        } else { Label("Start a timing run", systemImage: "plus.circle") }
    }

}

struct WatchForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var watch = Watch(name: "")
    @State private var photoSelection: PhotosPickerItem?
    @State private var coverDraft: PhotoDraft?
    @State private var loadingPhoto = false
    @State private var saving = false
    @State private var error: String?
    var onSave: (Watch) -> Void = { _ in }
    private var canSave: Bool { !saving && !loadingPhoto && !watch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // This header is outside the Form, so neither form scrolling nor
                // a selected photo can move Save off screen.
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }.frame(minWidth: 60, minHeight: 44).disabled(saving)
                    Spacer(minLength: 0)
                    Text(store.database.watches.contains(where: { $0.id == watch.id }) ? "Edit watch" : "Add watch")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Button("Save", action: save).font(.headline).frame(minWidth: 52, minHeight: 44)
                        .disabled(!canSave).accessibilityIdentifier("saveWatch")
                        .accessibilityHint(watch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a name to enable Save" : "Save this watch")
                }.padding(.horizontal, 16).padding(.vertical, 8).background(Theme.ivory)
                Form {
                    Section("Watch") {
                        TextField("Name (required)", text: $watch.name).accessibilityIdentifier("watchName")
                        TextField("Brand (optional)", text: $watch.brand)
                        TextField("Model (optional)", text: $watch.model)
                    }
                    Section("Reference photo (optional)") {
                        PhotosPicker(selection: $photoSelection, matching: .images) { Label("Choose from Photos", systemImage: "photo") }
                        if loadingPhoto { ProgressView("Loading photo…") }
                        if let draft = coverDraft {
                            Image(uiImage: draft.image).resizable().scaledToFit().frame(maxHeight: 160)
                            Button("Remove selected photo") { coverDraft = nil; photoSelection = nil }
                        }
                        Text("You can position and zoom the cover from the watch’s photo editor after saving.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { Section { Text(error).foregroundStyle(Theme.orange) } }
                    Section("Notes") { TextField("Optional notes", text: $watch.notes, axis: .vertical).lineLimit(3...8) }
                    Section { Text(coverDraft == nil ? "You can take your first timing photo right away. Without a chosen cover, it becomes your Watch Box reference photo automatically." : "Your chosen cover will stay in place when you save timing readings.").font(.subheadline).foregroundStyle(.secondary) }
                }.scrollContentBackground(.hidden).background(Theme.ivory)
            }.toolbar(.hidden, for: .navigationBar)
                .task(id: photoSelection) {
                    guard let item = photoSelection else { return }
                    loadingPhoto = true
                    defer { loadingPhoto = false }
                    do {
                        guard let bytes = try await item.loadTransferable(type: Data.self) else { throw StoreError.invalid("The selected photo could not be loaded.") }
                        try Task.checkCancellation()
                        coverDraft = try PhotoDraft(bytes: bytes, source: .imported)
                    } catch is CancellationError {} catch { self.error = error.localizedDescription }
                }
        }.preferredColorScheme(.light).modifier(CloudEditingGuard())
    }
    private func save() {
        guard canSave else { return }; saving = true
        watch.name = watch.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.perform({ try $0.saveWatch(watch, cover: coverDraft?.asset(watchID: watch.id), bytes: coverDraft?.bytes, thumbnail: coverDraft?.thumbnail) }) { onSave(watch); dismiss() }
        else { saving = false; error = store.failure; store.failure = nil }
    }
}

struct WatchDetailView: View {
    @Environment(AppStore.self) private var store
    var watchID: UUID
    @State private var capturing = false
    @State private var cover = false
    @State private var editing = false
    @State private var ending = false
    private var watch: Watch? { store.database.watches.first { $0.id == watchID } }
    var body: some View {
        if let watch {
            let stats = WatchStatistics.calculate(database: store.database, watchID: watchID)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WatchCover(watch: watch).clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .bottomTrailing) {
                            Button("Change reference photo", systemImage: "camera") { beginCover() }
                                .labelStyle(.iconOnly).font(.title2).padding(12).background(Theme.orange, in: Circle()).foregroundStyle(.white).padding(12)
                        }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(watch.name).font(.largeTitle.bold())
                        if !watch.brand.isEmpty || !watch.model.isEmpty { Text([watch.brand, watch.model].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary) }
                    }
                    if watch.coverWasAutomatic && watch.coverID != nil {
                        Label("First photo set as reference. Change it whenever you like.", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).padding(12).background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    WatchStatisticsView(stats: stats)
                    if let run = store.database.activeRun(for: watchID) {
                        NavigationLink { RunDetailView(runID: run.id) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text("Current run").font(.headline); Spacer(); Image(systemName: "chevron.right") }
                                let readings = store.database.readings(in: run.id)
                                if stats.rate != nil, let rate = RunResult.calculate(readings, clockCompromised: run.clockCompromised).rate {
                                    Text("This run: \(RunResult.displayRate(rate)) s/day · \(readings.count) readings").font(.subheadline).monospacedDigit()
                                } else { RunSummary(run: run, readings: readings, compact: true) }
                            }.foregroundStyle(Theme.ink).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("currentRun")
                        PrimaryButton(title: "Add reading") { beginCapture() }
                        SecondaryButton(title: "End run") { ending = true }
                    } else {
                        if let latest = store.database.runs.filter({ $0.watchID == watchID }).sorted(by: { $0.createdAt > $1.createdAt }).first, latest.clockCompromised {
                            Label("The phone clock changed. Your readings were kept, but a new run is needed.", systemImage: "exclamationmark.triangle").font(.subheadline)
                            NavigationLink("Review saved readings") { RunDetailView(runID: latest.id) }
                        }
                        PrimaryButton(title: "Start timing run") { beginCapture() }
                        Text("No need to set or synchronize your watch first.").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    NavigationLink { RunsView(watchID: watchID) } label: { Label("Run history", systemImage: "clock.arrow.circlepath") }
                    if !watch.notes.isEmpty { Text(watch.notes).font(.body).foregroundStyle(.secondary) }
                }.padding(20)
            }.background(Theme.ivory).navigationTitle(watch.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { Menu {
                    Button("Edit watch") { beginEdit() }
                    Button("Change reference photo") { beginCover() }
                    if store.database.activeRun(for: watchID) != nil { Button("Start a new run…") { ending = true } }
                } label: { Image(systemName: "ellipsis").accessibilityLabel("Watch actions") } }
                .sheet(isPresented: $editing, onDismiss: { store.endEditing() }) { WatchForm(watch: watch) }
                .sheet(isPresented: $cover, onDismiss: { store.endEditing() }) { CoverChooser(watchID: watchID) }
                .fullScreenCover(isPresented: $capturing, onDismiss: { store.endEditing() }) { CaptureFlow(watchID: watchID, runID: store.database.activeRun(for: watchID)?.id) }
                .confirmationDialog("End the current run? Earlier readings will be preserved.", isPresented: $ending, titleVisibility: .visible) {
                    if let run = store.database.activeRun(for: watchID) {
                        Button("End run — finished") { _ = store.perform { try $0.endRun(run.id, reason: "Finished") } }
                        Button("Hands reset — start new run") { if store.perform({ try $0.endRun(run.id, reason: "Hands reset") }) { beginCapture() } }
                        Button("Watch stopped — start new run") { if store.perform({ try $0.endRun(run.id, reason: "Watch stopped") }) { beginCapture() } }
                    }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
    private func beginCapture() { guard !capturing else { return }; store.beginEditing(); capturing = true }
    private func beginEdit() { guard !editing else { return }; store.beginEditing(); editing = true }
    private func beginCover() { guard !cover else { return }; store.beginEditing(); cover = true }

}
