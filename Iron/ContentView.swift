import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Iron")
                    .font(.largeTitle.bold())
                Text("Hybrid lifting + conditioning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Iron")
        }
    }
}

#Preview {
    ContentView()
}
