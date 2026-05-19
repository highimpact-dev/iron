import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var workout: Workout

    @State private var showDeleteConfirm = false

    private var titleText: String {
        if let name = workout.name, !name.isEmpty { return name }
        if let prog = workout.sourceProgram?.name { return prog }
        return "Workout"
    }

    private var dateText: String {
        let date = workout.finishedAt ?? workout.startedAt
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var durationText: String {
        guard let finished = workout.finishedAt else { return "—" }
        let total = Int(finished.timeIntervalSince(workout.startedAt))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        return String(format: "%dm %02ds", m, s)
    }

    private var totalVolume: Double {
        workout.setEntries.filter { $0.setType != .warmup }.reduce(0.0) { acc, set in
            acc + Double(set.reps) * (set.weightLb ?? 0)
        }
    }

    private var volumeText: String {
        totalVolume > 0 ? "\(Int(totalVolume.rounded())) lb" : "—"
    }

    private var setsByExercise: [(exercise: Exercise, sets: [SetEntry])] {
        let grouped = Dictionary(grouping: workout.setEntries) { $0.exercise?.id ?? UUID() }
        return grouped.compactMap { _, sets -> (Exercise, [SetEntry])? in
            guard let exercise = sets.first?.exercise else { return nil }
            let sorted = sets.sorted { $0.orderIndex < $1.orderIndex }
            return (exercise, sorted)
        }
        .sorted { lhs, rhs in
            (lhs.1.first?.exerciseOrderIndex ?? 0) < (rhs.1.first?.exerciseOrderIndex ?? 0)
        }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: dateText)
                LabeledContent("Duration", value: durationText)
                LabeledContent("Working sets", value: "\(workout.setEntries.filter { $0.setType != .warmup }.count)")
                LabeledContent("Warm-up sets", value: "\(workout.setEntries.filter { $0.setType == .warmup }.count)")
                LabeledContent("Volume", value: volumeText)
                if let bw = workout.bodyweightLb {
                    LabeledContent("Bodyweight", value: "\(formatWeight(bw)) lb")
                }
                if let rpe = workout.rpeOverall {
                    LabeledContent("Session RPE", value: formatWeight(rpe))
                }
            }

            if setsByExercise.isEmpty {
                Section {
                    Text("No sets logged.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(setsByExercise, id: \.exercise.id) { entry in
                    Section(entry.exercise.name) {
                        ForEach(Array(entry.sets.enumerated()), id: \.element.id) { idx, set in
                            LoggedSetRow(setNumber: idx + 1, set: set)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        SetEntry.delete(set, from: workout, in: modelContext)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }

            if let notes = workout.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
            }
        }
        .alert("Delete this workout?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                modelContext.delete(workout)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes the session and all its sets.")
        }
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}
