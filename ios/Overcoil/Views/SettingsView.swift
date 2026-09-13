import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section {
                Wordmark().padding(.vertical, 8)
                Text("Your watch, your photo.").font(.system(.title2, design: .serif))
                Text("Overcoil measures how a watch's offset from your iPhone changes during ordinary use.")
            }
            Section("Reference clock") {
                Text("Results are relative to the iPhone system clock. Enable Automatic Date & Time in iPhone Settings when possible. Overcoil does not certify synchronization or claim atomic-clock accuracy.")
                Text("Capture timestamps are mapped from the camera clock to host time and the phone wall clock. Physical capture alignment has not yet been validated. Treat this testing build's results as estimates.")
                Text("Clock-discontinuity checks operate only within a continuous foreground session. Suspension, relaunch, reboot, and smaller corrections limit detection. Not every clock change can be detected.")
            }
            Section("Reading your watch") {
                Text("Use the normal running seconds hand or small seconds subdial, not a stopped chronograph hand. Retake if the seconds cannot be read.")
                Text("You do not need to synchronize your watch before starting. Winding a running watch without moving its hands does not require a new run.")
                Text("If the hands are reset, including for travel or daylight saving time, or the watch stops, end the run and start a new one. A phone time-zone change alone does not change the watch's fixed time basis.")
            }
            Section("Measurement quality") {
                Text("Longer intervals reduce the effect of reading error. Runs shorter than 24 hours are labeled Early estimate; add another reading the next day.")
                Text("For illustration only: if each endpoint were uncertain by up to one second, their difference could be uncertain by up to two seconds—about 2 seconds/day across 24 hours, or 48 seconds/day across one hour. This is sensitivity, not a validated app error bound.")
                Text("A rounded 0.0 seconds/day does not establish perfect accuracy.")
            }
            Section("Privacy & storage") {
                Text("Your watches, photos, and readings stay in app-owned storage on this iPhone. Overcoil does not upload them, use an account, or request microphone, location, or full photo-library access. Your device's normal backup settings may include app data.")
                Text("Photos imports are for reference photos only. Timing readings require in-app capture. Deleting the app can delete its local data.")
            }
            Section("Build") {
                LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                if let revision = Bundle.main.object(forInfoDictionaryKey: "OvercoilSourceRevision") as? String { LabeledContent("Source", value: revision).font(.caption.monospaced()) }
                Text("Native iPhone · Local-first · Testing build").font(.caption)
            }
        }.scrollContentBackground(.hidden).background(Theme.ivory).navigationTitle("Settings")
    }
}
