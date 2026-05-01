import SwiftUI
import SwiftData
import AudioToolbox
#if canImport(UIKit)
import UIKit
#endif

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var workout: Workout

    @State private var elapsed: TimeInterval = 0
    @State private var now: Date = Date()
    @State private var logTarget: ProgramExercise?
    @State private var showFinishConfirm = false
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

    private var orderedProgramExercises: [ProgramExercise] {
        (workout.sourceProgramDay?.exercises ?? [])
            .sorted(by: { $0.orderIndex < $1.orderIndex })
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

            if orderedProgramExercises.isEmpty {
                Section {
                    Text("Free workout — no program day attached.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(orderedProgramExercises) { pe in
                    ExerciseSection(
                        programExercise: pe,
                        sets: setsFor(pe),
                        onAddSet: { logTarget = pe }
                    )
                }
            }
        }
        .navigationTitle("Active")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") { showFinishConfirm = true }
                    .bold()
            }
        }
        .sheet(item: $logTarget) { pe in
            LogSetSheet(
                programExercise: pe,
                suggestion: suggestion(for: pe),
                onSave: { reps, weight in
                    logSet(programExercise: pe, reps: reps, weight: weight)
                    logTarget = nil
                },
                onCancel: { logTarget = nil }
            )
            .presentationDetents([.medium])
        }
        .alert("Finish workout?", isPresented: $showFinishConfirm) {
            Button("Finish", role: .destructive) { finishWorkout() }
            Button("Keep going", role: .cancel) { }
        } message: {
            Text("This marks the workout complete. You can still view it in History.")
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
        }
    }

    private func startRest(for pe: ProgramExercise, previousSet: SetEntry) {
        let seconds = max(0, pe.restSeconds)
        guard seconds > 0 else { return }
        let started = Date()
        let endsAt = started.addingTimeInterval(TimeInterval(seconds))
        let name = pe.exercise?.name ?? "Rest"
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
    }

    private func dismissRest() {
        recordActualRest()
        rest = nil
        didFireRestHaptic = false
        beepedAt.removeAll()
        RestNotificationService.cancel()
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

    private func setsFor(_ pe: ProgramExercise) -> [SetEntry] {
        guard let exercise = pe.exercise else { return [] }
        return workout.setEntries
            .filter { $0.exercise?.id == exercise.id }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    private func suggestion(for pe: ProgramExercise) -> WeightSuggestion {
        if let last = setsFor(pe).last?.weightLb {
            return .carry(last)
        }
        guard let exercise = pe.exercise else { return .none }
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
        guard let recent = try? modelContext.fetch(descriptor),
              let mostRecentWorkoutId = recent.first?.workout?.id else {
            return .none
        }
        let lastSessionSets = recent.filter { $0.workout?.id == mostRecentWorkoutId }
        guard let topWeight = lastSessionSets.compactMap(\.weightLb).max() else {
            return .none
        }
        let increment = exercise.progressionIncrementLb
        return .progress(last: topWeight, suggested: topWeight + increment)
    }

    private func logSet(programExercise pe: ProgramExercise, reps: Int, weight: Double?) {
        guard let exercise = pe.exercise else { return }
        if rest != nil { recordActualRest() }
        let existing = setsFor(pe)
        let entry = SetEntry(
            orderIndex: existing.count,
            exerciseOrderIndex: pe.orderIndex,
            setType: .working,
            reps: reps,
            weightLb: weight,
            workout: workout,
            exercise: exercise
        )
        modelContext.insert(entry)
        try? modelContext.save()
        startRest(for: pe, previousSet: entry)
    }

    private func finishWorkout() {
        if rest != nil { recordActualRest() }
        rest = nil
        RestNotificationService.cancel()
        workout.finishedAt = Date()
        try? modelContext.save()
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
}

private struct ExerciseSection: View {
    let programExercise: ProgramExercise
    let sets: [SetEntry]
    let onAddSet: () -> Void

    private var name: String { programExercise.exercise?.name ?? "—" }

    private var targetText: String {
        let reps: String
        if programExercise.targetRepsMin == programExercise.targetRepsMax {
            reps = "\(programExercise.targetRepsMin)"
        } else {
            reps = "\(programExercise.targetRepsMin)–\(programExercise.targetRepsMax)"
        }
        return "Target: \(programExercise.targetSets) × \(reps)"
    }

    private var progressText: String {
        "\(sets.count)/\(programExercise.targetSets) sets"
    }

    var body: some View {
        Section {
            ForEach(Array(sets.enumerated()), id: \.element.id) { idx, set in
                HStack {
                    Text("Set \(idx + 1)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                    Text("\(set.reps) reps")
                        .font(.body.monospacedDigit())
                    Spacer()
                    if let w = set.weightLb {
                        Text("\(formatWeight(w)) lb")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("BW")
                            .font(.body)
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(sets.count >= programExercise.targetSets ? .green : .secondary)
            }
        } footer: {
            Text(targetText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
