import SwiftData
import SwiftUI

@main
struct JarvisApp: App {
    init() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.voiceEnabled: true,
            SettingsKey.voiceAccent: "en-GB",
            SettingsKey.reminderLead: 10,
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: Plan.self)
    }
}
