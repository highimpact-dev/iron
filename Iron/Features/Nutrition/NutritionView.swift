import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(VisionKit)
import VisionKit
#endif

struct NutritionView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HealthKitPreferenceKeys.readNutrition) private var readHealthNutrition = false
    @AppStorage(HealthKitPreferenceKeys.writeNutrition) private var writeHealthNutrition = false
    @AppStorage(GeminiNutritionPreferenceKeys.apiKey) private var geminiAPIKey = ""

    @Query(
        filter: #Predicate<NutritionEntry> { $0.deletedAt == nil },
        sort: \NutritionEntry.loggedAt,
        order: .reverse
    )
    private var entries: [NutritionEntry]

    @Query(
        filter: #Predicate<NutritionTarget> { $0.deletedAt == nil },
        sort: \NutritionTarget.effectiveDate,
        order: .reverse
    )
    private var targets: [NutritionTarget]

    @Query(
        filter: #Predicate<BodyMetric> { $0.deletedAt == nil && $0.bodyweightLb != nil },
        sort: \BodyMetric.loggedAt,
        order: .reverse
    )
    private var bodyMetrics: [BodyMetric]

    @State private var selectedDate = Date()
    @State private var activeSheet: NutritionSheet?
    @State private var pendingDelete: NutritionEntry?
    @State private var isImportingHealthNutrition = false
    @State private var healthNutritionMessage: String?
    @State private var healthNutritionError: String?
    @StateObject private var mealRecorder = MealAudioRecorder()
    @State private var isAnalyzingVoiceMeal = false
    @State private var recordingStartedAt: Date?
    @State private var voiceMealMessage: String?
    @State private var voiceMealError: String?

    private enum NutritionSheet: Identifiable {
        case addFood
        case editFood(NutritionEntry)
        case editTargets
        case voiceDraft(MealDraft)

        var id: String {
            switch self {
            case .addFood: return "add-food"
            case .editFood(let entry): return "edit-food-\(entry.id)"
            case .editTargets: return "edit-targets"
            case .voiceDraft(let draft): return "voice-draft-\(draft.id)"
            }
        }
    }

    private var selectedEntries: [NutritionEntry] {
        entries
            .filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    private var currentTarget: NutritionTarget {
        target(for: selectedDate) ?? defaultTarget
    }

    private var dailyTotals: NutritionTotals {
        NutritionTotals(entries: selectedEntries)
    }

    private var weeklyAverage: NutritionTotals {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: selectedDate) ?? selectedDate
        let rangeEntries = entries.filter {
            $0.loggedAt >= Calendar.current.startOfDay(for: start)
                && $0.loggedAt < Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: selectedDate))!
        }
        return NutritionTotals(
            calories: rangeEntries.reduce(0) { $0 + $1.calories } / 7,
            proteinG: rangeEntries.reduce(0) { $0 + $1.proteinG } / 7,
            carbsG: rangeEntries.reduce(0) { $0 + $1.carbsG } / 7,
            fatG: rangeEntries.reduce(0) { $0 + $1.fatG } / 7,
            fiberG: rangeEntries.reduce(0) { $0 + ($1.fiberG ?? 0) } / 7,
            sugarG: rangeEntries.reduce(0) { $0 + ($1.sugarG ?? 0) } / 7,
            sodiumMg: rangeEntries.reduce(0) { $0 + ($1.sodiumMg ?? 0) } / 7,
            potassiumMg: rangeEntries.reduce(0) { $0 + ($1.potassiumMg ?? 0) } / 7,
            calciumMg: rangeEntries.reduce(0) { $0 + ($1.calciumMg ?? 0) } / 7,
            ironMg: rangeEntries.reduce(0) { $0 + ($1.ironMg ?? 0) } / 7,
            vitaminDMcg: rangeEntries.reduce(0) { $0 + ($1.vitaminDMcg ?? 0) } / 7,
            cholesterolMg: rangeEntries.reduce(0) { $0 + ($1.cholesterolMg ?? 0) } / 7
        )
    }

    private var expenditureEstimate: ExpenditureEstimate? {
        estimateExpenditure()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DateNavigator(date: $selectedDate)
                    NutritionSummaryCard(
                        totals: dailyTotals,
                        target: currentTarget
                    )
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                Section("Health") {
                    if HealthKitService.isAvailable {
                        Button {
                            Task { await importHealthNutrition() }
                        } label: {
                            Label(
                                isImportingHealthNutrition ? "Importing nutrition..." : "Import Health nutrition",
                                systemImage: "heart.fill"
                            )
                        }
                        .disabled(isImportingHealthNutrition || !readHealthNutrition)

                        if let healthNutritionMessage {
                            Text(healthNutritionMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !readHealthNutrition {
                            Text("Turn on Health nutrition reading in Settings to import calories and macros.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Health is unavailable on this device.", systemImage: "heart.slash")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Voice") {
                    if mealRecorder.isRecording {
                        VoiceMealStatusView(status: .recording(startedAt: recordingStartedAt ?? Date()))
                            .listRowBackground(Color.red.opacity(0.08))
                    } else if isAnalyzingVoiceMeal {
                        VoiceMealStatusView(status: .analyzing)
                            .listRowBackground(Color.blue.opacity(0.08))
                    }

                    Button {
                        Task { await toggleVoiceMealRecording() }
                    } label: {
                        Label(
                            voiceMealButtonTitle,
                            systemImage: mealRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                        )
                    }
                    .disabled(isAnalyzingVoiceMeal || (!mealRecorder.isRecording && geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                    if isAnalyzingVoiceMeal {
                        ProgressView("Analyzing meal...")
                    }

                    if let voiceMealMessage {
                        Text(voiceMealMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add a Gemini API key in Settings to try spoken meal logging.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let voiceMealError {
                        Text(voiceMealError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Food Log") {
                    if selectedEntries.isEmpty {
                        ContentUnavailableView(
                            "No food logged",
                            systemImage: "fork.knife",
                            description: Text("Add foods to track calories and macros for this day.")
                        )
                    } else {
                        ForEach(groupedMeals) { meal in
                            MealGroupView(
                                meal: meal,
                                onEdit: { entry in activeSheet = .editFood(entry) },
                                onDelete: deleteEntry
                            )
                        }
                    }

                    Button {
                        activeSheet = .addFood
                    } label: {
                        Label("Add food", systemImage: "plus.circle.fill")
                    }
                }

                Section("Targets") {
                    LabeledContent("Goal", value: currentTarget.goal.label)
                    LabeledContent("Calories", value: "\(formatNumber(currentTarget.calories)) kcal")
                    LabeledContent(
                        "Macros",
                        value: "\(formatNumber(currentTarget.proteinG))P / \(formatNumber(currentTarget.carbsG))C / \(formatNumber(currentTarget.fatG))F"
                    )
                    Button {
                        activeSheet = .editTargets
                    } label: {
                        Label("Edit targets", systemImage: "slider.horizontal.3")
                    }
                }

                Section("Macros") {
                    MacroProgressRow(
                        title: "Calories",
                        value: dailyTotals.calories,
                        target: currentTarget.calories,
                        suffix: "kcal",
                        tint: .orange
                    )
                    MacroProgressRow(
                        title: "Protein",
                        value: dailyTotals.proteinG,
                        target: currentTarget.proteinG,
                        suffix: "g",
                        tint: .red
                    )
                    MacroProgressRow(
                        title: "Carbs",
                        value: dailyTotals.carbsG,
                        target: currentTarget.carbsG,
                        suffix: "g",
                        tint: .blue
                    )
                    LabeledContent("Net Carbs", value: "\(formatNumber(dailyTotals.netCarbsG)) g")
                    LabeledContent("Fiber", value: "\(formatNumber(dailyTotals.fiberG)) g")
                    MacroProgressRow(
                        title: "Fat",
                        value: dailyTotals.fatG,
                        target: currentTarget.fatG,
                        suffix: "g",
                        tint: .yellow
                    )
                }

                Section("Micronutrients") {
                    NutrientRow(title: "Sugar", value: dailyTotals.sugarG, suffix: "g")
                    NutrientRow(title: "Sodium", value: dailyTotals.sodiumMg, suffix: "mg")
                    NutrientRow(title: "Potassium", value: dailyTotals.potassiumMg, suffix: "mg")
                    NutrientRow(title: "Calcium", value: dailyTotals.calciumMg, suffix: "mg")
                    NutrientRow(title: "Iron", value: dailyTotals.ironMg, suffix: "mg")
                    NutrientRow(title: "Vitamin D", value: dailyTotals.vitaminDMcg, suffix: "mcg")
                    NutrientRow(title: "Cholesterol", value: dailyTotals.cholesterolMg, suffix: "mg")
                }

                DetailedNutrientPanel(totals: DetailedNutrientTotals(entries: selectedEntries))

                Section("Coach") {
                    EnergyInsightView(
                        weeklyAverage: weeklyAverage,
                        target: currentTarget,
                        estimate: expenditureEstimate
                    )
                }
            }
            .navigationTitle("Nutrition")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .editTargets
                    } label: {
                        Image(systemName: "target")
                    }
                    Button {
                        Task { await toggleVoiceMealRecording() }
                    } label: {
                        Image(systemName: mealRecorder.isRecording ? "stop.circle.fill" : "mic")
                    }
                    .disabled(isAnalyzingVoiceMeal || (!mealRecorder.isRecording && geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    Button {
                        activeSheet = .addFood
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addFood:
                    FoodEntryEditor(initialDate: selectedDate, editingEntry: nil) { entry in
                        modelContext.insert(entry)
                        try? modelContext.save()
                        if writeHealthNutrition {
                            let snapshot = HealthNutritionSnapshot(entry: entry)
                            Task {
                                try? await HealthKitService.shared.saveNutrition(snapshot)
                            }
                        }
                        activeSheet = nil
                    }
                case .editFood(let existing):
                    FoodEntryEditor(initialDate: selectedDate, editingEntry: existing) { edited in
                        update(existing, with: edited)
                        try? modelContext.save()
                        activeSheet = nil
                    }
                case .editTargets:
                    NutritionTargetEditor(target: currentTarget) { target in
                        saveTarget(target)
                        activeSheet = nil
                    }
                case .voiceDraft(let draft):
                    VoiceMealDraftReview(draft: draft, loggedAt: selectedDate) { entries in
                        saveVoiceEntries(entries)
                        activeSheet = nil
                    }
                }
            }
            .onAppear {
                seedDefaultTargetIfNeeded()
            }
            .alert(
                "Health nutrition import failed",
                isPresented: Binding(
                    get: { healthNutritionError != nil },
                    set: { if !$0 { healthNutritionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    healthNutritionError = nil
                }
            } message: {
                Text(healthNutritionError ?? "")
            }
        }
    }

    private var voiceMealButtonTitle: String {
        if mealRecorder.isRecording { return "Stop recording" }
        if isAnalyzingVoiceMeal { return "Analyzing meal..." }
        return "Speak meal"
    }

    private var defaultTarget: NutritionTarget {
        NutritionTarget(
            effectiveDate: selectedDate,
            goal: .maintenance,
            calories: 2400,
            proteinG: 180,
            carbsG: 250,
            fatG: 70
        )
    }

    private var groupedMeals: [MealGroup] {
        let grouped = Dictionary(grouping: selectedEntries) { $0.mealName }
        return grouped
            .map { meal, entries in
                MealGroup(
                    name: meal,
                    entries: entries.sorted { $0.loggedAt < $1.loggedAt }
                )
            }
            .sorted { lhs, rhs in
                mealSortIndex(lhs.name) < mealSortIndex(rhs.name)
            }
    }

    private func target(for date: Date) -> NutritionTarget? {
        targets.first { target in
            Calendar.current.startOfDay(for: target.effectiveDate) <= Calendar.current.startOfDay(for: date)
        } ?? targets.last
    }

    private func seedDefaultTargetIfNeeded() {
        guard targets.isEmpty else { return }
        modelContext.insert(defaultTarget)
        try? modelContext.save()
    }

    private func deleteEntry(_ entry: NutritionEntry) {
        entry.deletedAt = Date()
        try? modelContext.save()
    }

    private func saveTarget(_ target: NutritionTarget) {
        if let existing = targets.first(where: { $0.id == target.id }) {
            existing.effectiveDate = target.effectiveDate
            existing.goal = target.goal
            existing.calories = target.calories
            existing.proteinG = target.proteinG
            existing.carbsG = target.carbsG
            existing.fatG = target.fatG
            existing.notes = target.notes
            existing.deletedAt = nil
        } else {
            modelContext.insert(target)
        }
        try? modelContext.save()
    }

    private func toggleVoiceMealRecording() async {
        if mealRecorder.isRecording {
            await finishVoiceMealRecording()
        } else {
            await startVoiceMealRecording()
        }
    }

    private func startVoiceMealRecording() async {
        voiceMealMessage = nil
        voiceMealError = nil
        do {
            try await mealRecorder.start()
            recordingStartedAt = Date()
            voiceMealMessage = "Recording meal..."
        } catch {
            recordingStartedAt = nil
            voiceMealError = error.localizedDescription
        }
    }

    private func finishVoiceMealRecording() async {
        let audioURL: URL
        do {
            audioURL = try mealRecorder.stop()
        } catch {
            voiceMealError = error.localizedDescription
            recordingStartedAt = nil
            return
        }

        recordingStartedAt = nil
        isAnalyzingVoiceMeal = true
        voiceMealMessage = nil
        voiceMealError = nil
        defer {
            isAnalyzingVoiceMeal = false
            try? FileManager.default.removeItem(at: audioURL)
        }

        do {
            let draft = try await GeminiNutritionService.shared.draftMeal(
                from: audioURL,
                selectedDate: selectedDate,
                apiKey: geminiAPIKey
            )
            activeSheet = .voiceDraft(draft)
            voiceMealMessage = "Review Gemini's meal draft before logging."
        } catch {
            voiceMealError = error.localizedDescription
        }
    }

    private func saveVoiceEntries(_ entries: [NutritionEntry]) {
        for entry in entries {
            modelContext.insert(entry)
        }
        try? modelContext.save()
        if writeHealthNutrition {
            for entry in entries {
                let snapshot = HealthNutritionSnapshot(entry: entry)
                Task {
                    try? await HealthKitService.shared.saveNutrition(snapshot)
                }
            }
        }
    }

    private func update(_ existing: NutritionEntry, with edited: NutritionEntry) {
        existing.loggedAt = edited.loggedAt
        existing.mealName = edited.mealName
        existing.foodName = edited.foodName
        existing.servingDescription = edited.servingDescription
        existing.quantity = edited.quantity
        existing.quantityUnit = edited.quantityUnit
        existing.calories = edited.calories
        existing.proteinG = edited.proteinG
        existing.carbsG = edited.carbsG
        existing.fatG = edited.fatG
        existing.fiberG = edited.fiberG
        existing.sugarG = edited.sugarG
        existing.saturatedFatG = edited.saturatedFatG
        existing.monounsaturatedFatG = edited.monounsaturatedFatG
        existing.polyunsaturatedFatG = edited.polyunsaturatedFatG
        existing.transFatG = edited.transFatG
        existing.omega3G = edited.omega3G
        existing.alaOmega3G = edited.alaOmega3G
        existing.epaOmega3G = edited.epaOmega3G
        existing.dpaOmega3G = edited.dpaOmega3G
        existing.dhaOmega3G = edited.dhaOmega3G
        existing.omega6G = edited.omega6G
        existing.linoleicAcidG = edited.linoleicAcidG
        existing.arachidonicAcidG = edited.arachidonicAcidG
        existing.omega9G = edited.omega9G
        existing.sodiumMg = edited.sodiumMg
        existing.potassiumMg = edited.potassiumMg
        existing.calciumMg = edited.calciumMg
        existing.ironMg = edited.ironMg
        existing.magnesiumMg = edited.magnesiumMg
        existing.phosphorusMg = edited.phosphorusMg
        existing.zincMg = edited.zincMg
        existing.seleniumMcg = edited.seleniumMcg
        existing.copperMg = edited.copperMg
        existing.manganeseMg = edited.manganeseMg
        existing.iodineMcg = edited.iodineMcg
        existing.vitaminAMcg = edited.vitaminAMcg
        existing.vitaminCMg = edited.vitaminCMg
        existing.vitaminDMcg = edited.vitaminDMcg
        existing.vitaminEMg = edited.vitaminEMg
        existing.vitaminKMcg = edited.vitaminKMcg
        existing.thiaminMg = edited.thiaminMg
        existing.riboflavinMg = edited.riboflavinMg
        existing.niacinMg = edited.niacinMg
        existing.pantothenicAcidMg = edited.pantothenicAcidMg
        existing.vitaminB6Mg = edited.vitaminB6Mg
        existing.biotinMcg = edited.biotinMcg
        existing.folateMcg = edited.folateMcg
        existing.folicAcidMcg = edited.folicAcidMcg
        existing.vitaminB12Mcg = edited.vitaminB12Mcg
        existing.cholineMg = edited.cholineMg
        existing.cholesterolMg = edited.cholesterolMg
        existing.notes = edited.notes
    }

    private func importHealthNutrition() async {
        isImportingHealthNutrition = true
        defer { isImportingHealthNutrition = false }

        do {
            let snapshots = try await HealthKitService.shared.fetchRecentNutrition()
            let newSnapshots = snapshots.filter { !isDuplicateHealthNutrition($0) }
            for snapshot in newSnapshots {
                modelContext.insert(
                    NutritionEntry(
                        loggedAt: snapshot.loggedAt,
                        mealName: snapshot.mealName,
                        foodName: snapshot.foodName,
                        servingDescription: "Daily Health total",
                        quantity: 1,
                        quantityUnit: "day",
                        calories: snapshot.calories,
                        proteinG: snapshot.proteinG,
                        carbsG: snapshot.carbsG,
                        fatG: snapshot.fatG,
                        fiberG: snapshot.fiberG,
                        sugarG: snapshot.sugarG,
                        sodiumMg: snapshot.sodiumMg,
                        potassiumMg: snapshot.potassiumMg,
                        calciumMg: snapshot.calciumMg,
                        ironMg: snapshot.ironMg,
                        vitaminDMcg: snapshot.vitaminDMcg,
                        cholesterolMg: snapshot.cholesterolMg,
                        notes: "Imported from Health"
                    )
                )
            }
            if !newSnapshots.isEmpty {
                try? modelContext.save()
            }
            healthNutritionMessage = newSnapshots.isEmpty
                ? "No new Health nutrition found."
                : "Imported \(newSnapshots.count) Health nutrition entr\(newSnapshots.count == 1 ? "y" : "ies")."
        } catch {
            healthNutritionError = error.localizedDescription
        }
    }

    private func isDuplicateHealthNutrition(_ snapshot: HealthNutritionSnapshot) -> Bool {
        entries.contains { entry in
            abs(entry.loggedAt.timeIntervalSince(snapshot.loggedAt)) < 60
                && approximatelyEqual(entry.calories, snapshot.calories)
                && approximatelyEqual(entry.proteinG, snapshot.proteinG)
                && approximatelyEqual(entry.carbsG, snapshot.carbsG)
                && approximatelyEqual(entry.fatG, snapshot.fatG)
        }
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.05
    }

    private func estimateExpenditure() -> ExpenditureEstimate? {
        let nutritionWindowStart = Calendar.current.date(byAdding: .day, value: -13, to: selectedDate) ?? selectedDate
        let nutritionWindowEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: selectedDate)) ?? selectedDate
        let windowEntries = entries.filter {
            $0.loggedAt >= Calendar.current.startOfDay(for: nutritionWindowStart)
                && $0.loggedAt < nutritionWindowEnd
        }
        let loggedDayCount = Set(windowEntries.map { Calendar.current.startOfDay(for: $0.loggedAt) }).count
        guard loggedDayCount >= 4 else { return nil }

        let avgCalories = windowEntries.reduce(0) { $0 + $1.calories } / Double(loggedDayCount)
        let bodySamples = bodyMetrics
            .compactMap { metric -> (Date, Double)? in
                guard let weight = metric.bodyweightLb else { return nil }
                return (metric.loggedAt, weight)
            }
            .filter { $0.0 >= Calendar.current.startOfDay(for: nutritionWindowStart) && $0.0 < nutritionWindowEnd }
            .sorted { $0.0 < $1.0 }
        guard let first = bodySamples.first, let last = bodySamples.last else { return nil }
        let days = max(1, last.0.timeIntervalSince(first.0) / 86_400)
        let dailyWeightChange = (last.1 - first.1) / days
        let estimated = avgCalories - dailyWeightChange * 3500
        let suggested = estimated + currentTarget.goal.calorieAdjustment
        return ExpenditureEstimate(
            dailyCalories: max(0, estimated),
            suggestedCalories: max(1200, suggested),
            loggedDays: loggedDayCount,
            weightChangeLb: last.1 - first.1
        )
    }

    private func mealSortIndex(_ meal: String) -> Int {
        FoodEntryEditor.defaultMeals.firstIndex(of: meal) ?? 99
    }
}

private struct NutritionTotals {
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fiberG: Double = 0
    var sugarG: Double = 0
    var sodiumMg: Double = 0
    var potassiumMg: Double = 0
    var calciumMg: Double = 0
    var ironMg: Double = 0
    var vitaminDMcg: Double = 0
    var cholesterolMg: Double = 0

    var netCarbsG: Double {
        max(0, carbsG - fiberG)
    }

    init(
        calories: Double = 0,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        fiberG: Double = 0,
        sugarG: Double = 0,
        sodiumMg: Double = 0,
        potassiumMg: Double = 0,
        calciumMg: Double = 0,
        ironMg: Double = 0,
        vitaminDMcg: Double = 0,
        cholesterolMg: Double = 0
    ) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
        self.potassiumMg = potassiumMg
        self.calciumMg = calciumMg
        self.ironMg = ironMg
        self.vitaminDMcg = vitaminDMcg
        self.cholesterolMg = cholesterolMg
    }

    init(entries: [NutritionEntry]) {
        self.calories = entries.reduce(0) { $0 + $1.calories }
        self.proteinG = entries.reduce(0) { $0 + $1.proteinG }
        self.carbsG = entries.reduce(0) { $0 + $1.carbsG }
        self.fatG = entries.reduce(0) { $0 + $1.fatG }
        self.fiberG = entries.reduce(0) { $0 + ($1.fiberG ?? 0) }
        self.sugarG = entries.reduce(0) { $0 + ($1.sugarG ?? 0) }
        self.sodiumMg = entries.reduce(0) { $0 + ($1.sodiumMg ?? 0) }
        self.potassiumMg = entries.reduce(0) { $0 + ($1.potassiumMg ?? 0) }
        self.calciumMg = entries.reduce(0) { $0 + ($1.calciumMg ?? 0) }
        self.ironMg = entries.reduce(0) { $0 + ($1.ironMg ?? 0) }
        self.vitaminDMcg = entries.reduce(0) { $0 + ($1.vitaminDMcg ?? 0) }
        self.cholesterolMg = entries.reduce(0) { $0 + ($1.cholesterolMg ?? 0) }
    }
}

private struct ExpenditureEstimate {
    let dailyCalories: Double
    let suggestedCalories: Double
    let loggedDays: Int
    let weightChangeLb: Double
}

private struct MealGroup: Identifiable {
    let id = UUID()
    let name: String
    let entries: [NutritionEntry]
}

private struct DateNavigator: View {
    @Binding var date: Date

    var body: some View {
        HStack {
            Button {
                move(days: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Spacer()

            DatePicker("", selection: $date, displayedComponents: [.date])
                .labelsHidden()

            Spacer()

            Button {
                move(days: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
    }

    private func move(days: Int) {
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
}

private struct NutritionSummaryCard: View {
    let totals: NutritionTotals
    let target: NutritionTarget

    private var remainingCalories: Double {
        target.calories - totals.calories
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remaining")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(formatNumber(abs(remainingCalories)))")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(remainingCalories >= 0 ? "kcal left" : "kcal over")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(target.goal.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            HStack(spacing: 12) {
                SummaryMetric(title: "Protein", value: "\(formatNumber(totals.proteinG)) / \(formatNumber(target.proteinG))g")
                SummaryMetric(title: "Net Carbs", value: "\(formatNumber(totals.netCarbsG))g")
                SummaryMetric(title: "Fat", value: "\(formatNumber(totals.fatG)) / \(formatNumber(target.fatG))g")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacroProgressRow: View {
    let title: String
    let value: Double
    let target: Double
    let suffix: String
    let tint: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(value / target, 1.25)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.body)
                Spacer()
                Text("\(formatNumber(value)) / \(formatNumber(target)) \(suffix)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(progress, 1))
                .tint(value > target ? .red : tint)
            HStack {
                Text(value > target ? "\(formatNumber(value - target)) \(suffix) over" : "\(formatNumber(target - value)) \(suffix) remaining")
                Spacer()
                Text("\(Int((target > 0 ? value / target : 0) * 100))%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct NutrientRow: View {
    let title: String
    let value: Double
    let suffix: String

    var body: some View {
        LabeledContent(title, value: "\(formatNumber(value)) \(suffix)")
    }
}

private struct DetailedNutrientPanel: View {
    let totals: DetailedNutrientTotals

    var body: some View {
        Section("Detailed Fats") {
            ForEach(totals.fats) { item in
                NutrientRow(title: item.name, value: item.value, suffix: item.unit)
            }
        }

        Section("Vitamins") {
            ForEach(totals.vitamins) { item in
                NutrientRow(title: item.name, value: item.value, suffix: item.unit)
            }
        }

        Section("Minerals") {
            ForEach(totals.minerals) { item in
                NutrientRow(title: item.name, value: item.value, suffix: item.unit)
            }
        }
    }
}

private struct NutrientAmount: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let unit: String
}

private struct DetailedNutrientTotals {
    let entries: [NutritionEntry]

    var fats: [NutrientAmount] {
        [
            item("Saturated Fat", sum(\.saturatedFatG), "g"),
            item("Monounsaturated Fat", sum(\.monounsaturatedFatG), "g"),
            item("Polyunsaturated Fat", sum(\.polyunsaturatedFatG), "g"),
            item("Trans Fat", sum(\.transFatG), "g"),
            item("Omega-3", sum(\.omega3G), "g"),
            item("ALA Omega-3", sum(\.alaOmega3G), "g"),
            item("EPA Omega-3", sum(\.epaOmega3G), "g"),
            item("DPA Omega-3", sum(\.dpaOmega3G), "g"),
            item("DHA Omega-3", sum(\.dhaOmega3G), "g"),
            item("Omega-6", sum(\.omega6G), "g"),
            item("Linoleic Acid", sum(\.linoleicAcidG), "g"),
            item("Arachidonic Acid", sum(\.arachidonicAcidG), "g"),
            item("Omega-9", sum(\.omega9G), "g"),
        ]
    }

    var vitamins: [NutrientAmount] {
        [
            item("Vitamin A", sum(\.vitaminAMcg), "mcg"),
            item("Vitamin C", sum(\.vitaminCMg), "mg"),
            item("Vitamin D", sum(\.vitaminDMcg), "mcg"),
            item("Vitamin E", sum(\.vitaminEMg), "mg"),
            item("Vitamin K", sum(\.vitaminKMcg), "mcg"),
            item("Thiamin B1", sum(\.thiaminMg), "mg"),
            item("Riboflavin B2", sum(\.riboflavinMg), "mg"),
            item("Niacin B3", sum(\.niacinMg), "mg"),
            item("Pantothenic Acid B5", sum(\.pantothenicAcidMg), "mg"),
            item("Vitamin B6", sum(\.vitaminB6Mg), "mg"),
            item("Biotin B7", sum(\.biotinMcg), "mcg"),
            item("Folate", sum(\.folateMcg), "mcg"),
            item("Folic Acid", sum(\.folicAcidMcg), "mcg"),
            item("Vitamin B12", sum(\.vitaminB12Mcg), "mcg"),
            item("Choline", sum(\.cholineMg), "mg"),
        ]
    }

    var minerals: [NutrientAmount] {
        [
            item("Sodium", sum(\.sodiumMg), "mg"),
            item("Potassium", sum(\.potassiumMg), "mg"),
            item("Calcium", sum(\.calciumMg), "mg"),
            item("Iron", sum(\.ironMg), "mg"),
            item("Magnesium", sum(\.magnesiumMg), "mg"),
            item("Phosphorus", sum(\.phosphorusMg), "mg"),
            item("Zinc", sum(\.zincMg), "mg"),
            item("Selenium", sum(\.seleniumMcg), "mcg"),
            item("Copper", sum(\.copperMg), "mg"),
            item("Manganese", sum(\.manganeseMg), "mg"),
            item("Iodine", sum(\.iodineMcg), "mcg"),
            item("Cholesterol", sum(\.cholesterolMg), "mg"),
        ]
    }

    private func sum(_ keyPath: KeyPath<NutritionEntry, Double?>) -> Double {
        entries.reduce(0) { $0 + ($1[keyPath: keyPath] ?? 0) }
    }

    private func item(_ name: String, _ value: Double, _ unit: String) -> NutrientAmount {
        NutrientAmount(name: name, value: value, unit: unit)
    }
}

private struct EnergyInsightView: View {
    let weeklyAverage: NutritionTotals
    let target: NutritionTarget
    let estimate: ExpenditureEstimate?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                InsightPill(title: "7-day avg", value: "\(formatNumber(weeklyAverage.calories)) kcal")
                InsightPill(title: "Target", value: "\(formatNumber(target.calories)) kcal")
            }

            if let estimate {
                HStack {
                    InsightPill(title: "Expenditure", value: "\(formatNumber(estimate.dailyCalories)) kcal")
                    InsightPill(title: "Suggested", value: "\(formatNumber(estimate.suggestedCalories)) kcal")
                }
                Text("Based on \(estimate.loggedDays) logged nutrition days and \(signedNumber(estimate.weightChangeLb)) lb bodyweight change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Log food and bodyweight for at least 4 days to estimate expenditure and suggest target changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct InsightPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VoiceMealStatusView: View {
    enum Status {
        case recording(startedAt: Date)
        case analyzing
    }

    let status: Status

    var body: some View {
        switch status {
        case .recording(let startedAt):
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                statusRow(
                    icon: "record.circle.fill",
                    title: "Recording meal",
                    detail: elapsedText(from: startedAt, to: context.date),
                    tint: .red,
                    showsSpinner: false
                )
            }
        case .analyzing:
            statusRow(
                icon: "sparkles",
                title: "Analyzing meal",
                detail: "Gemini is drafting the food log",
                tint: .blue,
                showsSpinner: true
            )
        }
    }

    private func statusRow(
        icon: String,
        title: String,
        detail: String,
        tint: Color,
        showsSpinner: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating, isActive: true)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            if showsSpinner {
                ProgressView()
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func elapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct VoiceMealDraftReview: View {
    @Environment(\.dismiss) private var dismiss

    let draft: MealDraft
    let loggedAt: Date
    let onSave: ([NutritionEntry]) -> Void
    @State private var entries: [NutritionEntry]

    init(draft: MealDraft, loggedAt: Date, onSave: @escaping ([NutritionEntry]) -> Void) {
        self.draft = draft
        self.loggedAt = loggedAt
        self.onSave = onSave
        _entries = State(initialValue: draft.nutritionEntries(loggedAt: loggedAt))
    }

    private var totals: NutritionTotals {
        NutritionTotals(entries: entries)
    }

    var body: some View {
        NavigationStack {
            List {
                if let transcript = draft.transcript.nilIfBlankForNutritionView {
                    Section("Transcript") {
                        Text(transcript)
                            .font(.body)
                    }
                }

                Section("Draft") {
                    if entries.isEmpty {
                        ContentUnavailableView(
                            "No foods found",
                            systemImage: "mic.slash",
                            description: Text("Cancel and try speaking the meal again.")
                        )
                    } else {
                        ForEach(entries) { entry in
                            FoodEntryRow(entry: entry)
                        }
                    }
                }

                if !entries.isEmpty {
                    Section("Totals") {
                        LabeledContent("Calories", value: "\(formatNumber(totals.calories)) kcal")
                        LabeledContent("Protein", value: "\(formatNumber(totals.proteinG)) g")
                        LabeledContent("Carbs", value: "\(formatNumber(totals.carbsG)) g")
                        LabeledContent("Fat", value: "\(formatNumber(totals.fatG)) g")
                    }
                }
            }
            .navigationTitle("Review Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log") {
                        onSave(entries)
                        dismiss()
                    }
                    .bold()
                    .disabled(entries.isEmpty)
                }
            }
        }
    }
}

private struct MealGroupView: View {
    let meal: MealGroup
    let onEdit: (NutritionEntry) -> Void
    let onDelete: (NutritionEntry) -> Void

    private var totals: NutritionTotals {
        NutritionTotals(entries: meal.entries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(meal.name)
                    .font(.headline)
                Spacer()
                Text("\(formatNumber(totals.calories)) kcal")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ForEach(meal.entries) { entry in
                FoodEntryRow(
                    entry: entry,
                    onEdit: { onEdit(entry) },
                    onDelete: { onDelete(entry) }
                )

                if entry.id != meal.entries.last?.id {
                    Divider()
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct FoodEntryRow: View {
    let entry: NutritionEntry
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.foodName.capitalized)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(servingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    NutritionPill(text: "\(formatNumber(entry.proteinG))P")
                    NutritionPill(text: "\(formatNumber(entry.netCarbsG)) net C")
                    NutritionPill(text: "\(formatNumber(entry.fatG))F")
                }

                if entry.hasMicronutrients {
                    Text(micronutrientText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(formatNumber(entry.calories))")
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text("kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if onEdit != nil || onDelete != nil {
                    Menu {
                        if let onEdit {
                            Button {
                                onEdit()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }

                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 32, alignment: .trailing)
                    }
                    .accessibilityLabel("Food actions")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit?()
        }
    }

    private var servingText: String {
        let quantity = "\(formatNumber(entry.quantity)) \(entry.quantityUnit)"
        guard let serving = entry.servingDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serving.isEmpty else {
            return quantity
        }
        return "\(quantity) · \(serving)"
    }

    private var micronutrientText: String {
        [
            entry.fiberG.map { "Fiber \(formatNumber($0))g" },
            entry.sodiumMg.map { "Na \(formatNumber($0))mg" },
            entry.potassiumMg.map { "K \(formatNumber($0))mg" },
            entry.ironMg.map { "Iron \(formatNumber($0))mg" },
        ].compactMap(\.self).joined(separator: " · ")
    }
}

private struct NutritionPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

private struct FoodEntryEditor: View {
    static let defaultMeals = ["Breakfast", "Lunch", "Dinner", "Snack"]
    static let quantityUnits = ["serving", "g", "oz", "cup", "tbsp", "tsp", "piece"]

    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let editingEntry: NutritionEntry?
    let onSave: (NutritionEntry) -> Void

    @State private var loggedAt: Date
    @State private var mealName = "Breakfast"
    @State private var barcode = ""
    @State private var searchText = ""
    @State private var lookupResults: [OpenFoodFactsFood] = []
    @State private var lookupSource: FoodLookupSource = .usda
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    @State private var lookupError: String?
    @State private var showBarcodeScanner = false
    @State private var selectedFood: OpenFoodFactsFood?
    @State private var quantity = "1"
    @State private var quantityUnit = "serving"
    @State private var foodName = ""
    @State private var servingDescription = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var sugar = ""
    @State private var sodium = ""
    @State private var potassium = ""
    @State private var calcium = ""
    @State private var iron = ""
    @State private var vitaminD = ""
    @State private var cholesterol = ""
    @State private var detailed = DetailedNutrientEditorValues()
    @State private var notes = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case foodName
    }

    private enum FoodLookupSource: String, CaseIterable, Identifiable {
        case usda
        case openFoodFacts

        var id: String { rawValue }

        var label: String {
            switch self {
            case .usda: return "USDA"
            case .openFoodFacts: return "Open Food Facts"
            }
        }
    }

    init(initialDate: Date, editingEntry: NutritionEntry?, onSave: @escaping (NutritionEntry) -> Void) {
        self.initialDate = initialDate
        self.editingEntry = editingEntry
        self.onSave = onSave
        _loggedAt = State(initialValue: editingEntry?.loggedAt ?? initialDate)
        _mealName = State(initialValue: editingEntry?.mealName ?? "Breakfast")
        _quantity = State(initialValue: editingEntry.map { formatNumber($0.quantity) } ?? "1")
        _quantityUnit = State(initialValue: editingEntry?.quantityUnit ?? "serving")
        _foodName = State(initialValue: editingEntry?.foodName ?? "")
        _servingDescription = State(initialValue: editingEntry?.servingDescription ?? "")
        _calories = State(initialValue: editingEntry.map { formatNumber($0.calories) } ?? "")
        _protein = State(initialValue: editingEntry.map { formatNumber($0.proteinG) } ?? "")
        _carbs = State(initialValue: editingEntry.map { formatNumber($0.carbsG) } ?? "")
        _fat = State(initialValue: editingEntry.map { formatNumber($0.fatG) } ?? "")
        _fiber = State(initialValue: editingEntry?.fiberG.map(formatNumber) ?? "")
        _sugar = State(initialValue: editingEntry?.sugarG.map(formatNumber) ?? "")
        _sodium = State(initialValue: editingEntry?.sodiumMg.map(formatNumber) ?? "")
        _potassium = State(initialValue: editingEntry?.potassiumMg.map(formatNumber) ?? "")
        _calcium = State(initialValue: editingEntry?.calciumMg.map(formatNumber) ?? "")
        _iron = State(initialValue: editingEntry?.ironMg.map(formatNumber) ?? "")
        _vitaminD = State(initialValue: editingEntry?.vitaminDMcg.map(formatNumber) ?? "")
        _cholesterol = State(initialValue: editingEntry?.cholesterolMg.map(formatNumber) ?? "")
        _detailed = State(initialValue: DetailedNutrientEditorValues(entry: editingEntry))
        _notes = State(initialValue: editingEntry?.notes ?? "")
    }

    private var canSave: Bool {
        !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && doubleValue(calories) != nil
            && (doubleValue(quantity) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if editingEntry == nil {
                    Section("Lookup") {
                    Picker("Database", selection: $lookupSource) {
                        ForEach(FoodLookupSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        TextField("Barcode", text: $barcode)
                            .keyboardType(.numberPad)
                        Button("Lookup") {
                            Task { await lookupBarcode() }
                        }
                        .disabled(isLookingUp || barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Button {
                        showBarcodeScanner = true
                    } label: {
                        Label("Scan barcode", systemImage: "barcode.viewfinder")
                    }
                    .disabled(!BarcodeScannerView.isAvailable)

                    HStack {
                        TextField("Search foods", text: $searchText)
                        Button("Search") {
                            Task { await searchFoods() }
                        }
                        .disabled(isLookingUp || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if isLookingUp {
                        ProgressView()
                    }

                    if let lookupMessage {
                        Text(lookupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let lookupError {
                        Text(lookupError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    ForEach(lookupResults) { result in
                        Button {
                            apply(result)
                        } label: {
                            FoodLookupResultRow(food: result)
                        }
                        .buttonStyle(.plain)
                    }
                    }
                }

                Section {
                    DatePicker("Date", selection: $loggedAt, displayedComponents: [.date, .hourAndMinute])
                    Picker("Meal", selection: $mealName) {
                        ForEach(Self.defaultMeals, id: \.self) { meal in
                            Text(meal).tag(meal)
                        }
                    }
                    TextField("Food", text: $foodName)
                        .focused($focusedField, equals: .foodName)
                    TextField("Serving", text: $servingDescription)
                }

                Section("Quantity") {
                    HStack {
                        TextField("Amount", text: $quantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Picker("Unit", selection: $quantityUnit) {
                            ForEach(Self.quantityUnits, id: \.self) { unit in
                                Text(unit).tag(unit)
                            }
                        }
                    }
                    if selectedFood != nil {
                        Button("Apply quantity") {
                            applyQuantity()
                        }
                    } else if editingEntry != nil {
                        Button("Scale current food") {
                            scaleCurrentEntry()
                        }
                    }
                    Text(quantityHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Macros") {
                    NutritionNumberField(title: "Calories", suffix: "kcal", text: $calories)
                    NutritionNumberField(title: "Protein", suffix: "g", text: $protein)
                    NutritionNumberField(title: "Carbs", suffix: "g", text: $carbs)
                    LabeledContent("Net Carbs", value: "\(formatNumber(netCarbsValue)) g")
                    NutritionNumberField(title: "Fat", suffix: "g", text: $fat)
                    NutritionNumberField(title: "Fiber", suffix: "g", text: $fiber)
                }

                Section("Micronutrients") {
                    NutritionNumberField(title: "Sugar", suffix: "g", text: $sugar)
                    NutritionNumberField(title: "Sodium", suffix: "mg", text: $sodium)
                    NutritionNumberField(title: "Potassium", suffix: "mg", text: $potassium)
                    NutritionNumberField(title: "Calcium", suffix: "mg", text: $calcium)
                    NutritionNumberField(title: "Iron", suffix: "mg", text: $iron)
                    NutritionNumberField(title: "Vitamin D", suffix: "mcg", text: $vitaminD)
                    NutritionNumberField(title: "Cholesterol", suffix: "mg", text: $cholesterol)
                }

                detailedNutrientFields

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(editingEntry == nil ? "Add Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(
                            NutritionEntry(
                                loggedAt: loggedAt,
                                mealName: mealName,
                                foodName: trimmed(foodName) ?? "Food",
                                servingDescription: trimmed(servingDescription),
                                quantity: doubleValue(quantity) ?? 1,
                                quantityUnit: quantityUnit,
                                calories: scaledCalories,
                                proteinG: scaledProtein,
                                carbsG: scaledCarbs,
                                fatG: scaledFat,
                                fiberG: scaledFiber,
                                sugarG: scaledSugar,
                                saturatedFatG: detailed.optional(\.saturatedFat, multiplier: quantityMultiplierForSave),
                                monounsaturatedFatG: detailed.optional(\.monounsaturatedFat, multiplier: quantityMultiplierForSave),
                                polyunsaturatedFatG: detailed.optional(\.polyunsaturatedFat, multiplier: quantityMultiplierForSave),
                                transFatG: detailed.optional(\.transFat, multiplier: quantityMultiplierForSave),
                                omega3G: detailed.optional(\.omega3, multiplier: quantityMultiplierForSave),
                                alaOmega3G: detailed.optional(\.alaOmega3, multiplier: quantityMultiplierForSave),
                                epaOmega3G: detailed.optional(\.epaOmega3, multiplier: quantityMultiplierForSave),
                                dpaOmega3G: detailed.optional(\.dpaOmega3, multiplier: quantityMultiplierForSave),
                                dhaOmega3G: detailed.optional(\.dhaOmega3, multiplier: quantityMultiplierForSave),
                                omega6G: detailed.optional(\.omega6, multiplier: quantityMultiplierForSave),
                                linoleicAcidG: detailed.optional(\.linoleicAcid, multiplier: quantityMultiplierForSave),
                                arachidonicAcidG: detailed.optional(\.arachidonicAcid, multiplier: quantityMultiplierForSave),
                                omega9G: detailed.optional(\.omega9, multiplier: quantityMultiplierForSave),
                                sodiumMg: scaledSodium,
                                potassiumMg: scaledPotassium,
                                calciumMg: scaledCalcium,
                                ironMg: scaledIron,
                                magnesiumMg: detailed.optional(\.magnesium, multiplier: quantityMultiplierForSave),
                                phosphorusMg: detailed.optional(\.phosphorus, multiplier: quantityMultiplierForSave),
                                zincMg: detailed.optional(\.zinc, multiplier: quantityMultiplierForSave),
                                seleniumMcg: detailed.optional(\.selenium, multiplier: quantityMultiplierForSave),
                                copperMg: detailed.optional(\.copper, multiplier: quantityMultiplierForSave),
                                manganeseMg: detailed.optional(\.manganese, multiplier: quantityMultiplierForSave),
                                iodineMcg: detailed.optional(\.iodine, multiplier: quantityMultiplierForSave),
                                vitaminAMcg: detailed.optional(\.vitaminA, multiplier: quantityMultiplierForSave),
                                vitaminCMg: detailed.optional(\.vitaminC, multiplier: quantityMultiplierForSave),
                                vitaminDMcg: scaledVitaminD,
                                vitaminEMg: detailed.optional(\.vitaminE, multiplier: quantityMultiplierForSave),
                                vitaminKMcg: detailed.optional(\.vitaminK, multiplier: quantityMultiplierForSave),
                                thiaminMg: detailed.optional(\.thiamin, multiplier: quantityMultiplierForSave),
                                riboflavinMg: detailed.optional(\.riboflavin, multiplier: quantityMultiplierForSave),
                                niacinMg: detailed.optional(\.niacin, multiplier: quantityMultiplierForSave),
                                pantothenicAcidMg: detailed.optional(\.pantothenicAcid, multiplier: quantityMultiplierForSave),
                                vitaminB6Mg: detailed.optional(\.vitaminB6, multiplier: quantityMultiplierForSave),
                                biotinMcg: detailed.optional(\.biotin, multiplier: quantityMultiplierForSave),
                                folateMcg: detailed.optional(\.folate, multiplier: quantityMultiplierForSave),
                                folicAcidMcg: detailed.optional(\.folicAcid, multiplier: quantityMultiplierForSave),
                                vitaminB12Mcg: detailed.optional(\.vitaminB12, multiplier: quantityMultiplierForSave),
                                cholineMg: detailed.optional(\.choline, multiplier: quantityMultiplierForSave),
                                cholesterolMg: scaledCholesterol,
                                notes: trimmed(notes)
                            )
                        )
                    }
                    .bold()
                    .disabled(!canSave)
                }
            }
            .onAppear {
                focusedField = .foodName
            }
            .sheet(isPresented: $showBarcodeScanner) {
                BarcodeScannerView { code in
                    barcode = code
                    showBarcodeScanner = false
                    Task { await lookupBarcode() }
                }
            }
        }
    }

    private var netCarbsValue: Double {
        max(0, (doubleValue(carbs) ?? 0) - (doubleValue(fiber) ?? 0))
    }

    private var quantityHelpText: String {
        guard let selectedFood else {
            if editingEntry != nil {
                return "Change quantity and tap Scale current food to adjust this logged entry."
            }
            return "Manual entries use the nutrient values exactly as entered."
        }
        if quantityUnit == "serving" {
            return "Scales from \(selectedFood.serving ?? "one serving")."
        }
        if let grams = gramsForCurrentQuantity {
            return "Approx. \(formatNumber(grams)) g, scaled from \(selectedFood.serving ?? "one serving")."
        }
        return "No gram conversion is available for this unit, so one serving will be used."
    }

    private var quantityMultiplier: Double {
        guard let selectedFood else { return 1 }
        let amount = max(0, doubleValue(quantity) ?? 1)
        if quantityUnit == "serving" {
            return amount
        }
        guard let targetGrams = gramsForCurrentQuantity,
              let baseGrams = selectedFood.servingGrams,
              baseGrams > 0 else {
            return 1
        }
        return targetGrams / baseGrams
    }

    private var gramsForCurrentQuantity: Double? {
        let amount = max(0, doubleValue(quantity) ?? 1)
        switch quantityUnit {
        case "g":
            return amount
        case "oz":
            return amount * 28.3495
        case "cup":
            return amount * 240
        case "tbsp":
            return amount * 15
        case "tsp":
            return amount * 5
        case "piece":
            return selectedFood?.servingGrams.map { amount * $0 }
        default:
            return nil
        }
    }

    private var scaledCalories: Double { scaled(doubleValue(calories) ?? 0) }
    private var scaledProtein: Double { scaled(doubleValue(protein) ?? 0) }
    private var scaledCarbs: Double { scaled(doubleValue(carbs) ?? 0) }
    private var scaledFat: Double { scaled(doubleValue(fat) ?? 0) }
    private var scaledFiber: Double? { scaledOptional(doubleValue(fiber)) }
    private var scaledSugar: Double? { scaledOptional(doubleValue(sugar)) }
    private var scaledSodium: Double? { scaledOptional(doubleValue(sodium)) }
    private var scaledPotassium: Double? { scaledOptional(doubleValue(potassium)) }
    private var scaledCalcium: Double? { scaledOptional(doubleValue(calcium)) }
    private var scaledIron: Double? { scaledOptional(doubleValue(iron)) }
    private var scaledVitaminD: Double? { scaledOptional(doubleValue(vitaminD)) }
    private var scaledCholesterol: Double? { scaledOptional(doubleValue(cholesterol)) }

    private var quantityMultiplierForSave: Double { 1 }

    private func scaled(_ value: Double) -> Double {
        value
    }

    private func scaledOptional(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return scaled(value)
    }

    private func lookupBarcode() async {
        isLookingUp = true
        lookupMessage = nil
        lookupError = nil
        defer { isLookingUp = false }

        do {
            let food: OpenFoodFactsFood
            switch lookupSource {
            case .usda:
                if let usdaFood = try await USDAFoodDataService.shared.lookupBarcode(barcode) {
                    food = usdaFood
                } else {
                    food = try await OpenFoodFactsService.shared.lookupBarcode(barcode)
                }
            case .openFoodFacts:
                food = try await OpenFoodFactsService.shared.lookupBarcode(barcode)
            }
            lookupResults = [food]
            apply(food)
            lookupMessage = "Filled from \(lookupSource.label)."
        } catch {
            lookupError = error.localizedDescription
        }
    }

    private func searchFoods() async {
        isLookingUp = true
        lookupMessage = nil
        lookupError = nil
        defer { isLookingUp = false }

        do {
            switch lookupSource {
            case .usda:
                lookupResults = try await USDAFoodDataService.shared.search(searchText)
            case .openFoodFacts:
                lookupResults = try await OpenFoodFactsService.shared.search(searchText)
            }
            lookupMessage = lookupResults.isEmpty ? "No \(lookupSource.label) results found." : "\(lookupResults.count) result\(lookupResults.count == 1 ? "" : "s") found."
        } catch {
            lookupError = error.localizedDescription
        }
    }

    private func apply(_ food: OpenFoodFactsFood) {
        selectedFood = food
        quantity = "1"
        quantityUnit = "serving"
        barcode = food.barcode
        foodName = food.displayName
        servingDescription = food.serving ?? "Open Food Facts serving"
        calories = formatNumber(food.calories)
        protein = formatNumber(food.proteinG)
        carbs = formatNumber(food.carbsG)
        fat = formatNumber(food.fatG)
        fiber = food.fiberG.map(formatNumber) ?? ""
        sugar = food.sugarG.map(formatNumber) ?? ""
        sodium = food.sodiumMg.map(formatNumber) ?? ""
        potassium = food.potassiumMg.map(formatNumber) ?? ""
        calcium = food.calciumMg.map(formatNumber) ?? ""
        iron = food.ironMg.map(formatNumber) ?? ""
        vitaminD = food.vitaminDMcg.map(formatNumber) ?? ""
        cholesterol = food.cholesterolMg.map(formatNumber) ?? ""
        detailed.apply(food)
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = "\(lookupSource.label) lookup \(food.barcode)"
        }
    }

    private func applyQuantity() {
        guard let selectedFood else { return }
        let multiplier = quantityMultiplier
        calories = formatNumber(selectedFood.calories * multiplier)
        protein = formatNumber(selectedFood.proteinG * multiplier)
        carbs = formatNumber(selectedFood.carbsG * multiplier)
        fat = formatNumber(selectedFood.fatG * multiplier)
        fiber = selectedFood.fiberG.map { formatNumber($0 * multiplier) } ?? ""
        sugar = selectedFood.sugarG.map { formatNumber($0 * multiplier) } ?? ""
        sodium = selectedFood.sodiumMg.map { formatNumber($0 * multiplier) } ?? ""
        potassium = selectedFood.potassiumMg.map { formatNumber($0 * multiplier) } ?? ""
        calcium = selectedFood.calciumMg.map { formatNumber($0 * multiplier) } ?? ""
        iron = selectedFood.ironMg.map { formatNumber($0 * multiplier) } ?? ""
        vitaminD = selectedFood.vitaminDMcg.map { formatNumber($0 * multiplier) } ?? ""
        cholesterol = selectedFood.cholesterolMg.map { formatNumber($0 * multiplier) } ?? ""
        detailed.scale(food: selectedFood, multiplier: multiplier)
    }

    private func scaleCurrentEntry() {
        guard let editingEntry else { return }
        let originalQuantity = max(editingEntry.quantity, 0.0001)
        let newQuantity = max(0, doubleValue(quantity) ?? editingEntry.quantity)
        let multiplier = newQuantity / originalQuantity

        calories = formatNumber(editingEntry.calories * multiplier)
        protein = formatNumber(editingEntry.proteinG * multiplier)
        carbs = formatNumber(editingEntry.carbsG * multiplier)
        fat = formatNumber(editingEntry.fatG * multiplier)
        fiber = editingEntry.fiberG.map { formatNumber($0 * multiplier) } ?? ""
        sugar = editingEntry.sugarG.map { formatNumber($0 * multiplier) } ?? ""
        sodium = editingEntry.sodiumMg.map { formatNumber($0 * multiplier) } ?? ""
        potassium = editingEntry.potassiumMg.map { formatNumber($0 * multiplier) } ?? ""
        calcium = editingEntry.calciumMg.map { formatNumber($0 * multiplier) } ?? ""
        iron = editingEntry.ironMg.map { formatNumber($0 * multiplier) } ?? ""
        vitaminD = editingEntry.vitaminDMcg.map { formatNumber($0 * multiplier) } ?? ""
        cholesterol = editingEntry.cholesterolMg.map { formatNumber($0 * multiplier) } ?? ""
        detailed.scale(entry: editingEntry, multiplier: multiplier)
    }

    private var detailedNutrientFields: some View {
        Group {
            Section("Detailed Fats") {
                NutritionNumberField(title: "Saturated Fat", suffix: "g", text: $detailed.saturatedFat)
                NutritionNumberField(title: "Monounsaturated Fat", suffix: "g", text: $detailed.monounsaturatedFat)
                NutritionNumberField(title: "Polyunsaturated Fat", suffix: "g", text: $detailed.polyunsaturatedFat)
                NutritionNumberField(title: "Trans Fat", suffix: "g", text: $detailed.transFat)
                NutritionNumberField(title: "Omega-3", suffix: "g", text: $detailed.omega3)
                NutritionNumberField(title: "ALA Omega-3", suffix: "g", text: $detailed.alaOmega3)
                NutritionNumberField(title: "EPA Omega-3", suffix: "g", text: $detailed.epaOmega3)
                NutritionNumberField(title: "DPA Omega-3", suffix: "g", text: $detailed.dpaOmega3)
                NutritionNumberField(title: "DHA Omega-3", suffix: "g", text: $detailed.dhaOmega3)
                NutritionNumberField(title: "Omega-6", suffix: "g", text: $detailed.omega6)
                NutritionNumberField(title: "Linoleic Acid", suffix: "g", text: $detailed.linoleicAcid)
                NutritionNumberField(title: "Arachidonic Acid", suffix: "g", text: $detailed.arachidonicAcid)
                NutritionNumberField(title: "Omega-9", suffix: "g", text: $detailed.omega9)
            }

            Section("Vitamins") {
                NutritionNumberField(title: "Vitamin A", suffix: "mcg", text: $detailed.vitaminA)
                NutritionNumberField(title: "Vitamin C", suffix: "mg", text: $detailed.vitaminC)
                NutritionNumberField(title: "Vitamin E", suffix: "mg", text: $detailed.vitaminE)
                NutritionNumberField(title: "Vitamin K", suffix: "mcg", text: $detailed.vitaminK)
                NutritionNumberField(title: "Thiamin B1", suffix: "mg", text: $detailed.thiamin)
                NutritionNumberField(title: "Riboflavin B2", suffix: "mg", text: $detailed.riboflavin)
                NutritionNumberField(title: "Niacin B3", suffix: "mg", text: $detailed.niacin)
                NutritionNumberField(title: "Pantothenic Acid B5", suffix: "mg", text: $detailed.pantothenicAcid)
                NutritionNumberField(title: "Vitamin B6", suffix: "mg", text: $detailed.vitaminB6)
                NutritionNumberField(title: "Biotin B7", suffix: "mcg", text: $detailed.biotin)
                NutritionNumberField(title: "Folate", suffix: "mcg", text: $detailed.folate)
                NutritionNumberField(title: "Folic Acid", suffix: "mcg", text: $detailed.folicAcid)
                NutritionNumberField(title: "Vitamin B12", suffix: "mcg", text: $detailed.vitaminB12)
                NutritionNumberField(title: "Choline", suffix: "mg", text: $detailed.choline)
            }

            Section("Minerals") {
                NutritionNumberField(title: "Magnesium", suffix: "mg", text: $detailed.magnesium)
                NutritionNumberField(title: "Phosphorus", suffix: "mg", text: $detailed.phosphorus)
                NutritionNumberField(title: "Zinc", suffix: "mg", text: $detailed.zinc)
                NutritionNumberField(title: "Selenium", suffix: "mcg", text: $detailed.selenium)
                NutritionNumberField(title: "Copper", suffix: "mg", text: $detailed.copper)
                NutritionNumberField(title: "Manganese", suffix: "mg", text: $detailed.manganese)
                NutritionNumberField(title: "Iodine", suffix: "mcg", text: $detailed.iodine)
            }
        }
    }
}

private struct DetailedNutrientEditorValues {
    var saturatedFat = ""
    var monounsaturatedFat = ""
    var polyunsaturatedFat = ""
    var transFat = ""
    var omega3 = ""
    var alaOmega3 = ""
    var epaOmega3 = ""
    var dpaOmega3 = ""
    var dhaOmega3 = ""
    var omega6 = ""
    var linoleicAcid = ""
    var arachidonicAcid = ""
    var omega9 = ""
    var magnesium = ""
    var phosphorus = ""
    var zinc = ""
    var selenium = ""
    var copper = ""
    var manganese = ""
    var iodine = ""
    var vitaminA = ""
    var vitaminC = ""
    var vitaminE = ""
    var vitaminK = ""
    var thiamin = ""
    var riboflavin = ""
    var niacin = ""
    var pantothenicAcid = ""
    var vitaminB6 = ""
    var biotin = ""
    var folate = ""
    var folicAcid = ""
    var vitaminB12 = ""
    var choline = ""

    init() {}

    init(entry: NutritionEntry?) {
        guard let entry else { return }
        saturatedFat = entry.saturatedFatG.map(formatNumber) ?? ""
        monounsaturatedFat = entry.monounsaturatedFatG.map(formatNumber) ?? ""
        polyunsaturatedFat = entry.polyunsaturatedFatG.map(formatNumber) ?? ""
        transFat = entry.transFatG.map(formatNumber) ?? ""
        omega3 = entry.omega3G.map(formatNumber) ?? ""
        alaOmega3 = entry.alaOmega3G.map(formatNumber) ?? ""
        epaOmega3 = entry.epaOmega3G.map(formatNumber) ?? ""
        dpaOmega3 = entry.dpaOmega3G.map(formatNumber) ?? ""
        dhaOmega3 = entry.dhaOmega3G.map(formatNumber) ?? ""
        omega6 = entry.omega6G.map(formatNumber) ?? ""
        linoleicAcid = entry.linoleicAcidG.map(formatNumber) ?? ""
        arachidonicAcid = entry.arachidonicAcidG.map(formatNumber) ?? ""
        omega9 = entry.omega9G.map(formatNumber) ?? ""
        magnesium = entry.magnesiumMg.map(formatNumber) ?? ""
        phosphorus = entry.phosphorusMg.map(formatNumber) ?? ""
        zinc = entry.zincMg.map(formatNumber) ?? ""
        selenium = entry.seleniumMcg.map(formatNumber) ?? ""
        copper = entry.copperMg.map(formatNumber) ?? ""
        manganese = entry.manganeseMg.map(formatNumber) ?? ""
        iodine = entry.iodineMcg.map(formatNumber) ?? ""
        vitaminA = entry.vitaminAMcg.map(formatNumber) ?? ""
        vitaminC = entry.vitaminCMg.map(formatNumber) ?? ""
        vitaminE = entry.vitaminEMg.map(formatNumber) ?? ""
        vitaminK = entry.vitaminKMcg.map(formatNumber) ?? ""
        thiamin = entry.thiaminMg.map(formatNumber) ?? ""
        riboflavin = entry.riboflavinMg.map(formatNumber) ?? ""
        niacin = entry.niacinMg.map(formatNumber) ?? ""
        pantothenicAcid = entry.pantothenicAcidMg.map(formatNumber) ?? ""
        vitaminB6 = entry.vitaminB6Mg.map(formatNumber) ?? ""
        biotin = entry.biotinMcg.map(formatNumber) ?? ""
        folate = entry.folateMcg.map(formatNumber) ?? ""
        folicAcid = entry.folicAcidMcg.map(formatNumber) ?? ""
        vitaminB12 = entry.vitaminB12Mcg.map(formatNumber) ?? ""
        choline = entry.cholineMg.map(formatNumber) ?? ""
    }

    func optional(_ keyPath: KeyPath<DetailedNutrientEditorValues, String>, multiplier: Double = 1) -> Double? {
        doubleValue(self[keyPath: keyPath]).map { $0 * multiplier }
    }

    mutating func apply(_ food: OpenFoodFactsFood) {
        saturatedFat = food.saturatedFatG.map(formatNumber) ?? ""
        monounsaturatedFat = food.monounsaturatedFatG.map(formatNumber) ?? ""
        polyunsaturatedFat = food.polyunsaturatedFatG.map(formatNumber) ?? ""
        transFat = food.transFatG.map(formatNumber) ?? ""
        omega3 = food.omega3G.map(formatNumber) ?? ""
        alaOmega3 = food.alaOmega3G.map(formatNumber) ?? ""
        epaOmega3 = food.epaOmega3G.map(formatNumber) ?? ""
        dpaOmega3 = food.dpaOmega3G.map(formatNumber) ?? ""
        dhaOmega3 = food.dhaOmega3G.map(formatNumber) ?? ""
        omega6 = food.omega6G.map(formatNumber) ?? ""
        linoleicAcid = food.linoleicAcidG.map(formatNumber) ?? ""
        arachidonicAcid = food.arachidonicAcidG.map(formatNumber) ?? ""
        omega9 = food.omega9G.map(formatNumber) ?? ""
        magnesium = food.magnesiumMg.map(formatNumber) ?? ""
        phosphorus = food.phosphorusMg.map(formatNumber) ?? ""
        zinc = food.zincMg.map(formatNumber) ?? ""
        selenium = food.seleniumMcg.map(formatNumber) ?? ""
        copper = food.copperMg.map(formatNumber) ?? ""
        manganese = food.manganeseMg.map(formatNumber) ?? ""
        iodine = food.iodineMcg.map(formatNumber) ?? ""
        vitaminA = food.vitaminAMcg.map(formatNumber) ?? ""
        vitaminC = food.vitaminCMg.map(formatNumber) ?? ""
        vitaminE = food.vitaminEMg.map(formatNumber) ?? ""
        vitaminK = food.vitaminKMcg.map(formatNumber) ?? ""
        thiamin = food.thiaminMg.map(formatNumber) ?? ""
        riboflavin = food.riboflavinMg.map(formatNumber) ?? ""
        niacin = food.niacinMg.map(formatNumber) ?? ""
        pantothenicAcid = food.pantothenicAcidMg.map(formatNumber) ?? ""
        vitaminB6 = food.vitaminB6Mg.map(formatNumber) ?? ""
        biotin = food.biotinMcg.map(formatNumber) ?? ""
        folate = food.folateMcg.map(formatNumber) ?? ""
        folicAcid = food.folicAcidMcg.map(formatNumber) ?? ""
        vitaminB12 = food.vitaminB12Mcg.map(formatNumber) ?? ""
        choline = food.cholineMg.map(formatNumber) ?? ""
    }

    mutating func scale(food: OpenFoodFactsFood, multiplier: Double) {
        apply(food)
        scaleAll(multiplier)
    }

    mutating func scale(entry: NutritionEntry, multiplier: Double) {
        self = DetailedNutrientEditorValues(entry: entry)
        scaleAll(multiplier)
    }

    private mutating func scaleAll(_ multiplier: Double) {
        let fields: [WritableKeyPath<DetailedNutrientEditorValues, String>] = [
            \.saturatedFat, \.monounsaturatedFat, \.polyunsaturatedFat, \.transFat,
            \.omega3, \.alaOmega3, \.epaOmega3, \.dpaOmega3, \.dhaOmega3,
            \.omega6, \.linoleicAcid, \.arachidonicAcid, \.omega9,
            \.magnesium, \.phosphorus, \.zinc, \.selenium, \.copper, \.manganese, \.iodine,
            \.vitaminA, \.vitaminC, \.vitaminE, \.vitaminK, \.thiamin, \.riboflavin,
            \.niacin, \.pantothenicAcid, \.vitaminB6, \.biotin, \.folate, \.folicAcid,
            \.vitaminB12, \.choline,
        ]
        for keyPath in fields {
            if let value = doubleValue(self[keyPath: keyPath]) {
                self[keyPath: keyPath] = formatNumber(value * multiplier)
            }
        }
    }
}

private struct FoodLookupResultRow: View {
    let food: OpenFoodFactsFood

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.displayName)
                    .foregroundStyle(.primary)
                Text(food.serving ?? food.barcode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(formatNumber(food.proteinG))P / \(formatNumber(netCarbs)) net C / \(formatNumber(food.fatG))F")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(formatNumber(food.calories))")
                .font(.body.monospacedDigit())
            Text("kcal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var netCarbs: Double {
        max(0, food.carbsG - (food.fiberG ?? 0))
    }
}

private struct NutritionTargetEditor: View {
    @Environment(\.dismiss) private var dismiss

    let target: NutritionTarget
    let onSave: (NutritionTarget) -> Void

    @State private var effectiveDate = Date()
    @State private var goal: NutritionGoal = .maintenance
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var notes = ""
    @State private var calculatedMacro: CalculatedMacro = .fat
    @State private var isAutoCalculating = false

    private enum CalculatedMacro: String, CaseIterable, Identifiable {
        case carbs
        case fat

        var id: String { rawValue }

        var label: String {
            switch self {
            case .carbs: return "Carbs"
            case .fat: return "Fat"
            }
        }
    }

    private var canSave: Bool {
        doubleValue(calories) != nil
            && doubleValue(protein) != nil
            && doubleValue(carbs) != nil
            && doubleValue(fat) != nil
            && macroCalorieDelta >= 0
            && macroCalorieDelta < 10
    }

    private var macroCalories: Double {
        (doubleValue(protein) ?? 0) * 4
            + (doubleValue(carbs) ?? 0) * 4
            + (doubleValue(fat) ?? 0) * 9
    }

    private var macroCalorieDelta: Double {
        abs((doubleValue(calories) ?? 0) - macroCalories)
    }

    private var macroSummaryText: String {
        let targetCalories = doubleValue(calories) ?? 0
        let delta = macroCalories - targetCalories
        if abs(delta) < 10 {
            return "Macros match calories."
        }
        if delta > 0 {
            return "Macros are \(formatNumber(delta)) kcal over calories."
        }
        return "Macros are \(formatNumber(abs(delta))) kcal under calories."
    }

    init(target: NutritionTarget, onSave: @escaping (NutritionTarget) -> Void) {
        self.target = target
        self.onSave = onSave
        _effectiveDate = State(initialValue: target.effectiveDate)
        _goal = State(initialValue: target.goal)
        _calories = State(initialValue: formatNumber(target.calories))
        _protein = State(initialValue: formatNumber(target.proteinG))
        _carbs = State(initialValue: formatNumber(target.carbsG))
        _fat = State(initialValue: formatNumber(target.fatG))
        _notes = State(initialValue: target.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Effective", selection: $effectiveDate, displayedComponents: [.date])
                    Picker("Goal", selection: $goal) {
                        ForEach(NutritionGoal.allCases) { goal in
                            Text(goal.label).tag(goal)
                        }
                    }
                }

                targetFieldsSection

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Nutrition Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(
                            NutritionTarget(
                                id: target.id,
                                effectiveDate: effectiveDate,
                                goal: goal,
                                calories: doubleValue(calories) ?? target.calories,
                                proteinG: doubleValue(protein) ?? target.proteinG,
                                carbsG: doubleValue(carbs) ?? target.carbsG,
                                fatG: doubleValue(fat) ?? target.fatG,
                                notes: trimmed(notes)
                            )
                        )
                    }
                    .bold()
                    .disabled(!canSave)
                }
            }
            .onChange(of: calories) { _, _ in autoCalculate() }
            .onChange(of: protein) { _, _ in autoCalculate() }
            .onChange(of: carbs) { _, _ in
                guard calculatedMacro == .fat else { return }
                autoCalculate()
            }
            .onChange(of: fat) { _, _ in
                guard calculatedMacro == .carbs else { return }
                autoCalculate()
            }
            .onChange(of: calculatedMacro) { _, _ in autoCalculate() }
        }
    }

    private var targetFieldsSection: some View {
        Section("Targets") {
            NutritionNumberField(title: "Calories", suffix: "kcal", text: $calories)
            Picker("Auto-calculate", selection: $calculatedMacro) {
                ForEach(CalculatedMacro.allCases) { macro in
                    Text(macro.label).tag(macro)
                }
            }
            .pickerStyle(.segmented)
            NutritionNumberField(title: "Protein", suffix: "g", text: $protein)
            NutritionNumberField(title: "Carbs", suffix: "g", text: $carbs)
                .disabled(calculatedMacro == .carbs)
            NutritionNumberField(title: "Fat", suffix: "g", text: $fat)
                .disabled(calculatedMacro == .fat)
            LabeledContent("Macro calories", value: "\(formatNumber(macroCalories)) kcal")
            Text(macroSummaryText)
                .font(.caption)
                .foregroundStyle(macroCalorieDelta < 10 ? Color.secondary : Color.red)
        }
    }

    private func autoCalculate() {
        guard !isAutoCalculating else { return }
        guard let calories = doubleValue(calories),
              let protein = doubleValue(protein) else {
            return
        }

        isAutoCalculating = true
        defer { isAutoCalculating = false }

        switch calculatedMacro {
        case .fat:
            guard let carbs = doubleValue(carbs) else { return }
            let remainingCalories = calories - protein * 4 - carbs * 4
            fat = formatNumber(max(0, remainingCalories / 9))
        case .carbs:
            guard let fat = doubleValue(fat) else { return }
            let remainingCalories = calories - protein * 4 - fat * 9
            carbs = formatNumber(max(0, remainingCalories / 4))
        }
    }
}

private struct NutritionNumberField: View {
    let title: String
    let suffix: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

private struct BarcodeScannerView: View {
    let onCode: (String) -> Void

    static var isAvailable: Bool {
        #if canImport(VisionKit)
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #else
        false
        #endif
    }

    var body: some View {
        #if canImport(VisionKit)
        if Self.isAvailable {
            BarcodeScannerRepresentable(onCode: onCode)
                .ignoresSafeArea()
        } else {
            ContentUnavailableView(
                "Barcode scanning unavailable",
                systemImage: "barcode.viewfinder",
                description: Text("Enter the barcode manually to look it up.")
            )
        }
        #else
        ContentUnavailableView(
            "Barcode scanning unavailable",
            systemImage: "barcode.viewfinder",
            description: Text("Enter the barcode manually to look it up.")
        )
        #endif
    }
}

#if canImport(VisionKit)
private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var didScan = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didScan else { return }
            for item in addedItems {
                guard case let .barcode(barcode) = item,
                      let payload = barcode.payloadStringValue,
                      !payload.isEmpty else {
                    continue
                }
                didScan = true
                onCode(payload)
                return
            }
        }
    }
}
#endif

private func formatNumber(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
}

private func signedNumber(_ value: Double) -> String {
    let prefix = value > 0 ? "+" : ""
    return "\(prefix)\(formatNumber(value))"
}

private func doubleValue(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : Double(trimmed)
}

private func trimmed(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private extension String {
    var nilIfBlankForNutritionView: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    NutritionView()
        .modelContainer(for: IronSchemaV1.models, inMemory: true)
}
