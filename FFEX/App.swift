import SwiftUI

@main
struct FFEXApp: App {
    init() {
        AntiDebug.runChecks()
        AntiDebug.startPeriodicChecks()
        setupLogCapture()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var session = SessionStore()
    @StateObject private var langStore = LanguageStore.shared

    var body: some View {
        Group {
            if !session.languageSelected {
                // First install — pick language once
                LanguagePickerView()
                    .environmentObject(session)
            } else if session.licenseInfo != nil {
                // Logged in — main app
                MainMenuView()
                    .environmentObject(session)
            } else {
                // Login page
                LoginView()
                    .environmentObject(session)
            }
        }
        .preferredColorScheme(.dark)
    }
}
