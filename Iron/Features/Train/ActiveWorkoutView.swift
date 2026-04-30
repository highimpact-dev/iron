import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var workout: Workout

    @State private var elapsed: TimeInterval = 0
    @State private var logTarget: ProgramExercise?
    @State private var showFinishConfirm = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
        .onReceive(timer) { _ in
            elapsed = Date().timeIntervalSince(workout.startedAt)
        }
        .onAppear {
            elapsed = Date().timeIntervalSince(workout.startedAt)
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
    }

    private func finishWorkout() {
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
