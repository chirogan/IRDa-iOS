import SwiftUI

@main
struct IRDaApp: App {
    @StateObject private var input = InputManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(input)
                .preferredColorScheme(.dark)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
