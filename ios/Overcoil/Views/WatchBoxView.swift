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
                    } actions: { PrimaryButton(title: "Add your first watch") { adding = true } }
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
            ToolbarItem(placement: .topBarTrailing) { Button("Add watch", systemImage: "plus") { adding = true }.labelStyle(.iconOnly).accessibilityIdentifier("addWatch") }
        }.sheet(isPresented: $adding) { WatchForm { watch in
            adding = false
            // The detail opens immediately; cover choice is never a prerequisite.
            path = [watch.id]
        } }
        .navigationDestination(isPresented: Binding(get: { !path.isEmpty }, set: { if !$0 { path = [] } })) {
            if let id = path.first { WatchDetailView(watchID: id) }
        }
    }
    @ViewBuilder private func status(_ watch: Watch) -> some View {
        if store.database.activeRun(for: watch.id) != nil {
            Label("Run in progress", systemImage: "circle.fill").foregroundStyle(Theme.orange)
        } else if let run = store.database.runs.filter({ $0.watchID == watch.id }).sorted(by: { $0.createdAt > $1.createdAt }).first,
                  let last = store.database.readings(in: run.id).last,
                  let rate = RunResult.calculate(store.database.readings(in: run.id), clockCompromised: run.clockCompromised).rate {
            Text("Last \(RunResult.displayRate(rate)) s/day · \(last.reference.formatted(date: .abbreviated, time: .omitted))")
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
    var body: some View {
        NavigationStack {
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
            }.navigationTitle(store.database.watches.contains(where: { $0.id == watch.id }) ? "Edit watch" : "Add watch")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard !saving else { return }; saving = true
                            watch.name = watch.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            if store.perform({ try $0.saveWatch(watch, cover: coverDraft?.asset(watchID: watch.id), bytes: coverDraft?.bytes, thumbnail: coverDraft?.thumbnail) }) { onSave(watch); dismiss() }
                            else { saving = false; error = store.failure; store.failure = nil }
                        }.disabled(saving || loadingPhoto || watch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveWatch")
                    }
                }
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
        }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WatchCover(watch: watch).clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .bottomTrailing) {
                            Button("Change reference photo", systemImage: "camera") { cover = true }
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
                    if let run = store.database.activeRun(for: watchID) {
                        NavigationLink { RunDetailView(runID: run.id) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text("Current run").font(.headline); Spacer(); Image(systemName: "chevron.right") }
                                RunSummary(run: run, readings: store.database.readings(in: run.id), compact: true)
                            }.foregroundStyle(Theme.ink).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("currentRun")
                        PrimaryButton(title: "Add reading") { capturing = true }
                        Button("End run") { ending = true }.frame(maxWidth: .infinity)
                    } else {
                        if let latest = store.database.runs.filter({ $0.watchID == watchID }).sorted(by: { $0.createdAt > $1.createdAt }).first, latest.clockCompromised {
                            Label("The phone clock changed. Your readings were kept, but a new run is needed.", systemImage: "exclamationmark.triangle").font(.subheadline)
                            NavigationLink("Review saved readings") { RunDetailView(runID: latest.id) }
                        }
                        PrimaryButton(title: "Start timing run") { capturing = true }
                        Text("No need to set or synchronize your watch first.").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    NavigationLink { RunsView(watchID: watchID) } label: { Label("Run history", systemImage: "clock.arrow.circlepath") }
                    if !watch.notes.isEmpty { Text(watch.notes).font(.body).foregroundStyle(.secondary) }
                }.padding(20)
            }.background(Theme.ivory).navigationTitle(watch.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { Menu {
                    Button("Edit watch") { editing = true }
                    Button("Change reference photo") { cover = true }
                    if store.database.activeRun(for: watchID) != nil { Button("Start a new run…") { ending = true } }
                } label: { Image(systemName: "ellipsis").accessibilityLabel("Watch actions") } }
                .sheet(isPresented: $editing) { WatchForm(watch: watch) }
                .sheet(isPresented: $cover) { CoverChooser(watchID: watchID) }
                .fullScreenCover(isPresented: $capturing) { CaptureFlow(watchID: watchID, runID: store.database.activeRun(for: watchID)?.id) }
                .confirmationDialog("End the current run? Earlier readings will be preserved.", isPresented: $ending, titleVisibility: .visible) {
                    if let run = store.database.activeRun(for: watchID) {
                        Button("End run — finished") { _ = store.perform { try $0.endRun(run.id, reason: "Finished") } }
                        Button("Hands reset — start new run") { if store.perform({ try $0.endRun(run.id, reason: "Hands reset") }) { capturing = true } }
                        Button("Watch stopped — start new run") { if store.perform({ try $0.endRun(run.id, reason: "Watch stopped") }) { capturing = true } }
                    }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
}
