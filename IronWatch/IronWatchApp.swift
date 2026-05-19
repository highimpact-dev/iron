import SwiftUI

@main
struct IronWatchApp: App {
    @StateObject private var viewModel = WatchWorkoutViewModel()

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView(viewModel: viewModel)
        }
    }
}

