import SwiftUI

// Signing/build smoke-test shell only; product implementation awaits the brief.
@main
struct OvercoilApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Text("Overcoil")
                    .font(.largeTitle)
                Text("Development setup")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
