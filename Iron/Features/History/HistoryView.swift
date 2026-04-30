import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No workouts yet",
                systemImage: "calendar",
                description: Text("Logged sessions will appear here.")
            )
            .navigationTitle("History")
        }
    }
}

#Preview {
    HistoryView()
}
