import SwiftUI

@main
struct OvercoilApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(Theme.orange)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { ClockContinuity.shared.reset() }
                    else { store.becameActive() }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Group {
            if let error = store.startupError {
                ContentUnavailableView {
                    Label("Your data is protected", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Overcoil could not open its saved data. Nothing has been reset.\n\n\(error)")
                } actions: { Button("Try again") { store.load() } }
            } else {
                TabView {
                    NavigationStack { WatchBoxView() }.tabItem { Label("Watch Box", systemImage: "shippingbox") }
                    NavigationStack { RunsView() }.tabItem { Label("Runs", systemImage: "clock") }
                    NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }
                }
            }
        }.alert("Could not complete that action", isPresented: Binding(get: { store.failure != nil }, set: { if !$0 { store.failure = nil } })) {
            Button("OK") { store.failure = nil }
        } message: { Text(store.failure ?? "") }
    }
}
