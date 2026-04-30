import SwiftUI

struct TrainView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No active workout",
                systemImage: "dumbbell.fill",
                description: Text("Start a session to begin logging sets.")
            )
            .navigationTitle("Train")
        }
    }
}

#Preview {
    TrainView()
}
