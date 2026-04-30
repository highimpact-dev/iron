import SwiftUI
import SwiftData

struct ProgramDayDetailView: View {
    let day: ProgramDay
    let onStart: (Workout) -> Void

    private var orderedExercises: [ProgramExercise] {
        day.exercises.sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    var body: some View {
        List {
            Section("Day plan") {
                ForEach(orderedExercises) { pe in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pe.exercise?.name ?? "—")
                                .font(.body)
                            Text(targetText(pe))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            if let notes = day.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    let workout = Workout(
                        startedAt: Date(),
                        name: day.name,
                        sourceProgram: day.program,
                        sourceProgramDay: day
                    )
                    onStart(workout)
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(day.name)
    }

    private func targetText(_ pe: ProgramExercise) -> String {
        let reps: String
        if pe.targetRepsMin == pe.targetRepsMax {
            reps = "\(pe.targetRepsMin)"
        } else {
            reps = "\(pe.targetRepsMin)–\(pe.targetRepsMax)"
        }
        return "\(pe.targetSets) × \(reps) · \(pe.restSeconds)s rest"
    }
}
