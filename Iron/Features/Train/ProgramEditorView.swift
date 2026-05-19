import SwiftUI
import SwiftData

enum ProgramEditorMode: Equatable {
    case create
    case edit
    case duplicate

    var title: String {
        switch self {
        case .create: "Create Program"
        case .edit: "Edit Program"
        case .duplicate: "Duplicate Program"
        }
    }

    var saveTitle: String {
        switch self {
        case .create: "Create"
        case .edit: "Save"
        case .duplicate: "Duplicate"
        }
    }
}

struct ProgramEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Exercise> { $0.deletedAt == nil }, sort: \Exercise.name)
    private var exercises: [Exercise]

    let mode: ProgramEditorMode
    let program: Program?

    @State private var draft: ProgramEditorDraft

    init(mode: ProgramEditorMode, program: Program? = nil) {
        self.mode = mode
        self.program = program
        _draft = State(initialValue: ProgramEditorDraft(program: program, mode: mode))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Program") {
                    TextField("Name", text: $draft.name)
                    TextField("Author", text: $draft.author)
                    TextField("Description", text: $draft.programDescription, axis: .vertical)
                        .lineLimit(3...8)

                    Stepper(value: $draft.weeksLength, in: 0...104) {
                        LabeledContent("Length", value: draft.weeksLength == 0 ? "Open-ended" : "\(draft.weeksLength) weeks")
                    }

                    Stepper(value: $draft.daysPerWeek, in: 0...7) {
                        LabeledContent("Days per week", value: draft.daysPerWeek == 0 ? "Not set" : "\(draft.daysPerWeek)")
                    }
                }

                ForEach($draft.days) { $day in
                    Section {
                        TextField("Day name", text: $day.name)
                        TextField("Day notes", text: $day.notes, axis: .vertical)
                            .lineLimit(2...6)

                        if day.exercises.isEmpty {
                            ContentUnavailableView(
                                "No exercises",
                                systemImage: "dumbbell",
                                description: Text("Add exercises for this workout day.")
                            )
                        } else {
                            ForEach($day.exercises) { $programExercise in
                                ProgramExerciseEditorRow(
                                    programExercise: $programExercise,
                                    exercises: exercises
                                )
                            }
                            .onDelete { offsets in
                                day.exercises.remove(atOffsets: offsets)
                            }
                        }

                        Button {
                            day.exercises.append(.empty(orderIndex: day.exercises.count))
                        } label: {
                            Label("Add Exercise", systemImage: "plus.circle")
                        }
                    } header: {
                        Text(day.name.isEmpty ? "Workout Day" : day.name)
                    }
                }

                Section {
                    Button {
                        draft.days.append(.empty(dayIndex: draft.days.count))
                    } label: {
                        Label("Add Workout Day", systemImage: "calendar.badge.plus")
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.saveTitle) {
                        save()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
    }

    private func save() {
        let targetProgram: Program
        switch mode {
        case .edit:
            guard let program else { return }
            targetProgram = program
        case .create, .duplicate:
            targetProgram = Program(name: draft.trimmedName)
            targetProgram.isBuiltIn = false
            modelContext.insert(targetProgram)
        }

        let exercisesByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        draft.apply(to: targetProgram, exercisesByID: exercisesByID, in: modelContext)
        try? modelContext.save()
        dismiss()
    }
}

private struct ProgramExerciseEditorRow: View {
    @Binding var programExercise: ProgramExerciseDraft
    let exercises: [Exercise]

    var body: some View {
        DisclosureGroup {
            Picker("Exercise", selection: $programExercise.exerciseID) {
                Text("Select Exercise").tag(UUID?.none)
                ForEach(exercises) { exercise in
                    Text(exercise.name).tag(Optional(exercise.id))
                }
            }

            Stepper(value: $programExercise.targetSets, in: 1...10) {
                LabeledContent("Working sets", value: "\(programExercise.targetSets)")
            }

            Stepper(value: $programExercise.targetRepsMin, in: 1...50) {
                LabeledContent("Rep range min", value: "\(programExercise.targetRepsMin)")
            }

            Stepper(value: $programExercise.targetRepsMax, in: programExercise.targetRepsMin...50) {
                LabeledContent("Rep range max", value: "\(programExercise.targetRepsMax)")
            }

            Stepper(value: $programExercise.targetRIR, in: 0...10) {
                LabeledContent("Target RIR", value: "\(programExercise.targetRIR)")
            }

            Stepper(value: $programExercise.restSeconds, in: 30...600, step: 30) {
                LabeledContent("Rest", value: restText(programExercise.restSeconds))
            }

            TextField("Notes", text: $programExercise.notes, axis: .vertical)
                .lineLimit(2...6)

            TextField("Substitution 1", text: $programExercise.substitutionOption1Name)
            TextField("Substitution 2", text: $programExercise.substitutionOption2Name)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(exerciseName)
                    .font(.body)
                Text("\(programExercise.targetSets) x \(repText) · \(programExercise.targetRIR) RIR · \(restText(programExercise.restSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: programExercise.targetRepsMin) { _, newValue in
            if programExercise.targetRepsMax < newValue {
                programExercise.targetRepsMax = newValue
            }
        }
    }

    private var exerciseName: String {
        guard let exerciseID = programExercise.exerciseID,
              let exercise = exercises.first(where: { $0.id == exerciseID }) else {
            return "Select Exercise"
        }
        return exercise.name
    }

    private var repText: String {
        if programExercise.targetRepsMin == programExercise.targetRepsMax {
            return "\(programExercise.targetRepsMin)"
        }
        return "\(programExercise.targetRepsMin)-\(programExercise.targetRepsMax)"
    }

    private func restText(_ seconds: Int) -> String {
        if seconds % 60 == 0 {
            return "\(seconds / 60) min"
        }
        return "\(seconds)s"
    }
}

private struct ProgramEditorDraft {
    var name: String
    var author: String
    var programDescription: String
    var weeksLength: Int
    var daysPerWeek: Int
    var days: [ProgramDayDraft]

    init(program: Program?, mode: ProgramEditorMode) {
        guard let program else {
            name = ""
            author = ""
            programDescription = ""
            weeksLength = 6
            daysPerWeek = 2
            days = [.empty(dayIndex: 0)]
            return
        }

        name = mode == .duplicate ? "\(program.name) Copy" : program.name
        author = program.author ?? ""
        programDescription = program.programDescription ?? ""
        weeksLength = program.weeksLength ?? 0
        daysPerWeek = program.daysPerWeek ?? 0
        days = program.days
            .sorted(by: Self.daySort)
            .map { ProgramDayDraft(day: $0) }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedName.isEmpty && days.allSatisfy(\.isValid)
    }

    func apply(to program: Program, exercisesByID: [UUID: Exercise], in modelContext: ModelContext) {
        program.name = trimmedName
        program.author = author.nilIfBlank
        program.programDescription = programDescription.nilIfBlank
        program.isBuiltIn = false
        program.weeksLength = weeksLength == 0 ? nil : weeksLength
        program.daysPerWeek = daysPerWeek == 0 ? nil : daysPerWeek
        program.deletedAt = nil

        let existingDays = Dictionary(uniqueKeysWithValues: program.days.map { ($0.id, $0) })

        for (dayIndex, dayDraft) in days.enumerated() {
            let day = dayDraft.sourceID.flatMap { existingDays[$0] } ?? ProgramDay(
                name: dayDraft.trimmedName.isEmpty ? "Day \(dayIndex + 1)" : dayDraft.trimmedName,
                program: program
            )

            if day.program == nil {
                day.program = program
            }
            if !program.days.contains(where: { $0.id == day.id }) {
                program.days.append(day)
                modelContext.insert(day)
            }

            day.name = dayDraft.trimmedName.isEmpty ? "Day \(dayIndex + 1)" : dayDraft.trimmedName
            day.weekIndex = nil
            day.phaseIndex = nil
            day.phaseName = nil
            day.dayIndex = dayIndex
            day.notes = dayDraft.notes.nilIfBlank

            let oldExercises = day.exercises
            day.exercises.removeAll()
            for oldExercise in oldExercises {
                modelContext.delete(oldExercise)
            }

            for (orderIndex, exerciseDraft) in dayDraft.exercises.enumerated() {
                guard let exerciseID = exerciseDraft.exerciseID,
                      let exercise = exercisesByID[exerciseID] else {
                    continue
                }

                let preferredExercise = exerciseDraft.preferredExerciseID.flatMap { exercisesByID[$0] }
                let programExercise = ProgramExercise(
                    orderIndex: orderIndex,
                    targetSets: exerciseDraft.targetSets,
                    targetRepsMin: exerciseDraft.targetRepsMin,
                    targetRepsMax: max(exerciseDraft.targetRepsMin, exerciseDraft.targetRepsMax),
                    targetRIR: exerciseDraft.targetRIR,
                    restSeconds: exerciseDraft.restSeconds,
                    intensityTechnique: exerciseDraft.intensityTechnique.nilIfBlank,
                    videoURLString: exerciseDraft.videoURLString.nilIfBlank,
                    substitutionOption1Name: exerciseDraft.substitutionOption1Name.nilIfBlank,
                    substitutionOption1URLString: exerciseDraft.substitutionOption1URLString.nilIfBlank,
                    substitutionOption2Name: exerciseDraft.substitutionOption2Name.nilIfBlank,
                    substitutionOption2URLString: exerciseDraft.substitutionOption2URLString.nilIfBlank,
                    notes: exerciseDraft.notes.nilIfBlank,
                    exercise: exercise,
                    preferredExercise: preferredExercise,
                    programDay: day
                )
                modelContext.insert(programExercise)
                day.exercises.append(programExercise)

                for warmupDraft in exerciseDraft.warmupSets {
                    let warmupSet = WarmupSet(
                        orderIndex: warmupDraft.orderIndex,
                        percentOfWorkWeight: warmupDraft.percentOfWorkWeight,
                        fixedWeightLb: warmupDraft.fixedWeightLb,
                        reps: warmupDraft.reps,
                        notes: warmupDraft.notes.nilIfBlank,
                        programExercise: programExercise
                    )
                    modelContext.insert(warmupSet)
                    programExercise.warmupSets.append(warmupSet)
                }
            }
        }
    }

    private static func daySort(_ lhs: ProgramDay, _ rhs: ProgramDay) -> Bool {
        let lhsPhase = lhs.phaseIndex ?? 0
        let rhsPhase = rhs.phaseIndex ?? 0
        if lhsPhase != rhsPhase { return lhsPhase < rhsPhase }

        let lhsWeek = lhs.weekIndex ?? 0
        let rhsWeek = rhs.weekIndex ?? 0
        if lhsWeek != rhsWeek { return lhsWeek < rhsWeek }

        return lhs.dayIndex < rhs.dayIndex
    }
}

private struct ProgramDayDraft: Identifiable {
    let id = UUID()
    let sourceID: UUID?
    var name: String
    var notes: String
    var exercises: [ProgramExerciseDraft]

    init(sourceID: UUID?, name: String, notes: String, exercises: [ProgramExerciseDraft]) {
        self.sourceID = sourceID
        self.name = name
        self.notes = notes
        self.exercises = exercises
    }

    init(day: ProgramDay) {
        sourceID = day.id
        name = day.name
        notes = day.notes ?? ""
        exercises = day.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { ProgramExerciseDraft(programExercise: $0) }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        exercises.allSatisfy(\.isValid)
    }

    static func empty(dayIndex: Int) -> ProgramDayDraft {
        ProgramDayDraft(sourceID: nil, name: "Day \(dayIndex + 1)", notes: "", exercises: [])
    }
}

private struct ProgramExerciseDraft: Identifiable {
    let id = UUID()
    let sourceID: UUID?
    var exerciseID: UUID?
    var preferredExerciseID: UUID?
    var targetSets: Int
    var targetRepsMin: Int
    var targetRepsMax: Int
    var targetRIR: Int
    var restSeconds: Int
    var intensityTechnique: String
    var videoURLString: String
    var substitutionOption1Name: String
    var substitutionOption1URLString: String
    var substitutionOption2Name: String
    var substitutionOption2URLString: String
    var notes: String
    var warmupSets: [WarmupSetDraft]

    init(
        sourceID: UUID?,
        exerciseID: UUID?,
        preferredExerciseID: UUID?,
        targetSets: Int,
        targetRepsMin: Int,
        targetRepsMax: Int,
        targetRIR: Int,
        restSeconds: Int,
        intensityTechnique: String,
        videoURLString: String,
        substitutionOption1Name: String,
        substitutionOption1URLString: String,
        substitutionOption2Name: String,
        substitutionOption2URLString: String,
        notes: String,
        warmupSets: [WarmupSetDraft]
    ) {
        self.sourceID = sourceID
        self.exerciseID = exerciseID
        self.preferredExerciseID = preferredExerciseID
        self.targetSets = targetSets
        self.targetRepsMin = targetRepsMin
        self.targetRepsMax = targetRepsMax
        self.targetRIR = targetRIR
        self.restSeconds = restSeconds
        self.intensityTechnique = intensityTechnique
        self.videoURLString = videoURLString
        self.substitutionOption1Name = substitutionOption1Name
        self.substitutionOption1URLString = substitutionOption1URLString
        self.substitutionOption2Name = substitutionOption2Name
        self.substitutionOption2URLString = substitutionOption2URLString
        self.notes = notes
        self.warmupSets = warmupSets
    }

    init(programExercise: ProgramExercise) {
        sourceID = programExercise.id
        exerciseID = programExercise.exercise?.id
        preferredExerciseID = programExercise.preferredExercise?.id
        targetSets = max(1, programExercise.targetSets)
        targetRepsMin = max(1, programExercise.targetRepsMin)
        targetRepsMax = max(targetRepsMin, programExercise.targetRepsMax)
        targetRIR = programExercise.targetRIR ?? 2
        restSeconds = programExercise.restSeconds
        intensityTechnique = programExercise.intensityTechnique ?? ""
        videoURLString = programExercise.videoURLString ?? ""
        substitutionOption1Name = programExercise.substitutionOption1Name ?? ""
        substitutionOption1URLString = programExercise.substitutionOption1URLString ?? ""
        substitutionOption2Name = programExercise.substitutionOption2Name ?? ""
        substitutionOption2URLString = programExercise.substitutionOption2URLString ?? ""
        notes = programExercise.notes ?? ""
        warmupSets = programExercise.warmupSets
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { WarmupSetDraft(warmupSet: $0) }
    }

    var isValid: Bool {
        exerciseID != nil
            && targetSets > 0
            && targetRepsMin > 0
            && targetRepsMax >= targetRepsMin
            && restSeconds > 0
    }

    static func empty(orderIndex: Int) -> ProgramExerciseDraft {
        ProgramExerciseDraft(
            sourceID: nil,
            exerciseID: nil,
            preferredExerciseID: nil,
            targetSets: 2,
            targetRepsMin: 8,
            targetRepsMax: 12,
            targetRIR: 2,
            restSeconds: 120,
            intensityTechnique: "",
            videoURLString: "",
            substitutionOption1Name: "",
            substitutionOption1URLString: "",
            substitutionOption2Name: "",
            substitutionOption2URLString: "",
            notes: "",
            warmupSets: []
        )
    }
}

private struct WarmupSetDraft {
    var orderIndex: Int
    var percentOfWorkWeight: Double?
    var fixedWeightLb: Double?
    var reps: Int
    var notes: String

    init(warmupSet: WarmupSet) {
        orderIndex = warmupSet.orderIndex
        percentOfWorkWeight = warmupSet.percentOfWorkWeight
        fixedWeightLb = warmupSet.fixedWeightLb
        reps = warmupSet.reps
        notes = warmupSet.notes ?? ""
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
