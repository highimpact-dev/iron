import SwiftUI

struct WatchWorkoutView: View {
    @ObservedObject var viewModel: WatchWorkoutViewModel

    var body: some View {
        NavigationStack {
            Group {
                if let workout = viewModel.workout, let exercise = viewModel.selectedExercise {
                    activeWorkoutView(workout: workout, exercise: exercise)
                } else {
                    ContentUnavailableView(
                        "No Active Workout",
                        systemImage: "iphone",
                        description: Text(viewModel.statusText)
                    )
                }
            }
            .navigationTitle("Iron")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                viewModel.markActiveForConnectivityCallbacks()
                viewModel.refresh()
            }
        }
    }

    private func activeWorkoutView(workout: WatchActiveWorkoutSnapshot, exercise: WatchExerciseSnapshot) -> some View {
        List {
            Section {
                Text(workout.workoutName)
                    .font(.headline)
                if let programName = workout.programName {
                    Text(programName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Exercise") {
                Picker("Exercise", selection: $viewModel.selectedExerciseIndex) {
                    ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, item in
                        Text(item.exerciseName).tag(index)
                    }
                }
                .onChange(of: viewModel.selectedExerciseIndex) { _, newValue in
                    guard workout.exercises.indices.contains(newValue) else { return }
                    viewModel.selectExercise(workout.exercises[newValue])
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.headline)
                    Text("Set \(viewModel.nextOrderIndex + 1) of \(exercise.targetSets) · \(exercise.targetRepsMin)-\(exercise.targetRepsMax) reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if exercise.isUnilateral {
                Section("Side") {
                    Picker("Side", selection: Binding(
                        get: { viewModel.side ?? "left" },
                        set: { viewModel.side = $0 }
                    )) {
                        Text("Left").tag("left")
                        Text("Right").tag("right")
                    }
                }
            }

            Section("Log Set") {
                WatchNumberControl(
                    title: "Reps",
                    value: "\(viewModel.reps)",
                    decrement: { viewModel.adjustReps(by: -1) },
                    increment: { viewModel.adjustReps(by: 1) }
                )

                WatchNumberControl(
                    title: "Weight",
                    value: viewModel.weightLb.map { "\(formatWeight($0)) lb" } ?? "BW",
                    decrement: { viewModel.adjustWeight(by: -5) },
                    increment: { viewModel.adjustWeight(by: 5) }
                )

                WatchNumberControl(
                    title: "RIR",
                    value: "\(viewModel.rir)",
                    decrement: { viewModel.rir = max(0, viewModel.rir - 1) },
                    increment: { viewModel.rir += 1 }
                )

                Button {
                    viewModel.logSet()
                } label: {
                    Label("Log Set", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if !exercise.loggedSets.isEmpty {
                Section("Logged") {
                    ForEach(exercise.loggedSets) { set in
                        HStack {
                            Text(loggedSetTitle(set))
                            Spacer()
                            Text("\(set.reps) reps")
                            Text(set.weightLb.map { "\(formatWeight($0))" } ?? "BW")
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func loggedSetTitle(_ set: WatchSetSnapshot) -> String {
        if let side = set.side {
            return "\(set.orderIndex + 1) \(side.capitalized)"
        }
        return "Set \(set.orderIndex + 1)"
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
    }
}

private struct WatchNumberControl: View {
    let title: String
    let value: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.headline.monospacedDigit())
            }

            HStack {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .frame(maxWidth: .infinity)
                }
                Button(action: increment) {
                    Image(systemName: "plus")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    WatchWorkoutView(viewModel: WatchWorkoutViewModel())
}
