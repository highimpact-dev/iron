import SwiftUI

struct LogSetSheet: View {
    let programExercise: ProgramExercise
    let lastWeight: Double?
    let onSave: (Int, Double?) -> Void
    let onCancel: () -> Void

    @State private var reps: String = ""
    @State private var weight: String = ""
    @FocusState private var focus: Field?

    enum Field { case reps, weight }

    private var name: String { programExercise.exercise?.name ?? "Exercise" }

    private var defaultReps: Int {
        (programExercise.targetRepsMin + programExercise.targetRepsMax) / 2
    }

    private var canSave: Bool {
        Int(reps) ?? 0 > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Reps")
                        Spacer()
                        TextField("\(defaultReps)", text: $reps)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .reps)
                            .frame(maxWidth: 120)
                    }
                    HStack {
                        Text("Weight (lb)")
                        Spacer()
                        TextField(weightPlaceholder, text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .weight)
                            .frame(maxWidth: 120)
                    }
                } footer: {
                    Text("Leave weight blank for bodyweight. Target: \(targetText)")
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let r = Int(reps) ?? defaultReps
                        let w = Double(weight)
                        onSave(r, w)
                    }
                    .bold()
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if reps.isEmpty { reps = "\(defaultReps)" }
                if weight.isEmpty, let last = lastWeight {
                    weight = formatWeight(last)
                }
                focus = .weight
            }
        }
    }

    private var targetText: String {
        let r: String
        if programExercise.targetRepsMin == programExercise.targetRepsMax {
            r = "\(programExercise.targetRepsMin) reps"
        } else {
            r = "\(programExercise.targetRepsMin)–\(programExercise.targetRepsMax) reps"
        }
        return "\(programExercise.targetSets) × \(r)"
    }

    private var weightPlaceholder: String {
        if let last = lastWeight {
            return formatWeight(last)
        }
        return "—"
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}
