import SwiftUI
import SwiftData
import AudioToolbox
#if canImport(UIKit)
import UIKit
#endif

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var workout: Workout
    @Query(filter: #Predicate<Exercise> { $0.deletedAt == nil }, sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var elapsed: TimeInterval = 0
    @State private var now: Date = Date()
    @State private var logTarget: SetLogTarget?
    @State private var showAddExercise = false
    @State private var showFinishSheet = false
    @State private var rest: RestState?
    @State private var didFireRestHaptic = false
    @State private var beepedAt: Set<Int> = []

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    struct RestState {
        let endsAt: Date
        let totalSeconds: Int
        let exerciseName: String
        let previousSetId: UUID?
        let startedAt: Date
    }

    struct SetLogTarget: Identifiable {
        let id = UUID()
        let programExercise: ProgramExercise
        let setType: SetType
        let orderIndex: Int
        let side: SetSide?
        let defaultReps: Int?
        let defaultWeight: Double?
        let defaultRPE: Double?
        let defaultRIR: Int?
        let defaultNotes: String?
        let locksSetType: Bool
    }

    struct SetSlotKey: Hashable {
        let orderIndex: Int
        let side: SetSide?
    }

    private var orderedProgramExercises: [ProgramExercise] {
        (workout.sourceProgramDay?.exercises ?? [])
            .sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    private var activeExercises: [ProgramExercise] {
        (orderedProgramExercises + workout.additionalExercises)
            .sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    private var activeExerciseIds: Set<UUID> {
        Set(activeExercises.compactMap { effectiveExercise(for: $0)?.id })
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.name ?? "Workout")
                            .font(.headline)
                        if let prog = workout.sourceProgram?.name {
                            Text(prog)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(formatElapsed(elapsed))
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if activeExercises.isEmpty {
                Section {
                    Text("No exercises added.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(activeExercises) { pe in
                    ExerciseSection(
                        programExercise: pe,
                        workingEntries: workingEntriesFor(pe),
                        extraWorkingSets: extraWorkingSetsFor(pe),
                        warmupEntries: warmupEntriesFor(pe),
                        plannedWeight: plannedWorkingWeight(for: pe),
                        exercises: exercises,
                        onAddWarmup: { warmup in logWarmupTarget(programExercise: pe, warmup: warmup) },
                        onLogWorkingSet: { orderIndex, side, existingSet in
                            logWorkingSetTarget(programExercise: pe, orderIndex: orderIndex, side: side, existingSet: existingSet)
                        },
                        onAddSet: { logWorkingSetTarget(programExercise: pe) },
                        onDeleteSet: deleteSet,
                        onSelectSubstitution: { selected in selectSubstitution(selected, for: pe) }
                    )
                }
            }
        }
        .navigationTitle("Active")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showAddExercise = true
                } label: {
                    Label("Add Accessory", systemImage: "plus")
                }

                Button("Finish") { showFinishSheet = true }
                    .bold()
            }
        }
        .sheet(isPresented: $showAddExercise) {
            AccessoryPickerSheet(
                exercises: exercises,
                excludedExerciseIds: activeExerciseIds,
                onAdd: addAccessory
            )
        }
        .sheet(item: $logTarget) { target in
            LogSetSheet(
                programExercise: target.programExercise,
                suggestion: target.setType == .warmup ? .none : suggestion(for: target.programExercise, orderIndex: target.orderIndex, side: target.side),
                side: target.side,
                defaultSetType: target.setType,
                locksSetType: target.locksSetType,
                defaultRepsOverride: target.defaultReps,
                defaultWeightOverride: target.defaultWeight,
                defaultRPEOverride: target.defaultRPE,
                defaultRIROverride: target.defaultRIR,
                defaultNotesOverride: target.defaultNotes,
                onSaveDetailed: { setType, reps, weight, rpe, rir, notes in
                    logSet(
                        programExercise: target.programExercise,
                        setType: setType,
                        orderIndex: target.orderIndex,
                        side: target.side,
                        reps: reps,
                        weight: weight,
                        rpe: rpe,
                        rir: rir,
                        notes: notes
                    )
                    logTarget = nil
                },
                onCancel: { logTarget = nil }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showFinishSheet) {
            FinishWorkoutSheet(
                initialBodyweight: workout.bodyweightLb,
                initialRPE: workout.rpeOverall,
                initialNotes: workout.notes,
                onFinish: { bodyweight, rpe, notes in
                    finishWorkout(bodyweight: bodyweight, rpeOverall: rpe, notes: notes)
                    showFinishSheet = false
                },
                onCancel: { showFinishSheet = false }
            )
            .presentationDetents([.medium])
        }
        .safeAreaInset(edge: .bottom) {
            if let rest {
                RestTimerBar(
                    rest: rest,
                    now: now,
                    onAddTime: { addRest(seconds: 15) },
                    onSkip: { dismissRest() }
                )
            }
        }
        .onReceive(timer) { tick in
            now = tick
            elapsed = tick.timeIntervalSince(workout.startedAt)
            checkRestExpiration()
        }
        .onAppear {
            now = Date()
            elapsed = Date().timeIntervalSince(workout.startedAt)
            WatchConnectivityService.shared.publishActiveWorkoutIfAvailable()
        }
    }

    private func startRest(for pe: ProgramExercise, previousSet: SetEntry) {
        let seconds = max(0, pe.restSeconds)
        guard seconds > 0 else { return }
        let started = Date()
        let endsAt = started.addingTimeInterval(TimeInterval(seconds))
        let name = effectiveExercise(for: pe)?.name ?? "Rest"
        rest = RestState(
            endsAt: endsAt,
            totalSeconds: seconds,
            exerciseName: name,
            previousSetId: previousSet.id,
            startedAt: started
        )
        didFireRestHaptic = false
        beepedAt.removeAll()
        RestNotificationService.schedule(endsAt: endsAt, exerciseName: name)
        RestLiveActivityService.start(
            startedAt: started,
            endsAt: endsAt,
            totalSeconds: seconds,
            exerciseName: name
        )
    }

    private func addRest(seconds: Int) {
        guard let current = rest else { return }
        let newEndsAt = current.endsAt.addingTimeInterval(TimeInterval(seconds))
        rest = RestState(
            endsAt: newEndsAt,
            totalSeconds: current.totalSeconds + seconds,
            exerciseName: current.exerciseName,
            previousSetId: current.previousSetId,
            startedAt: current.startedAt
        )
        didFireRestHaptic = false
        beepedAt.removeAll()
        RestNotificationService.schedule(endsAt: newEndsAt, exerciseName: current.exerciseName)
        RestLiveActivityService.update(
            startedAt: current.startedAt,
            endsAt: newEndsAt,
            totalSeconds: current.totalSeconds + seconds
        )
    }

    private func dismissRest() {
        recordActualRest()
        clearRestTracking()
    }

    private func clearRestTracking() {
        rest = nil
        didFireRestHaptic = false
        beepedAt.removeAll()
        RestNotificationService.cancel()
        RestLiveActivityService.end()
    }

    private func recordActualRest() {
        guard let current = rest, let setId = current.previousSetId else { return }
        let actual = max(0, Int(Date().timeIntervalSince(current.startedAt)))
        let descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate<SetEntry> { $0.id == setId }
        )
        if let match = try? modelContext.fetch(descriptor).first {
            match.restSeconds = actual
            try? modelContext.save()
        }
    }

    private func checkRestExpiration() {
        guard let rest else { return }
        let remaining = Int(rest.endsAt.timeIntervalSince(now).rounded(.up))
        if remaining > 0, remaining <= 10, !beepedAt.contains(remaining) {
            beepedAt.insert(remaining)
            AudioServicesPlaySystemSound(1057)
        }
        if !didFireRestHaptic, now >= rest.endsAt {
            didFireRestHaptic = true
            #if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif
        }
    }

    private func effectiveExercise(for pe: ProgramExercise) -> Exercise? {
        pe.preferredExercise ?? pe.exercise
    }

    private func setEntriesFor(_ pe: ProgramExercise) -> [SetEntry] {
        guard let exercise = effectiveExercise(for: pe) else { return [] }
        return workout.setEntries
            .filter { $0.exercise?.id == exercise.id }
            .filter { $0.exerciseOrderIndex == pe.orderIndex }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    private func workingSetsFor(_ pe: ProgramExercise) -> [SetEntry] {
        setEntriesFor(pe)
            .filter { $0.setType != .warmup }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    private func workingEntriesFor(_ pe: ProgramExercise) -> [SetSlotKey: SetEntry] {
        workingSetsFor(pe)
            .filter { $0.orderIndex < pe.targetSets }
            .reduce(into: [:]) { result, entry in
                result[SetSlotKey(orderIndex: entry.orderIndex, side: entry.side)] = entry
            }
    }

    private func extraWorkingSetsFor(_ pe: ProgramExercise) -> [SetEntry] {
        workingSetsFor(pe)
            .filter { $0.orderIndex >= pe.targetSets }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func warmupEntriesFor(_ pe: ProgramExercise) -> [Int: SetEntry] {
        Dictionary(
            uniqueKeysWithValues: setEntriesFor(pe)
                .filter { $0.setType == .warmup }
                .map { ($0.orderIndex, $0) }
        )
    }

    private func resolvedWorkingWeight(for pe: ProgramExercise) -> Double? {
        if let last = workingSetsFor(pe).last?.weightLb { return last }
        return plannedWorkingWeight(for: pe)
    }

    private func plannedWorkingWeight(for pe: ProgramExercise) -> Double? {
        suggestion(for: pe, orderIndex: 0, side: effectiveExercise(for: pe)?.isUnilateral == true ? .left : nil).weight
    }

    private func suggestion(for pe: ProgramExercise, orderIndex: Int, side: SetSide?) -> SetSuggestion {
        guard let exercise = effectiveExercise(for: pe) else { return .none }
        let exId = exercise.id
        var descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate<SetEntry> { entry in
                entry.exercise?.id == exId
                    && entry.workout?.finishedAt != nil
                    && entry.weightLb != nil
            },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        guard let fetched = try? modelContext.fetch(descriptor) else {
            return .none
        }
        let recent = fetched.filter { entry in
            entry.setType != .warmup && entry.side == side
        }
        guard
              let mostRecentWorkoutId = recent.first?.workout?.id else {
            return .none
        }
        let lastSessionSets = recent
            .filter { $0.workout?.id == mostRecentWorkoutId }
            .sorted { $0.orderIndex < $1.orderIndex }
        guard let topWeight = lastSessionSets.compactMap(\.weightLb).max() else {
            return .none
        }
        let increment = exercise.progressionIncrementLb
        let targetRIR = pe.targetRIR
        let hasAllTargetSets = Set(lastSessionSets.map(\.orderIndex)).isSuperset(of: Set(0..<pe.targetSets))
        let hitTopOfRange = hasAllTargetSets && lastSessionSets
            .filter { $0.orderIndex < pe.targetSets }
            .allSatisfy { $0.reps >= pe.targetRepsMax && (($0.rir ?? targetRIR ?? 0) >= (targetRIR ?? 0)) }

        if hitTopOfRange, increment > 0 {
            let suggested = topWeight + increment
            return SetSuggestion(
                weight: suggested,
                reps: pe.targetRepsMin,
                hint: "Last time both sets reached \(pe.targetRepsMax). Increase to \(formatWeight(suggested)) lb and restart at \(pe.targetRepsMin) reps."
            )
        }

        let matchingSet = lastSessionSets.first { $0.orderIndex == orderIndex }
        let suggestedReps = min(pe.targetRepsMax, (matchingSet?.reps ?? pe.targetRepsMin - 1) + 1)
        return SetSuggestion(
            weight: topWeight,
            reps: max(pe.targetRepsMin, suggestedReps),
            hint: "Double progression: keep \(formatWeight(topWeight)) lb and add reps until both sets reach \(pe.targetRepsMax)."
        )
    }

    private func logWorkingSetTarget(programExercise pe: ProgramExercise) {
        let nextOrderIndex = max(pe.targetSets, (workingSetsFor(pe).map(\.orderIndex).max() ?? pe.targetSets - 1) + 1)
        logWorkingSetTarget(programExercise: pe, orderIndex: nextOrderIndex, side: nil, existingSet: nil)
    }

    private func logWorkingSetTarget(programExercise pe: ProgramExercise, orderIndex: Int, side: SetSide?, existingSet: SetEntry?) {
        let setSuggestion = suggestion(for: pe, orderIndex: orderIndex, side: side)
        logTarget = SetLogTarget(
            programExercise: pe,
            setType: existingSet?.setType ?? defaultSetType(for: pe, orderIndex: orderIndex),
            orderIndex: orderIndex,
            side: side,
            defaultReps: existingSet?.reps ?? setSuggestion.reps,
            defaultWeight: existingSet?.weightLb ?? defaultWorkingWeight(for: pe, orderIndex: orderIndex, side: side),
            defaultRPE: existingSet?.rpe,
            defaultRIR: existingSet?.rir ?? pe.targetRIR,
            defaultNotes: existingSet?.notes,
            locksSetType: false
        )
    }

    private func defaultWorkingWeight(for pe: ProgramExercise, orderIndex: Int, side: SetSide?) -> Double? {
        if orderIndex < pe.targetSets {
            return suggestion(for: pe, orderIndex: orderIndex, side: side).weight
        }
        return resolvedWorkingWeight(for: pe)
    }

    private func defaultSetType(for pe: ProgramExercise, orderIndex: Int) -> SetType {
        guard orderIndex == pe.targetSets - 1, pe.intensityTechnique == "Failure" else {
            return .working
        }
        return .failure
    }

    private func logWarmupTarget(programExercise pe: ProgramExercise, warmup: WarmupSet) {
        logTarget = SetLogTarget(
            programExercise: pe,
            setType: .warmup,
            orderIndex: warmup.orderIndex,
            side: nil,
            defaultReps: warmup.reps,
            defaultWeight: resolvedWarmupWeight(warmup, workingWeight: plannedWorkingWeight(for: pe)),
            defaultRPE: nil,
            defaultRIR: nil,
            defaultNotes: nil,
            locksSetType: true
        )
    }

    private func resolvedWarmupWeight(_ warmup: WarmupSet, workingWeight: Double?) -> Double? {
        if let fixed = warmup.fixedWeightLb { return fixed }
        guard let pct = warmup.percentOfWorkWeight, let workingWeight else { return nil }
        return (workingWeight * pct / 5).rounded() * 5
    }

    private func addAccessory(_ exercise: Exercise, targetSets: Int) {
        guard !activeExerciseIds.contains(exercise.id) else { return }
        let nextOrderIndex = (activeExercises.map(\.orderIndex).max() ?? -1) + 1
        let programExercise = ProgramExercise(
            orderIndex: nextOrderIndex,
            targetSets: targetSets,
            targetRepsMin: 8,
            targetRepsMax: 12,
            targetRIR: 2,
            restSeconds: 120,
            videoURLString: exercise.videoURL?.absoluteString,
            exercise: exercise
        )
        modelContext.insert(programExercise)
        workout.additionalExercises.append(programExercise)
        try? modelContext.save()
        showAddExercise = false
    }

    private func selectSubstitution(_ exercise: Exercise?, for pe: ProgramExercise) {
        guard setEntriesFor(pe).isEmpty else { return }
        pe.preferredExercise = exercise
        try? modelContext.save()
    }

    private func logSet(
        programExercise pe: ProgramExercise,
        setType: SetType,
        orderIndex: Int,
        side: SetSide?,
        reps: Int,
        weight: Double?,
        rpe: Double?,
        rir: Int?,
        notes: String?
    ) {
        guard let exercise = effectiveExercise(for: pe) else { return }
        if rest != nil, setType != .warmup { recordActualRest() }
        if setType == .warmup,
           let existing = setEntriesFor(pe).first(where: { $0.setType == .warmup && $0.orderIndex == orderIndex }) {
            existing.reps = reps
            existing.weightLb = weight
            existing.rpe = rpe
            existing.rir = rir
            existing.notes = notes
            existing.completedAt = Date()
            try? modelContext.save()
            WatchConnectivityService.shared.publishActiveWorkoutIfAvailable()
            return
        }
        if setType != .warmup,
           let existing = workingSetsFor(pe).first(where: { $0.orderIndex == orderIndex && $0.side == side }) {
            existing.setType = setType
            existing.reps = reps
            existing.weightLb = weight
            existing.rpe = rpe
            existing.rir = rir
            existing.side = side
            existing.notes = notes
            existing.completedAt = Date()
            try? modelContext.save()
            startRest(for: pe, previousSet: existing)
            WatchConnectivityService.shared.publishActiveWorkoutIfAvailable()
            return
        }
        let entry = SetEntry(
            orderIndex: orderIndex,
            exerciseOrderIndex: pe.orderIndex,
            setType: setType,
            reps: reps,
            weightLb: weight,
            rpe: rpe,
            rir: rir,
            side: side,
            notes: notes,
            workout: workout,
            exercise: exercise
        )
        modelContext.insert(entry)
        try? modelContext.save()
        if setType != .warmup {
            startRest(for: pe, previousSet: entry)
        }
        WatchConnectivityService.shared.publishActiveWorkoutIfAvailable()
    }

    private func deleteSet(_ set: SetEntry) {
        if rest?.previousSetId == set.id {
            clearRestTracking()
        }
        SetEntry.delete(set, from: workout, in: modelContext)
    }

    private func finishWorkout(bodyweight: Double?, rpeOverall: Double?, notes: String?) {
        if rest != nil { recordActualRest() }
        clearRestTracking()
        workout.bodyweightLb = bodyweight
        workout.rpeOverall = rpeOverall
        workout.notes = notes
        workout.finishedAt = Date()
        try? modelContext.save()
        WatchConnectivityService.shared.publishNoActiveWorkout()

        let snapshot = HealthWorkoutSnapshot(workout: workout)
        Task {
            try? await HealthKitService.shared.saveCompletedWorkout(snapshot)
        }
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let total = Int(max(t, 0))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}

private struct FinishWorkoutSheet: View {
    let initialBodyweight: Double?
    let initialRPE: Double?
    let initialNotes: String?
    let onFinish: (Double?, Double?, String?) -> Void
    let onCancel: () -> Void

    @State private var bodyweight: String
    @State private var rpe: String
    @State private var notes: String
    @FocusState private var focus: Field?

    enum Field { case bodyweight, rpe }

    init(
        initialBodyweight: Double?,
        initialRPE: Double?,
        initialNotes: String?,
        onFinish: @escaping (Double?, Double?, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialBodyweight = initialBodyweight
        self.initialRPE = initialRPE
        self.initialNotes = initialNotes
        self.onFinish = onFinish
        self.onCancel = onCancel
        _bodyweight = State(initialValue: initialBodyweight.map(Self.formatNumber) ?? "")
        _rpe = State(initialValue: initialRPE.map(Self.formatNumber) ?? "")
        _notes = State(initialValue: initialNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Bodyweight (lb)")
                        Spacer()
                        TextField("Optional", text: $bodyweight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .bodyweight)
                            .frame(maxWidth: 120)
                    }
                    HStack {
                        Text("Session RPE")
                        Spacer()
                        TextField("Optional", text: $rpe)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .rpe)
                            .frame(maxWidth: 120)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workout notes")
                        TextField("Optional", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                    }
                } footer: {
                    Text("These fields stay with the completed workout in History.")
                }
            }
            .navigationTitle("Finish Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") {
                        onFinish(
                            Double(bodyweight),
                            Double(rpe),
                            trimmedNotes
                        )
                    }
                    .bold()
                }
            }
            .onAppear {
                focus = .bodyweight
            }
        }
    }

    private static func formatNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ExerciseSection: View {
    let programExercise: ProgramExercise
    let workingEntries: [ActiveWorkoutView.SetSlotKey: SetEntry]
    let extraWorkingSets: [SetEntry]
    let warmupEntries: [Int: SetEntry]
    let plannedWeight: Double?
    let exercises: [Exercise]
    let onAddWarmup: (WarmupSet) -> Void
    let onLogWorkingSet: (Int, SetSide?, SetEntry?) -> Void
    let onAddSet: () -> Void
    let onDeleteSet: (SetEntry) -> Void
    let onSelectSubstitution: (Exercise?) -> Void

    private var exercise: Exercise? { programExercise.preferredExercise ?? programExercise.exercise }
    private var name: String { exercise?.name ?? "—" }
    private var isUnilateral: Bool { exercise?.isUnilateral == true }
    private var setSlotsPerTargetSet: Int { isUnilateral ? 2 : 1 }

    private var orderedWarmups: [WarmupSet] {
        programExercise.warmupSets.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var targetText: String {
        let reps: String
        if programExercise.targetRepsMin == programExercise.targetRepsMax {
            reps = "\(programExercise.targetRepsMin)"
        } else {
            reps = "\(programExercise.targetRepsMin)–\(programExercise.targetRepsMax)"
        }
        var parts = ["Target: \(programExercise.targetSets) × \(reps)"]
        if let targetRIR = programExercise.targetRIR {
            parts.append("\(targetRIR) RIR")
        }
        parts.append(restText)
        return parts.joined(separator: " · ")
    }

    private var progressText: String {
        "\(workingEntries.count)/\(programExercise.targetSets * setSlotsPerTargetSet) sets"
    }

    private var hasLoggedSets: Bool {
        !workingEntries.isEmpty || !extraWorkingSets.isEmpty || !warmupEntries.isEmpty
    }

    var body: some View {
        Section {
            if !orderedWarmups.isEmpty {
                ForEach(orderedWarmups) { w in
                    WarmupRow(
                        warmup: w,
                        loggedSet: warmupEntries[w.orderIndex],
                        workingWeight: plannedWeight,
                        onLog: { onAddWarmup(w) },
                        onDelete: onDeleteSet
                    )
                }
            }

            ForEach(0..<programExercise.targetSets, id: \.self) { orderIndex in
                if isUnilateral {
                    ForEach(SetSide.allCases, id: \.self) { side in
                        let key = ActiveWorkoutView.SetSlotKey(orderIndex: orderIndex, side: side)
                        WorkingSetRow(
                            setNumber: orderIndex + 1,
                            side: side,
                            loggedSet: workingEntries[key],
                            targetRepsText: targetRepsText,
                            plannedWeight: plannedWeight,
                            defaultSetType: defaultSetType(orderIndex: orderIndex),
                            onLog: { onLogWorkingSet(orderIndex, side, workingEntries[key]) },
                            onDelete: onDeleteSet
                        )
                    }
                } else {
                    let key = ActiveWorkoutView.SetSlotKey(orderIndex: orderIndex, side: nil)
                    WorkingSetRow(
                        setNumber: orderIndex + 1,
                        side: nil,
                        loggedSet: workingEntries[key],
                        targetRepsText: targetRepsText,
                        plannedWeight: plannedWeight,
                        defaultSetType: defaultSetType(orderIndex: orderIndex),
                        onLog: { onLogWorkingSet(orderIndex, nil, workingEntries[key]) },
                        onDelete: onDeleteSet
                    )
                }
            }

            ForEach(Array(extraWorkingSets.enumerated()), id: \.element.id) { idx, set in
                LoggedSetRow(setNumber: idx + 1, label: "Extra", set: set)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            onDeleteSet(set)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }

            Button(action: onAddSet) {
                Label("Add set", systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text(name)
                Spacer()
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(workingEntries.count >= programExercise.targetSets * setSlotsPerTargetSet ? .green : .secondary)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                SubstitutionMenu(
                    programExercise: programExercise,
                    exercises: exercises,
                    isDisabled: hasLoggedSets,
                    onSelect: onSelectSubstitution
                )
                Text(targetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let early = programExercise.earlySetTargetRPE, let last = programExercise.lastSetTargetRPE {
                    Text("RPE: early \(early), last \(last)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let target = programExercise.targetRPE {
                    Text("Target RPE: \(formatWeight(target))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let technique = programExercise.intensityTechnique {
                    Text("Technique: \(technique)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let plannedWeight {
                    Text("Planned weight: \(formatWeight(plannedWeight)) lb")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                ProgramExerciseNotes(
                    notes: programExercise.notes,
                    videoURLString: currentVideoURLString,
                    description: exercise?.instructions
                )
            }
        }
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }

    private var targetRepsText: String {
        if programExercise.targetRepsMin == programExercise.targetRepsMax {
            return "\(programExercise.targetRepsMin) reps"
        }
        return "\(programExercise.targetRepsMin)-\(programExercise.targetRepsMax) reps"
    }

    private var restText: String {
        if programExercise.restSeconds == 120 { return "2 min rest" }
        if programExercise.restSeconds >= 180 && programExercise.restSeconds <= 300 { return "3-5 min rest" }
        return "\(programExercise.restSeconds)s rest"
    }

    private var currentVideoURLString: String? {
        guard let preferred = programExercise.preferredExercise else {
            return programExercise.videoURLString ?? exercise?.videoURL?.absoluteString
        }

        if preferred.name == programExercise.substitutionOption1Name {
            return programExercise.substitutionOption1URLString ?? preferred.videoURL?.absoluteString
        }
        if preferred.name == programExercise.substitutionOption2Name {
            return programExercise.substitutionOption2URLString ?? preferred.videoURL?.absoluteString
        }
        return preferred.videoURL?.absoluteString
    }

    private func defaultSetType(orderIndex: Int) -> SetType {
        guard orderIndex == programExercise.targetSets - 1, programExercise.intensityTechnique == "Failure" else {
            return .working
        }
        return .failure
    }
}

struct SubstitutionMenu: View {
    let programExercise: ProgramExercise
    let exercises: [Exercise]
    let isDisabled: Bool
    let onSelect: (Exercise?) -> Void

    private struct Choice: Identifiable {
        let id: String
        let title: String
        let exercise: Exercise?
    }

    private var currentName: String {
        (programExercise.preferredExercise ?? programExercise.exercise)?.name ?? "Select exercise"
    }

    private var choices: [Choice] {
        var result = [
            Choice(
                id: "default",
                title: programExercise.exercise?.name ?? "Default",
                exercise: nil
            )
        ]
        if let name = programExercise.substitutionOption1Name, !name.isEmpty {
            result.append(Choice(id: "sub-1", title: name, exercise: exercise(named: name)))
        }
        if let name = programExercise.substitutionOption2Name, !name.isEmpty {
            result.append(Choice(id: "sub-2", title: name, exercise: exercise(named: name)))
        }
        return result
    }

    var body: some View {
        if choices.count > 1 {
            Menu {
                ForEach(choices) { choice in
                    Button {
                        onSelect(choice.exercise)
                    } label: {
                        if currentName == (choice.exercise?.name ?? programExercise.exercise?.name) {
                            Label(choice.title, systemImage: "checkmark")
                        } else {
                            Text(choice.title)
                        }
                    }
                    .disabled(choice.exercise == nil && programExercise.exercise == nil)
                }
            } label: {
                Label("Exercise: \(currentName)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .disabled(isDisabled)

            if isDisabled {
                Text("Substitutions lock after this workout has logged sets.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exercise(named name: String) -> Exercise? {
        let key = normalized(name)
        return exercises.first { normalized($0.name) == key }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LoggedSetRow: View {
    let setNumber: Int
    var label: String = "Set"
    let set: SetEntry

    var body: some View {
        HStack {
            Text("\(label) \(setNumber)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(set.reps) reps")
                    .font(.body.monospacedDigit())
                HStack(spacing: 6) {
                    Text(set.setType.label)
                    if let side = set.side {
                        Text(side.label)
                    }
                    if let rpe = set.rpe {
                        Text("RPE \(formatWeight(rpe))")
                    }
                    if let rir = set.rir {
                        Text("RIR \(rir)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let weight = set.weightLb {
                Text("\(formatWeight(weight)) lb")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("BW")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}

private struct WorkingSetRow: View {
    let setNumber: Int
    let side: SetSide?
    let loggedSet: SetEntry?
    let targetRepsText: String
    let plannedWeight: Double?
    let defaultSetType: SetType
    let onLog: () -> Void
    let onDelete: (SetEntry) -> Void

    var body: some View {
        HStack {
            Button(action: onLog) {
                HStack {
                    Image(systemName: loggedSet == nil ? "circle" : "checkmark.circle.fill")
                        .foregroundStyle(loggedSet == nil ? Color.secondary : Color.green)
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(width: 80, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loggedSet.map { "\($0.reps) reps" } ?? targetRepsText)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(loggedSet == nil ? .secondary : .primary)
                        if let loggedSet {
                            HStack(spacing: 6) {
                                Text(loggedSet.setType.label)
                                if let rpe = loggedSet.rpe {
                                    Text("RPE \(formatWeight(rpe))")
                                }
                                if let rir = loggedSet.rir {
                                    Text("RIR \(rir)")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        } else if defaultSetType != .working {
                            Text(defaultSetType.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(weightText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let loggedSet {
                Button(role: .destructive) {
                    onDelete(loggedSet)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var weightText: String {
        if let weight = loggedSet?.weightLb {
            return "\(formatWeight(weight)) lb"
        }
        if let plannedWeight {
            return "\(formatWeight(plannedWeight)) lb"
        }
        return "BW"
    }

    private var title: String {
        if let side {
            return "\(side.label) \(setNumber)"
        }
        return "Set \(setNumber)"
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}

private struct AccessoryPickerSheet: View {
    let exercises: [Exercise]
    let excludedExerciseIds: Set<UUID>
    let onAdd: (Exercise, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var targetSets = 2

    private let groups: [(String, [String])] = [
        ("Abs", ["Cable Crunch", "Machine Crunch", "Decline Sit-Up", "Hanging Leg Raise", "Ab Wheel Rollout"]),
        ("Calves", ["Standing Calf Raise", "Leg Press Calf Press", "Single-Leg Dumbbell Calf Raise"]),
        ("Side and Rear Delts", ["Cable Lateral Raise", "Dumbbell Lateral Raise", "Reverse Pec Deck", "Dumbbell Rear Delt Raise", "Cable Face Pull"]),
        ("Arms", ["Incline Dumbbell Curl", "Standing Barbell Curl", "Seated Cable Curl", "Machine Preacher Curl", "Barbell Skull Crusher", "Overhead Triceps Extension", "Tricep Pushdown", "Triceps Pressdown (Bar)"]),
        ("Traps", ["High Incline Shrugs", "Wide-Grip Upright Row", "Barbell Shrug", "Machine Shrug"]),
        ("Hamstrings and Glutes", ["Seated Leg Curl", "Lying Leg Curl", "Barbell Romanian Deadlift", "Dumbbell Romanian Deadlift", "Barbell Hip Thrust"]),
        ("Upper Chest and Pressing", ["Incline Dumbbell Press", "Incline Barbell Press", "Incline Smith Machine Press", "Seated Dumbbell Shoulder Press", "Machine Shoulder Press", "Landmine Press"])
    ]

    private var groupedExercises: [(String, [Exercise])] {
        groups.compactMap { group in
            let matches = group.1.compactMap { name in
                exercises.first { normalized($0.name) == normalized(name) }
            }
            .filter { exercise in
                !excludedExerciseIds.contains(exercise.id)
                    && (searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText))
            }
            return matches.isEmpty ? nil : (group.0, matches)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Working sets", selection: $targetSets) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Accessories use 8-12 reps, 2 RIR, and 2 minutes rest.")
                }

                if groupedExercises.isEmpty {
                    ContentUnavailableView(
                        "No exercises found",
                        systemImage: "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Every available accessory is already in this workout." : "Try another search.")
                    )
                } else {
                    ForEach(groupedExercises, id: \.0) { group in
                        Section(group.0) {
                            ForEach(group.1) { exercise in
                                Button {
                                    onAdd(exercise, targetSets)
                                } label: {
                                    ExercisePickerRow(exercise: exercise)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Accessory")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ExercisePickerRow: View {
    let exercise: Exercise

    private var detailText: String {
        let equipment = exercise.equipment.map(\.rawValue).joined(separator: ", ")
        if equipment.isEmpty { return exercise.category.rawValue.capitalized }
        return "\(exercise.category.rawValue.capitalized) · \(equipment)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
        }
    }
}

private struct WarmupRow: View {
    let warmup: WarmupSet
    let loggedSet: SetEntry?
    let workingWeight: Double?
    let onLog: () -> Void
    let onDelete: (SetEntry) -> Void

    var body: some View {
        HStack {
            Button(action: onLog) {
                HStack {
                    Image(systemName: loggedSet == nil ? "circle" : "checkmark.circle.fill")
                        .foregroundStyle(loggedSet == nil ? Color.secondary : Color.green)
                    Text("Warmup \(warmup.orderIndex + 1)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .frame(width: 80, alignment: .leading)
                    Text(loggedSet.map { "\($0.reps) reps" } ?? "\(warmup.reps) reps")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(loggedSet.flatMap(\.weightLb).map { "\(formatWeight($0)) lb" } ?? weightText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let loggedSet {
                Button(role: .destructive) {
                    onDelete(loggedSet)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var weightText: String {
        if let fixed = warmup.fixedWeightLb {
            if fixed == 45 { return "Empty bar" }
            return "\(formatWeight(fixed)) lb"
        }
        if let pct = warmup.percentOfWorkWeight {
            if let working = workingWeight {
                let raw = working * pct
                let rounded = (raw / 5).rounded() * 5
                return "\(formatWeight(rounded)) lb · \(Int(pct * 100))%"
            }
            return "\(Int(pct * 100))% of work"
        }
        return "—"
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}

private struct RestTimerBar: View {
    let rest: ActiveWorkoutView.RestState
    let now: Date
    let onAddTime: () -> Void
    let onSkip: () -> Void

    private var remaining: Int {
        max(0, Int(rest.endsAt.timeIntervalSince(now).rounded(.up)))
    }

    private var isDone: Bool { now >= rest.endsAt }

    private var progress: Double {
        guard rest.totalSeconds > 0 else { return 1 }
        let elapsed = Double(rest.totalSeconds) - rest.endsAt.timeIntervalSince(now)
        return min(1, max(0, elapsed / Double(rest.totalSeconds)))
    }

    private var formatted: String {
        let s = remaining
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDone ? "Rest complete" : "Resting")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isDone ? .green : .secondary)
                    Text(rest.exerciseName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatted)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(isDone ? .green : .primary)
                    .contentTransition(.numericText(countsDown: true))
            }
            ProgressView(value: progress)
                .tint(isDone ? .green : .accentColor)
            HStack(spacing: 12) {
                Button {
                    onAddTime()
                } label: {
                    Label("+15s", systemImage: "plus.circle")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(role: isDone ? .none : .cancel) {
                    onSkip()
                } label: {
                    Text(isDone ? "Done" : "Skip")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(isDone ? .green : .accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }
}
