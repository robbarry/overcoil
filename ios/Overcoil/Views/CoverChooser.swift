import SwiftUI
import PhotosUI

private struct CoverCandidate: Identifiable {
    var id = UUID()
    var image: UIImage
    var existingID: UUID?
    var draft: PhotoDraft?
    var crop = CoverCrop()
}

struct CoverChooser: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var watchID: UUID
    @State private var selection: PhotosPickerItem?
    @State private var candidate: CoverCandidate?
    @State private var takingPhoto = false
    @State private var importing = false
    @State private var deleteID: UUID?
    @State private var error: String?
    @State private var importTask: Task<Void, Never>?
    private var watch: Watch? { store.database.watches.first { $0.id == watchID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Choose the photo shown in your Watch Box.").foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        PhotosPicker(selection: $selection, matching: .images) {
                            Label("Choose from Photos", systemImage: "photo").frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        }.disabled(importing)
                        Divider()
                        Button { takingPhoto = true } label: { Label("Take a photo", systemImage: "camera").frame(maxWidth: .infinity, alignment: .leading).padding(16) }.disabled(importing)
                        Divider()
                        Button { if let first = store.database.photos(for: watchID).first { choose(first) } } label: {
                            Label("Use first photo", systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        }.disabled(store.database.photos(for: watchID).isEmpty || importing)
                    }.background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    if importing { ProgressView("Loading photo…") }
                    Text("Photos of this watch").font(.headline)
                    if store.database.photos(for: watchID).isEmpty { Text("Saved photos will appear here.").foregroundStyle(.secondary) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) {
                        ForEach(store.database.photos(for: watchID)) { photo in
                            Button { choose(photo) } label: {
                                ZStack(alignment: .bottomLeading) {
                                    if let image = store.image(photo.id, thumbnail: true) {
                                        Image(uiImage: image).resizable().scaledToFill().frame(height: 170).clipped()
                                    }
                                    VStack(alignment: .leading) {
                                        if photo.id == store.database.photos(for: watchID).first?.id { Text("First photo").padding(5).background(.regularMaterial, in: Capsule()) }
                                        if photo.id == watch?.coverID { Text("Current").padding(5).background(Theme.orange, in: Capsule()).foregroundStyle(.white) }
                                    }.font(.caption).padding(8)
                                }.clipShape(RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel("Photo saved \(photo.savedAt.formatted()). \(photo.id == watch?.coverID ? "Current reference photo." : "")")
                                .contextMenu { Button("Delete photo…", role: .destructive) { deleteID = photo.id } }
                        }
                    }
                    Text("Changing this photo won’t change your readings.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Theme.ivory).navigationTitle("Reference photo").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { importTask?.cancel(); dismiss() } } }
        }.onChange(of: selection) { _, item in
            importTask?.cancel()
            guard let item else { return }
            importing = true
            importTask = Task { @MainActor in
                defer { if selection == item { importing = false; selection = nil } }
                do {
                    guard let bytes = try await item.loadTransferable(type: Data.self) else { throw StoreError.invalid("The selected photo could not be loaded.") }
                    try Task.checkCancellation()
                    let draft = try PhotoDraft(bytes: bytes, source: .imported)
                    candidate = CoverCandidate(image: draft.image, draft: draft)
                } catch is CancellationError {} catch { self.error = error.localizedDescription }
            }
        }.fullScreenCover(isPresented: $takingPhoto) {
            CameraView(watchName: watch?.name ?? "Watch", coverOnly: true, onClose: { takingPhoto = false }, onPhoto: {
                candidate = CoverCandidate(image: $0.image, draft: $0); takingPhoto = false
            })
        }.sheet(item: $candidate) { candidate in
            CropEditor(image: candidate.image, initialCrop: candidate.crop, watchName: watch?.name ?? "Watch") { crop in
                let success = store.perform { repo in
                    if let id = candidate.existingID { try repo.setCover(watchID: watchID, photoID: id, crop: crop) }
                    else if let draft = candidate.draft { try repo.importCover(draft.asset(watchID: watchID), bytes: draft.bytes, thumbnail: draft.thumbnail, crop: crop) }
                    else { throw StoreError.invalid("Photo is no longer available.") }
                }
                if success { self.candidate = nil; dismiss() }
                else { error = store.failure; store.failure = nil }
                return success
            }
        }.confirmationDialog("Delete this saved photo? If it is your cover, the earliest remaining photo will replace it, or a placeholder. Reading evidence must be deleted as a reading first.", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }), titleVisibility: .visible) {
            Button("Delete photo", role: .destructive) {
                if let id = deleteID, !store.perform({ try $0.deletePhoto(id) }) { error = store.failure; store.failure = nil }
                deleteID = nil
            }
            Button("Cancel", role: .cancel) { deleteID = nil }
        }.alert("Photo unchanged", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
            .onDisappear { importTask?.cancel() }
    }
    private func choose(_ photo: PhotoAsset) {
        guard let image = store.image(photo.id) else { error = "The saved photo could not be opened."; return }
        candidate = CoverCandidate(image: image, existingID: photo.id, crop: photo.id == watch?.coverID ? watch?.crop ?? CoverCrop() : CoverCrop())
    }
}

struct CropEditor: View {
    @Environment(\.dismiss) private var dismiss
    var image: UIImage
    var watchName: String
    var onSave: (CoverCrop) -> Bool
    @State private var crop: CoverCrop
    @State private var baseline: CoverCrop
    @State private var saving = false
    @State private var failed = false
    init(image: UIImage, initialCrop: CoverCrop, watchName: String, onSave: @escaping (CoverCrop) -> Bool) {
        self.image = image; self.watchName = watchName; self.onSave = onSave
        _crop = State(initialValue: initialCrop); _baseline = State(initialValue: initialCrop)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GeometryReader { geo in
                        let rect = crop.rect(in: image.size)
                        let scale = geo.size.width / rect.width
                        Image(uiImage: image).resizable().frame(width: image.size.width * scale, height: image.size.height * scale)
                            .position(x: (image.size.width / 2 - rect.minX) * scale, y: (image.size.height / 2 - rect.minY) * scale)
                            .frame(width: geo.size.width, height: geo.size.width).clipped()
                            .contentShape(Rectangle())
                            .gesture(DragGesture().onChanged { value in
                                let unit = min(image.size.width, image.size.height) * baseline.side / geo.size.width
                                crop.x = min(1, max(0, baseline.x - value.translation.width * unit / image.size.width))
                                crop.y = min(1, max(0, baseline.y - value.translation.height * unit / image.size.height))
                            }.onEnded { _ in normalize() })
                            .simultaneousGesture(MagnifyGesture().onChanged { value in crop.side = min(1, max(0.15, baseline.side / value.magnification)) }.onEnded { _ in normalize() })
                    }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("Drag to position. Pinch to zoom.").font(.caption).foregroundStyle(.secondary)
                    HStack { Image(systemName: "minus.magnifyingglass"); Slider(value: Binding(get: { 1 / crop.side }, set: { crop.side = 1 / $0; normalize() }), in: 1...6).accessibilityLabel("Reference photo zoom"); Image(systemName: "plus.magnifyingglass") }
                    DisclosureGroup("Position controls") {
                        Slider(value: $crop.x, in: 0...1).accessibilityLabel("Horizontal crop position")
                        Slider(value: $crop.y, in: 0...1).accessibilityLabel("Vertical crop position")
                    }
                    Divider()
                    Text("Watch Box preview").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Image(uiImage: crop.apply(to: image)).resizable().scaledToFit().frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 10))
                        Text(watchName).font(.headline); Spacer()
                    }.padding(10).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    if failed { Text("The photo was not saved. Your crop is still here; try again.").foregroundStyle(Theme.orange) }
                    PrimaryButton(title: saving ? "Saving…" : "Use as reference photo", action: save).disabled(saving)
                }.padding(20)
            }.background(Theme.ivory).navigationTitle("Reference photo").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(saving).accessibilityIdentifier("saveReferencePhoto") }
                }
        }.preferredColorScheme(.light)
    }
    private func save() {
        guard !saving else { return }; saving = true
        if onSave(crop) { dismiss() } else { saving = false; failed = true }
    }
    private func normalize() {
        let rect = crop.rect(in: image.size)
        crop.x = rect.midX / image.size.width; crop.y = rect.midY / image.size.height
        baseline = crop
    }
}
