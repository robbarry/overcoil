import SwiftUI

struct ICloudSettingsSection: View {
    @Bindable var sync: ICloudDriveSync
    @State private var confirmLocal = false
    @State private var selectedCloud: CloudVersionChoice?
    @State private var confirmAccount = false
    var body: some View {
        Section("iCloud Drive") {
            Toggle("Sync Watch Box with iCloud", isOn: Binding(get: { sync.isEnabled }, set: { sync.setEnabled($0) }))
            if sync.isWorking { ProgressView("Syncing…") }
            Text(sync.status).font(.subheadline)
            if let date = sync.lastUploaded { LabeledContent("Last verified upload", value: date.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
            Button("Sync now") { sync.syncNow() }.disabled(!sync.isEnabled || sync.isWorking)
            Button("Verify restore without changing my library") { sync.verifyRestore() }.disabled(!sync.isEnabled || sync.isWorking)
            if sync.accountChanged {
                Button("Use the current iCloud account…") { confirmAccount = true }
            }
            if sync.hasConflict {
                Button("Keep this device’s library…") { confirmLocal = true }.disabled(sync.isWorking)
                ForEach(sync.conflictChoices) { choice in
                    Button("Use iCloud copy: \(choice.watchCount) watches, \(choice.readingCount) readings · \(choice.date.formatted(date: .abbreviated, time: .shortened))…") { selectedCloud = choice }.disabled(sync.isWorking)
                }
            }
            Text("Finder → iCloud Drive → Overcoil. The same iCloud account and iCloud Drive must be enabled on each device. New installations can restore the complete library and photos; offline changes are kept locally.").font(.caption).foregroundStyle(.secondary)
            Text("The shared JSON and photo files are app-managed. Copy them elsewhere before editing. Recovery versions and original photos are retained so conflicts do not silently erase your history.").font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Use this device’s library as the shared iCloud library? Existing cloud versions and photos will be backed up before replacement.", isPresented: $confirmLocal, titleVisibility: .visible) {
            Button("Keep this device’s library") { sync.keepThisDevice() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Use this iCloud library on this device? The current local library will be retained in a recovery copy before replacement.", isPresented: Binding(get: { selectedCloud != nil }, set: { if !$0 { selectedCloud = nil } }), titleVisibility: .visible) {
            if let choice = selectedCloud { Button("Use selected iCloud copy") { sync.useCloud(choice.id); selectedCloud = nil } }
            Button("Cancel", role: .cancel) { selectedCloud = nil }
        }
        .confirmationDialog("Allow this local Watch Box and its photos to sync with the iCloud account currently signed in on this device?", isPresented: $confirmAccount, titleVisibility: .visible) {
            Button("Use current iCloud account") { sync.confirmCurrentAccount() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
