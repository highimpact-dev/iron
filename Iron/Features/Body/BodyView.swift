import SwiftUI

struct BodyView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No body metrics",
                systemImage: "figure.stand",
                description: Text("Weight, measurements, and PRs will appear here.")
            )
            .navigationTitle("Body")
        }
    }
}

#Preview {
    BodyView()
}
