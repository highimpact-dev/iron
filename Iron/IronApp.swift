import SwiftUI
import SwiftData

@main
struct IronApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            // Models will be added from spec/20260430-iron-workout-app/schema.md
        ])
    }
}
