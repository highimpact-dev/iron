import SwiftUI
import SwiftData
import UIKit

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(GeminiNutritionPreferenceKeys.apiKey) private var geminiAPIKey = ""
    @State private var selectedTab: RootTab = .today
    @State private var pendingFitProfileReport: FitProfileReport?
    @State private var fitProfileImportError: String?
    @State private var isImportingFitProfileReport = false

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "heart.text.square")
                }
                .tag(RootTab.today)

            TrainView()
                .tabItem {
                    Label("Train", systemImage: "dumbbell.fill")
                }
                .tag(RootTab.train)

            IntervalTimerView()
                .tabItem {
                    Label("Timer", systemImage: "timer")
                }
                .tag(RootTab.timer)

            NutritionView()
                .tabItem {
                    Label("Nutrition", systemImage: "fork.knife")
                }
                .tag(RootTab.nutrition)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }
                .tag(RootTab.history)

            BodyView()
                .tabItem {
                    Label("Body", systemImage: "figure.stand")
                }
                .tag(RootTab.body)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(RootTab.settings)
        }
        .onOpenURL { url in
            handleURL(url)
        }
        .sheet(item: $pendingFitProfileReport) { report in
            FitProfileImportReview(report: report) {
                apply(report)
                pendingFitProfileReport = nil
            }
        }
        .sheet(isPresented: $isImportingFitProfileReport) {
            VStack(spacing: 16) {
                ProgressView()
                Text("Reading FitProfile with Gemini...")
                    .font(.headline)
                Text("Iron is extracting the report values from the shared image.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .presentationDetents([.height(180)])
        }
        .alert("FitProfile Import", isPresented: isFitProfileImportErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fitProfileImportError ?? "")
        }
    }

    private var isFitProfileImportErrorPresented: Binding<Bool> {
        Binding(
            get: { fitProfileImportError != nil },
            set: { isPresented in
                if !isPresented {
                    fitProfileImportError = nil
                }
            }
        )
    }

    private func apply(_ report: FitProfileReport) {
        let suggestion = report.suggestedNutrition
        upsertNutritionTarget(report: report, suggestion: suggestion)
        upsertBodyMetric(report)
        try? modelContext.save()
    }

    private func handleURL(_ url: URL) {
        if let report = FitProfileReport(url: url) {
            presentFitProfileImport(report)
            return
        }

        guard url.scheme == "iron", url.host == "fitprofile-import" else {
            return
        }

        selectedTab = .nutrition

        if let data = UIPasteboard.general.data(forPasteboardType: FitProfileReport.pasteboardType),
           let report = try? JSONDecoder().decode(FitProfileReport.self, from: data) {
            UIPasteboard.general.setData(Data(), forPasteboardType: FitProfileReport.pasteboardType)
            presentFitProfileImport(report)
            return
        }

        guard let data = UIPasteboard.general.data(forPasteboardType: FitProfileReport.mediaPasteboardType),
              let media = try? JSONDecoder().decode(FitProfileImportMedia.self, from: data) else {
            fitProfileImportError = "Iron opened, but the shared FitProfile data was not available. Try sharing the report again."
            return
        }

        UIPasteboard.general.setData(Data(), forPasteboardType: FitProfileReport.mediaPasteboardType)
        importFitProfileMedia(media)
    }

    private func importFitProfileMedia(_ media: FitProfileImportMedia) {
        isImportingFitProfileReport = true
        Task {
            do {
                let report = try await GeminiFitProfileService.shared.parse(
                    media: media,
                    apiKey: geminiAPIKey
                )
                isImportingFitProfileReport = false
                pendingFitProfileReport = report
            } catch {
                isImportingFitProfileReport = false
                fitProfileImportError = error.localizedDescription
            }
        }
    }

    private func presentFitProfileImport(_ report: FitProfileReport) {
        selectedTab = .nutrition
        pendingFitProfileReport = report
    }

    private func upsertNutritionTarget(
        report: FitProfileReport,
        suggestion: FitProfileNutritionSuggestion
    ) {
        // If the report has no date, we can’t anchor a daily target.
        guard let measuredAt = report.measuredAt else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: measuredAt)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? measuredAt

        let descriptor = FetchDescriptor<NutritionTarget>(
            predicate: #Predicate<NutritionTarget> { target in
                target.deletedAt == nil &&
                target.effectiveDate >= dayStart &&
                target.effectiveDate < dayEnd
            }
        )

        let existing = try? modelContext.fetch(descriptor).first
        let target = existing ?? NutritionTarget(effectiveDate: dayStart)

        target.effectiveDate = dayStart
        target.goal = NutritionGoal(fitProfileGoal: suggestion.goal)
        target.calories = suggestion.calories
        target.proteinG = suggestion.proteinG
        target.carbsG = suggestion.carbsG
        target.fatG = suggestion.fatG
        target.notes = "FitProfile import: BMR \(formatOptional(report.bmrKcal, suffix: " kcal")), weight control \(formatOptional(report.weightControlLb, suffix: " lb"))"


        if existing == nil {
            modelContext.insert(target)
        }
    }

    private func upsertBodyMetric(_ report: FitProfileReport) {
        // Need a date and at least one metric to log.
        guard let measuredAt = report.measuredAt else { return }
        guard report.weightLb != nil || report.bodyFatPercent != nil else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: measuredAt)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? measuredAt

        let descriptor = FetchDescriptor<BodyMetric>(
            predicate: #Predicate<BodyMetric> { metric in
                metric.deletedAt == nil &&
                metric.loggedAt >= dayStart &&
                metric.loggedAt < dayEnd
            }
        )

        let existing = try? modelContext.fetch(descriptor).first
        let metric = existing ?? BodyMetric(loggedAt: measuredAt)

        metric.loggedAt = measuredAt
        metric.bodyweightLb = report.weightLb
        metric.bodyFatPercent = report.bodyFatPercent.map { $0 / 100 }
        metric.notes = "FitProfile import"

        if existing == nil {
            modelContext.insert(metric)
        }
    }
}

private enum RootTab: Hashable {
    case today
    case train
    case timer
    case nutrition
    case history
    case body
    case settings
}

private struct FitProfileImportReview: View {
    let report: FitProfileReport
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var suggestion: FitProfileNutritionSuggestion {
        report.suggestedNutrition
    }

    var body: some View {
        let dateText = report.measuredAt.map {
            $0.formatted(date: .abbreviated, time: .shortened)
        } ?? "No date"

        NavigationStack {
            List {
                Section("Report") {
                    LabeledContent("Date", value: dateText)

                    if let weight = report.weightLb {
                        LabeledContent("Weight", value: "\(formatFitProfileNumber(weight)) lb")
                    }
                    if let bodyFat = report.bodyFatPercent {
                        LabeledContent("Body fat", value: "\(formatFitProfileNumber(bodyFat))%")
                    }
                    if let bmr = report.bmrKcal {
                        LabeledContent("BMR", value: "\(formatFitProfileNumber(bmr)) kcal")
                    }
                    if let control = report.weightControlLb {
                        LabeledContent("Weight control", value: "\(formatFitProfileNumber(control)) lb")
                    }
                }

                Section {
                    LabeledContent(
                        "Goal",
                        value: NutritionGoal(fitProfileGoal: suggestion.goal).label
                    )
                    LabeledContent(
                        "Calories",
                        value: "\(formatFitProfileNumber(suggestion.calories)) kcal"
                    )
                    LabeledContent(
                        "Macros",
                        value: "\(formatFitProfileNumber(suggestion.proteinG))P / \(formatFitProfileNumber(suggestion.carbsG))C / \(formatFitProfileNumber(suggestion.fatG))F"
                    )
                }
            }
            .navigationTitle("FitProfile Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private extension NutritionGoal {
    init(fitProfileGoal: FitProfileGoal) {
        switch fitProfileGoal {
        case .fatLoss:
            self = .fatLoss
        case .maintenance:
            self = .maintenance
        case .muscleGain:
            self = .muscleGain
        }
    }
}

private func formatOptional(_ value: Double?, suffix: String) -> String {
    guard let value else { return "unknown" }
    return "\(formatFitProfileNumber(value))\(suffix)"
}

private func formatFitProfileNumber(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
}

#Preview {
    RootTabView()
}
