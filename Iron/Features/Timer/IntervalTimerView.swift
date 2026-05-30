import AVFoundation
import SwiftUI

struct IntervalTimerView: View {
    @AppStorage("intervalTimerWorkouts.v1") private var storedWorkouts = ""

    @State private var workouts: [IntervalWorkout] = []
    @State private var sheet: IntervalTimerSheet?
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            List {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No interval workouts",
                        systemImage: "timer",
                        description: Text("Add a timer workout with work, rest, and rounds.")
                    )
                } else {
                    Section("Interval Workouts") {
                        ForEach(workouts) { workout in
                            NavigationLink(value: workout.id) {
                                IntervalWorkoutRow(workout: workout)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(workout)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    sheet = .edit(workout.id)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Timer")
            .navigationDestination(for: UUID.self) { workoutID in
                if let workout = workouts.first(where: { $0.id == workoutID }) {
                    IntervalTimerSessionView(workout: workout)
                } else {
                    ContentUnavailableView("Workout missing", systemImage: "timer")
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        sheet = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create interval workout")
                }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .create:
                    IntervalWorkoutEditorView(mode: .create, workout: nil) { workout in
                        workouts.append(workout)
                        saveWorkouts()
                    }
                case .edit(let id):
                    if let workout = workouts.first(where: { $0.id == id }) {
                        IntervalWorkoutEditorView(mode: .edit, workout: workout) { updated in
                            if let index = workouts.firstIndex(where: { $0.id == updated.id }) {
                                workouts[index] = updated
                                saveWorkouts()
                            }
                        }
                    } else {
                        ContentUnavailableView("Workout missing", systemImage: "timer")
                    }
                }
            }
            .onAppear(perform: loadWorkoutsIfNeeded)
        }
    }

    private func loadWorkoutsIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let data = storedWorkouts.data(using: .utf8), !data.isEmpty else { return }
        workouts = (try? JSONDecoder().decode([IntervalWorkout].self, from: data)) ?? []
    }

    private func saveWorkouts() {
        guard let data = try? JSONEncoder().encode(workouts),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        storedWorkouts = string
    }

    private func delete(_ offsets: IndexSet) {
        workouts.remove(atOffsets: offsets)
        saveWorkouts()
    }

    private func delete(_ workout: IntervalWorkout) {
        workouts.removeAll { $0.id == workout.id }
        saveWorkouts()
    }
}

private enum IntervalTimerSheet: Identifiable {
    case create
    case edit(UUID)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let id): "edit-\(id.uuidString)"
        }
    }
}

private struct IntervalWorkout: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var exercises: [IntervalExercise]
    var createdAt: Date = Date()

    var totalSeconds: Int {
        IntervalSegment.segments(for: self).reduce(0) { $0 + $1.durationSeconds }
    }

    var totalRounds: Int {
        exercises.reduce(0) { $0 + $1.rounds }
    }
}

private struct IntervalExercise: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var workSeconds: Int
    var restSeconds: Int
    var rounds: Int
}

private enum IntervalEditorMode {
    case create
    case edit

    var title: String {
        switch self {
        case .create: "Create Timer"
        case .edit: "Edit Timer"
        }
    }

    var saveTitle: String {
        switch self {
        case .create: "Create"
        case .edit: "Save"
        }
    }
}

private struct IntervalWorkoutEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: IntervalEditorMode
    let onSave: (IntervalWorkout) -> Void

    @State private var draft: IntervalWorkoutDraft

    init(mode: IntervalEditorMode, workout: IntervalWorkout?, onSave: @escaping (IntervalWorkout) -> Void) {
        self.mode = mode
        self.onSave = onSave
        _draft = State(initialValue: IntervalWorkoutDraft(workout: workout))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Name", text: $draft.name)
                }

                Section("Summary") {
                    LabeledContent("Total time", value: formatClock(draft.totalSeconds))
                    LabeledContent("Total rounds", value: "\(draft.totalRounds)")
                }

                Section("Exercises") {
                    if draft.exercises.isEmpty {
                        ContentUnavailableView(
                            "No exercises",
                            systemImage: "figure.run",
                            description: Text("Add a walk, sprint, bike, row, or any interval.")
                        )
                    } else {
                        ForEach($draft.exercises) { $exercise in
                            IntervalExerciseEditorRow(exercise: $exercise)
                        }
                        .onDelete { offsets in
                            draft.exercises.remove(atOffsets: offsets)
                        }
                    }

                    Button {
                        draft.exercises.append(.empty)
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle")
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
                        onSave(draft.workout)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
    }
}

private struct IntervalExerciseEditorRow: View {
    @Binding var exercise: IntervalExerciseDraft

    var body: some View {
        DisclosureGroup {
            TextField("Exercise", text: $exercise.name)

            DurationInput(title: "Work", minutes: $exercise.workMinutes, seconds: $exercise.workRemainderSeconds)
            DurationInput(title: "Rest", minutes: $exercise.restMinutes, seconds: $exercise.restRemainderSeconds)

            Stepper(value: $exercise.rounds, in: 1...99) {
                LabeledContent("Rounds", value: "\(exercise.rounds)")
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.displayName)
                    .font(.body)
                Text("\(formatClock(exercise.workTotalSeconds)) work / \(formatClock(exercise.restTotalSeconds)) rest x \(exercise.rounds)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DurationInput: View {
    let title: String
    @Binding var minutes: Int
    @Binding var seconds: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TimeNumberField(value: $minutes, range: 0...180)
                Text("min")
                    .foregroundStyle(.secondary)
                TimeNumberField(value: $seconds, range: 0...59)
                Text("sec")
                    .foregroundStyle(.secondary)
            }
            .font(.body.monospacedDigit())
        }
    }
}

private struct TimeNumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        TextField("0", value: $value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: 54)
            .onChange(of: value) { _, newValue in
                value = min(max(newValue, range.lowerBound), range.upperBound)
            }
    }
}

private struct IntervalWorkoutRow: View {
    let workout: IntervalWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.name)
                .font(.headline)
            HStack(spacing: 10) {
                Label("\(workout.exercises.count) exercises", systemImage: "figure.run")
                Label("\(workout.totalRounds) rounds", systemImage: "repeat")
                Label(formatClock(workout.totalSeconds), systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct IntervalTimerSessionView: View {
    let workout: IntervalWorkout

    @AppStorage("intervalTimerVoiceIdentifier.v1") private var selectedVoiceIdentifier = ""

    @State private var segmentIndex = 0
    @State private var remainingSeconds = 0
    @State private var isRunning = false
    @State private var isComplete = false
    @State private var voiceCuesEnabled = true
    @State private var announcedSegmentIndex: Int?
    @State private var announcedHalfwaySegmentIndex: Int?
    @State private var didAnnounceCompletion = false
    @State private var cueSpeaker = IntervalCueSpeaker()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var segments: [IntervalSegment] {
        IntervalSegment.segments(for: workout)
    }

    private var currentSegment: IntervalSegment? {
        guard segments.indices.contains(segmentIndex) else { return nil }
        return segments[segmentIndex]
    }

    private var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted {
                if $0.language == $1.language { return $0.name < $1.name }
                return $0.language < $1.language
            }
    }

    private var selectedVoiceName: String {
        guard !selectedVoiceIdentifier.isEmpty,
              let voice = availableVoices.first(where: { $0.identifier == selectedVoiceIdentifier }) else {
            return "System"
        }
        return voice.name
    }

    var body: some View {
        VStack(spacing: 24) {
            if segments.isEmpty {
                ContentUnavailableView("No intervals", systemImage: "timer")
            } else if let currentSegment {
                Spacer(minLength: 12)

                VStack(spacing: 8) {
                    Text(currentSegment.kind.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(currentSegment.kind.tint)
                    Text(currentSegment.exerciseName)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Round \(currentSegment.round) of \(currentSegment.totalRounds)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Total \(formatClock(workout.totalSeconds))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        voiceCuesEnabled.toggle()
                        if !voiceCuesEnabled {
                            cueSpeaker.stop()
                        }
                    } label: {
                        Label(
                            voiceCuesEnabled ? "Voice cues on" : "Voice cues off",
                            systemImage: voiceCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
                        )
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    HStack(spacing: 8) {
                        Menu {
                            Button {
                                selectedVoiceIdentifier = ""
                            } label: {
                                if selectedVoiceIdentifier.isEmpty {
                                    Label("System Default", systemImage: "checkmark")
                                } else {
                                    Text("System Default")
                                }
                            }

                            ForEach(availableVoices, id: \.identifier) { voice in
                                Button {
                                    selectedVoiceIdentifier = voice.identifier
                                } label: {
                                    let title = voiceMenuTitle(voice)
                                    if selectedVoiceIdentifier == voice.identifier {
                                        Label(title, systemImage: "checkmark")
                                    } else {
                                        Text(title)
                                    }
                                }
                            }
                        } label: {
                            Label("Voice: \(selectedVoiceName)", systemImage: "person.wave.2")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            cueSpeaker.speak("Voice preview.", voiceIdentifier: selectedVoiceIdentifier)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Preview voice")
                    }
                }

                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 18)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(currentSegment.kind.tint, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(formatClock(remainingSeconds))
                        .font(.system(size: 58, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: 260)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(currentSegment.kind.label), \(currentSegment.exerciseName), \(formatClock(remainingSeconds)) remaining")

                HStack(spacing: 14) {
                    TimerControlButton(systemName: "backward.end.fill", accessibilityLabel: "Previous interval") {
                        previousSegment()
                    }
                    TimerControlButton(systemName: isRunning ? "pause.fill" : "play.fill", accessibilityLabel: isRunning ? "Pause" : "Start") {
                        toggleRunning()
                    }
                    .controlSize(.large)
                    TimerControlButton(systemName: "forward.end.fill", accessibilityLabel: "Next interval") {
                        advanceSegment()
                    }
                    TimerControlButton(systemName: "arrow.counterclockwise", accessibilityLabel: "Reset timer") {
                        resetSession()
                    }
                }

                ProgressView(value: Double(segmentIndex + 1), total: Double(segments.count))
                    .padding(.horizontal)

                List {
                    Section("Plan") {
                        ForEach(workout.exercises) { exercise in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exercise.name)
                                    Text("\(formatClock(exercise.workSeconds)) work / \(formatClock(exercise.restSeconds)) rest")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(exercise.rounds)x")
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .frame(minHeight: 180)
            }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: resetSessionIfNeeded)
        .onReceive(timer) { _ in
            tick()
        }
    }

    private var progress: Double {
        guard let currentSegment, currentSegment.durationSeconds > 0 else { return 0 }
        let elapsed = currentSegment.durationSeconds - remainingSeconds
        return min(max(Double(elapsed) / Double(currentSegment.durationSeconds), 0), 1)
    }

    private func resetSessionIfNeeded() {
        guard remainingSeconds == 0 else { return }
        resetSession()
    }

    private func resetSession() {
        segmentIndex = 0
        remainingSeconds = segments.first?.durationSeconds ?? 0
        isRunning = false
        isComplete = false
        announcedSegmentIndex = nil
        announcedHalfwaySegmentIndex = nil
        didAnnounceCompletion = false
        cueSpeaker.stop()
    }

    private func tick() {
        guard isRunning, !isComplete else { return }
        if remainingSeconds > 1 {
            remainingSeconds -= 1
            announceHalfwayIfNeeded()
        } else {
            advanceSegment()
        }
    }

    private func toggleRunning() {
        if isComplete {
            resetSession()
            isRunning = true
            announceCurrentSegmentIfNeeded()
        } else {
            isRunning.toggle()
            if isRunning {
                announceCurrentSegmentIfNeeded()
            } else {
                cueSpeaker.stop()
            }
        }
    }

    private func advanceSegment() {
        guard !segments.isEmpty else { return }
        if segmentIndex + 1 < segments.count {
            segmentIndex += 1
            remainingSeconds = segments[segmentIndex].durationSeconds
            isComplete = false
            announcedHalfwaySegmentIndex = nil
            if isRunning {
                announceCurrentSegmentIfNeeded()
            }
        } else {
            remainingSeconds = 0
            isRunning = false
            isComplete = true
            announceCompletionIfNeeded()
        }
    }

    private func previousSegment() {
        guard !segments.isEmpty else { return }
        if segmentIndex > 0 {
            segmentIndex -= 1
        }
        remainingSeconds = segments[segmentIndex].durationSeconds
        isComplete = false
        announcedSegmentIndex = nil
        announcedHalfwaySegmentIndex = nil
        didAnnounceCompletion = false
    }

    private func announceCurrentSegmentIfNeeded() {
        guard voiceCuesEnabled,
              announcedSegmentIndex != segmentIndex,
              let currentSegment else {
            return
        }

        announcedSegmentIndex = segmentIndex
        switch currentSegment.kind {
        case .work:
            cueSpeaker.speak(
                "Start \(currentSegment.exerciseName). Round \(currentSegment.round).",
                voiceIdentifier: selectedVoiceIdentifier
            )
        case .rest:
            cueSpeaker.speak("Rest.", voiceIdentifier: selectedVoiceIdentifier)
        }
    }

    private func announceHalfwayIfNeeded() {
        guard voiceCuesEnabled,
              announcedHalfwaySegmentIndex != segmentIndex,
              let currentSegment,
              currentSegment.kind == .work,
              currentSegment.durationSeconds >= 4,
              remainingSeconds <= currentSegment.durationSeconds / 2 else {
            return
        }

        announcedHalfwaySegmentIndex = segmentIndex
        cueSpeaker.speak("Halfway.", voiceIdentifier: selectedVoiceIdentifier)
    }

    private func announceCompletionIfNeeded() {
        guard voiceCuesEnabled, !didAnnounceCompletion else { return }
        didAnnounceCompletion = true
        cueSpeaker.speak("Workout complete.", voiceIdentifier: selectedVoiceIdentifier)
    }

    private func voiceMenuTitle(_ voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) (\(voice.language))"
    }
}

@MainActor
private final class IntervalCueSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, voiceIdentifier: String) {
        configureAudioSession()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        if !voiceIdentifier.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
    }
}

private struct TimerControlButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct IntervalSegment: Identifiable {
    var id = UUID()
    var exerciseName: String
    var kind: IntervalSegmentKind
    var round: Int
    var totalRounds: Int
    var durationSeconds: Int

    static func segments(for workout: IntervalWorkout) -> [IntervalSegment] {
        workout.exercises.enumerated().flatMap { exerciseIndex, exercise in
            (1...exercise.rounds).flatMap { round in
                let isFinalRound = exerciseIndex == workout.exercises.count - 1 && round == exercise.rounds
                var roundSegments = [
                    IntervalSegment(
                        exerciseName: exercise.name,
                        kind: .work,
                        round: round,
                        totalRounds: exercise.rounds,
                        durationSeconds: exercise.workSeconds
                    )
                ]

                if exercise.restSeconds > 0 && !isFinalRound {
                    roundSegments.append(
                        IntervalSegment(
                            exerciseName: exercise.name,
                            kind: .rest,
                            round: round,
                            totalRounds: exercise.rounds,
                            durationSeconds: exercise.restSeconds
                        )
                    )
                }

                return roundSegments
            }
        }
    }
}

private enum IntervalSegmentKind {
    case work
    case rest

    var label: String {
        switch self {
        case .work: "Work"
        case .rest: "Rest"
        }
    }

    var tint: Color {
        switch self {
        case .work: .green
        case .rest: .blue
        }
    }
}

private struct IntervalWorkoutDraft: Equatable {
    var id: UUID
    var name: String
    var exercises: [IntervalExerciseDraft]
    var createdAt: Date

    init(workout: IntervalWorkout?) {
        if let workout {
            id = workout.id
            name = workout.name
            exercises = workout.exercises.map(IntervalExerciseDraft.init)
            createdAt = workout.createdAt
        } else {
            id = UUID()
            name = ""
            exercises = [.empty]
            createdAt = Date()
        }
    }

    var isValid: Bool {
        !trimmedName.isEmpty && exercises.allSatisfy(\.isValid)
    }

    var totalSeconds: Int {
        IntervalSegment.segments(for: workout).reduce(0) { $0 + $1.durationSeconds }
    }

    var totalRounds: Int {
        exercises.reduce(0) { $0 + $1.rounds }
    }

    var workout: IntervalWorkout {
        IntervalWorkout(
            id: id,
            name: trimmedName,
            exercises: exercises.map(\.exercise),
            createdAt: createdAt
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct IntervalExerciseDraft: Equatable, Identifiable {
    var id: UUID
    var name: String
    var workMinutes: Int
    var workRemainderSeconds: Int
    var restMinutes: Int
    var restRemainderSeconds: Int
    var rounds: Int

    static var empty: IntervalExerciseDraft {
        IntervalExerciseDraft(
            id: UUID(),
            name: "",
            workMinutes: 0,
            workRemainderSeconds: 30,
            restMinutes: 0,
            restRemainderSeconds: 30,
            rounds: 8
        )
    }

    init(_ exercise: IntervalExercise) {
        id = exercise.id
        name = exercise.name
        workMinutes = exercise.workSeconds / 60
        workRemainderSeconds = exercise.workSeconds % 60
        restMinutes = exercise.restSeconds / 60
        restRemainderSeconds = exercise.restSeconds % 60
        rounds = exercise.rounds
    }

    private init(
        id: UUID,
        name: String,
        workMinutes: Int,
        workRemainderSeconds: Int,
        restMinutes: Int,
        restRemainderSeconds: Int,
        rounds: Int
    ) {
        self.id = id
        self.name = name
        self.workMinutes = workMinutes
        self.workRemainderSeconds = workRemainderSeconds
        self.restMinutes = restMinutes
        self.restRemainderSeconds = restRemainderSeconds
        self.rounds = rounds
    }

    var displayName: String {
        trimmedName.isEmpty ? "Exercise" : trimmedName
    }

    var workTotalSeconds: Int {
        workMinutes * 60 + workRemainderSeconds
    }

    var restTotalSeconds: Int {
        restMinutes * 60 + restRemainderSeconds
    }

    var isValid: Bool {
        !trimmedName.isEmpty && workTotalSeconds > 0 && rounds > 0
    }

    var exercise: IntervalExercise {
        IntervalExercise(
            id: id,
            name: trimmedName,
            workSeconds: workTotalSeconds,
            restSeconds: restTotalSeconds,
            rounds: rounds
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func formatClock(_ seconds: Int) -> String {
    let safeSeconds = max(seconds, 0)
    let minutes = safeSeconds / 60
    let remainderSeconds = safeSeconds % 60
    return "\(minutes):\(String(format: "%02d", remainderSeconds))"
}

#Preview {
    IntervalTimerView()
}
