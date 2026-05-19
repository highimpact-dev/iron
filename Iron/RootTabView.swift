import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TrainView()
                .tabItem {
                    Label("Train", systemImage: "dumbbell.fill")
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }
            NutritionView()
                .tabItem {
                    Label("Nutrition", systemImage: "fork.knife")
                }
            BodyView()
                .tabItem {
                    Label("Body", systemImage: "figure.stand")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    RootTabView()
}
