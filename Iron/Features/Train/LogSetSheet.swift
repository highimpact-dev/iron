import SwiftUI

struct SetSuggestion {
    var weight: Double?
    var reps: Int?
    var hint: String?

    static let none = SetSuggestion()
}

struct LogSetSheet: View {
    let programExercise: ProgramExercise
    let suggestion: SetSuggestion
    let side: SetSide?
    let defaultSetType: SetType
    let locksSetType: Bool
    let defaultRepsOverride: Int?
    let defaultWeightOverride: Double?
    let defaultRPEOverride: Double?
    let defaultRIROverride: Int?
    let defaultNotesOverride: String?
    let onSaveDetailed: (SetType, Int, Double?, Double?, Int?, String?) -> Void
    let onCancel: () -> Void

    @State private var reps: String = ""
    @State private var weight: String = ""
    @State private var setType: SetType
    @State private var rpe: String = ""
    @State private var rir: String = ""
    @State private var notes: String = ""
    @FocusState private var focus: Field?

    enum Field { case reps, weight }

    init(
        programExercise: ProgramExercise,
        suggestion: SetSuggestion,
        side: SetSide? = nil,
        defaultSetType: SetType = .working,
        locksSetType: Bool = false,
        defaultRepsOverride: Int? = nil,
        defaultWeightOverride: Double? = nil,
        defaultRPEOverride: Double? = nil,
        defaultRIROverride: Int? = nil,
        defaultNotesOverride: String? = nil,
        onSaveDetailed: @escaping (SetType, Int, Double?, Double?, Int?, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.programExercise = programExercise
        self.suggestion = suggestion
        self.side = side
        self.defaultSetType = defaultSetType
        self.locksSetType = locksSetType
        self.defaultRepsOverride = defaultRepsOverride
        self.defaultWeightOverride = defaultWeightOverride
        self.defaultRPEOverride = defaultRPEOverride
        self.defaultRIROverride = defaultRIROverride
        self.defaultNotesOverride = defaultNotesOverride
        self.onSaveDetailed = onSaveDetailed
        self.onCancel = onCancel
        _setType = State(initialValue: defaultSetType)
    }

    private var exercise: Exercise? { programExercise.preferredExercise ?? programExercise.exercise }

    private var name: String {
        guard let side else { return exercise?.name ?? "Exercise" }
        return "\(exercise?.name ?? "Exercise") - \(side.label)"
    }

    private var defaultReps: Int {
        if let defaultRepsOverride { return defaultRepsOverride }
        if let reps = suggestion.reps { return reps }
        return programExercise.targetRepsMin
    }

    private var canSave: Bool {
        (Int(reps) ?? 0) > 0 && !hasInvalidWeight
    }

    private var prefillWeight: Double? {
        if let defaultWeightOverride { return defaultWeightOverride }
        return suggestion.weight
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Set type", selection: $setType) {
                        ForEach(SetType.allCases, id: \.self) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .disabled(locksSetType)
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Reps")
                            Spacer()
                            Text(targetRepsText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            NumericAdjustButton(systemName: "minus", accessibilityLabel: "Decrease reps") {
                                adjustReps(by: -1)
                            }
                            TextField("\(defaultReps)", text: $reps)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .focused($focus, equals: .reps)
                                .font(.system(.title2, design: .monospaced).weight(.semibold))
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 88)
                            NumericAdjustButton(systemName: "plus", accessibilityLabel: "Increase reps") {
                                adjustReps(by: 1)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Weight (lb)")
                            Spacer()
                            if let effectiveWeight {
                                Text("\(formatWeight(effectiveWeight)) lb")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 12) {
                            NumericAdjustButton(systemName: "minus", accessibilityLabel: "Decrease weight") {
                                adjustWeight(by: -5)
                            }
                            TextField(weightPlaceholder, text: $weight)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .focused($focus, equals: .weight)
                                .font(.system(.title2, design: .monospaced).weight(.semibold))
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 108)
                            NumericAdjustButton(systemName: "plus", accessibilityLabel: "Increase weight") {
                                adjustWeight(by: 5)
                            }
                        }
                        HStack(spacing: 8) {
                            ForEach(weightQuickAdjustments, id: \.self) { increment in
                                Button {
                                    adjustWeight(by: increment)
                                } label: {
                                    Text(increment > 0 ? "+\(formatWeight(increment))" : formatWeight(increment))
                                        .font(.caption.monospacedDigit().weight(.medium))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    HStack {
                        Text("RPE")
                        Spacer()
                        TextField(targetRPEPlaceholder, text: $rpe)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    HStack {
                        Text("RIR")
                        Spacer()
                        TextField("—", text: $rir)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                        TextField("Optional", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Leave weight blank for bodyweight. Use + to add plates. Target: \(targetText)")
                        if let weightSumText {
                            Text(weightSumText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if hasInvalidWeight {
                            Text("Enter a weight like 75 or 45+20+10.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let progressionHint {
                            Text(progressionHint)
                                .foregroundStyle(.tint)
                        }
                        if let plateText {
                            Text(plateText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
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
                        let w = parsedWeight
                        onSaveDetailed(
                            setType,
                            r,
                            w,
                            Double(rpe),
                            Int(rir),
                            notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        )
                    }
                    .bold()
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if reps.isEmpty { reps = "\(defaultReps)" }
                if weight.isEmpty, let pre = prefillWeight {
                    weight = formatWeight(pre)
                }
                if rpe.isEmpty, let defaultRPEOverride {
                    rpe = formatWeight(defaultRPEOverride)
                }
                if rir.isEmpty, let defaultRIROverride {
                    rir = "\(defaultRIROverride)"
                } else if rir.isEmpty, let targetRIR = programExercise.targetRIR, setType != .warmup {
                    rir = "\(targetRIR)"
                }
                if notes.isEmpty, let defaultNotesOverride {
                    notes = defaultNotesOverride
                }
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

    private var targetRepsText: String {
        if programExercise.targetRepsMin == programExercise.targetRepsMax {
            return "\(programExercise.targetRepsMin) reps"
        }
        return "\(programExercise.targetRepsMin)-\(programExercise.targetRepsMax) reps"
    }

    private var weightQuickAdjustments: [Double] {
        [-10, -5, -2.5, 2.5, 5, 10]
    }

    private var targetRPEPlaceholder: String {
        if setType == .warmup { return "—" }
        if let rpe = programExercise.lastSetTargetRPE, !rpe.isEmpty { return rpe }
        if let target = programExercise.targetRPE { return formatWeight(target) }
        return "—"
    }

    private var weightPlaceholder: String {
        if let pre = prefillWeight {
            return formatWeight(pre)
        }
        return "—"
    }

    private var parsedWeight: Double? {
        WeightExpressionParser.total(from: weight)
    }

    private var hasInvalidWeight: Bool {
        !weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedWeight == nil
    }

    private var weightSumText: String? {
        guard weight.contains("+"), let parsedWeight else { return nil }
        return "Total: \(formatWeight(parsedWeight)) lb"
    }

    private var usesBarbell: Bool {
        exercise?.equipment.contains(.barbell) == true
    }

    private var effectiveWeight: Double? {
        if let typed = parsedWeight, typed > 0 { return typed }
        return prefillWeight
    }

    private var plateText: String? {
        guard usesBarbell, let w = effectiveWeight, w > PlateCalculator.standardBarLb else {
            return nil
        }
        guard let loads = PlateCalculator.plates(targetLb: w) else {
            return "Bar 45 + \(formatWeight((w - PlateCalculator.standardBarLb) / 2)) per side (non-standard)"
        }
        return "Per side: \(PlateCalculator.breakdownText(for: loads))"
    }

    private var progressionHint: String? {
        suggestion.hint
    }

    private func adjustReps(by increment: Int) {
        let current = Int(reps.trimmingCharacters(in: .whitespacesAndNewlines)) ?? defaultReps
        reps = "\(max(1, current + increment))"
    }

    private func adjustWeight(by increment: Double) {
        let current = parsedWeight ?? prefillWeight ?? 0
        let adjusted = max(0, current + increment)
        weight = adjusted == 0 ? "" : formatWeight(adjusted)
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}

private struct NumericAdjustButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .frame(width: 48, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(accessibilityLabel)
    }
}

private enum WeightExpressionParser {
    static func total(from input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "+", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var total = 0.0
        for part in parts {
            let valueString = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !valueString.isEmpty, let value = Double(valueString), value >= 0 else {
                return nil
            }
            total += value
        }
        return total
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
