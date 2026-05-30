import SwiftUI

struct SettingsView: View {
    @AppStorage(HealthKitPreferenceKeys.writeWorkouts) private var writeWorkouts = false
    @AppStorage(HealthKitPreferenceKeys.readBodyMetrics) private var readBodyMetrics = false
    @AppStorage(HealthKitPreferenceKeys.writeBodyMetrics) private var writeBodyMetrics = false
    @AppStorage(HealthKitPreferenceKeys.readNutrition) private var readNutrition = false
    @AppStorage(HealthKitPreferenceKeys.writeNutrition) private var writeNutrition = false
    @AppStorage(HealthKitPreferenceKeys.readDailyHealth) private var readDailyHealth = false
    @AppStorage(USDAFoodDataPreferenceKeys.apiKey) private var usdaAPIKey = ""
    @AppStorage(GeminiNutritionPreferenceKeys.apiKey) private var geminiAPIKey = ""

    @State private var healthStatus = HealthKitService.shared.authorizationSummary()
    @State private var isRequestingHealthAccess = false
    @State private var healthError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Status", value: healthStatus)

                    Toggle("Write completed workouts", isOn: $writeWorkouts)
                        .disabled(!HealthKitService.isAvailable || isRequestingHealthAccess)
                    Toggle("Read body metrics", isOn: $readBodyMetrics)
                        .disabled(!HealthKitService.isAvailable || isRequestingHealthAccess)
                    Toggle("Write body metrics", isOn: $writeBodyMetrics)
                        .disabled(!HealthKitService.isAvailable || isRequestingHealthAccess)
                    Toggle("Read nutrition", isOn: $readNutrition)
                        .disabled(!HealthKitService.isAvailable || isRequestingHealthAccess)
                    Toggle("Write nutrition", isOn: $writeNutrition)
                        .disabled(!HealthKitService.isAvailable || isRequestingHealthAccess)
                    Toggle("Read daily health", isOn: $readDailyHealth)
                        .disabled(!HealthKitService.isAvailable || isRequestingHealthAccess)

                    Button {
                        Task { await requestHealthAccess() }
                    } label: {
                        Label(
                            isRequestingHealthAccess ? "Requesting access..." : "Request Health access",
                            systemImage: "heart.fill"
                        )
                    }
                    .disabled(!HealthKitService.isAvailable || isRequestingHealthAccess || noHealthTypesEnabled)
                } header: {
                    Text("HealthKit")
                } footer: {
                    Text("Iron writes workout summaries to Health and can read Apple Health and Watch data for the Today dashboard. Detailed set, rep, RPE, RIR, and bodybuilding measurements remain in Iron because Health does not have first-class fields for them.")
                }

                Section("Food Databases") {
                    SecureField("USDA API key", text: $usdaAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("USDA FoodData Central powers richer generic food and micronutrient lookup. Open Food Facts remains available for packaged food barcode fallback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("AI Voice Logging") {
                    SecureField("Gemini API key", text: $geminiAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Prototype-only local key for spoken meal logging. Production should move Gemini calls server-side or use short-lived Live API tokens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: "0.1.0")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: writeWorkouts) { _, enabled in
                if enabled { Task { await requestHealthAccess() } }
            }
            .onChange(of: readBodyMetrics) { _, enabled in
                if enabled { Task { await requestHealthAccess() } }
            }
            .onChange(of: writeBodyMetrics) { _, enabled in
                if enabled { Task { await requestHealthAccess() } }
            }
            .onChange(of: readNutrition) { _, enabled in
                if enabled { Task { await requestHealthAccess() } }
            }
            .onChange(of: writeNutrition) { _, enabled in
                if enabled { Task { await requestHealthAccess() } }
            }
            .onChange(of: readDailyHealth) { _, enabled in
                if enabled { Task { await requestHealthAccess() } }
            }
            .alert(
                "HealthKit access failed",
                isPresented: Binding(
                    get: { healthError != nil },
                    set: { if !$0 { healthError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    healthError = nil
                }
            } message: {
                Text(healthError ?? "")
            }
        }
    }

    private var noHealthTypesEnabled: Bool {
        !writeWorkouts && !readBodyMetrics && !writeBodyMetrics && !readNutrition && !writeNutrition && !readDailyHealth
    }

    private func requestHealthAccess() async {
        guard HealthKitService.isAvailable else {
            healthError = "Health data is not available on this device."
            healthStatus = HealthKitService.shared.authorizationSummary()
            return
        }
        guard !noHealthTypesEnabled else {
            healthStatus = HealthKitService.shared.authorizationSummary()
            return
        }

        isRequestingHealthAccess = true
        defer {
            isRequestingHealthAccess = false
            healthStatus = HealthKitService.shared.authorizationSummary()
        }

        do {
            try await HealthKitService.shared.requestAuthorization(
                readBodyMetrics: readBodyMetrics,
                writeBodyMetrics: writeBodyMetrics,
                writeWorkouts: writeWorkouts,
                readNutrition: readNutrition,
                writeNutrition: writeNutrition,
                readDailyHealth: readDailyHealth
            )
        } catch {
            healthError = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
}
