import SwiftUI
import SwiftData

@main
struct IronApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema(IronSchemaV3.models)
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            self.modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: IronMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    SeedService.seedIfNeeded(context: modelContainer.mainContext)
                    WatchConnectivityService.shared.configure(modelContext: modelContainer.mainContext)
                    await RestNotificationService.requestAuthorizationIfNeeded()
                }
        }
        .modelContainer(modelContainer)
    }
}
