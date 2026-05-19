import Foundation
@preconcurrency import WatchConnectivity

private struct WatchMessageEnvelope: @unchecked Sendable {
    let message: [String: Any]
}

@MainActor
final class WatchWorkoutViewModel: NSObject, ObservableObject {
    @Published var workout: WatchActiveWorkoutSnapshot?
    @Published var statusText = "Open Iron on iPhone and start a workout."
    @Published var selectedExerciseIndex = 0
    @Published var reps = 8
    @Published var weightLb: Double?
    @Published var rir = 2
    @Published var side: String?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    override init() {
        super.init()
        configureSession()
    }

    var selectedExercise: WatchExerciseSnapshot? {
        guard let exercises = workout?.exercises, exercises.indices.contains(selectedExerciseIndex) else {
            return nil
        }
        return exercises[selectedExerciseIndex]
    }

    var nextOrderIndex: Int {
        guard let selectedExercise else { return 0 }
        if selectedExercise.isUnilateral {
            let sideValue = side ?? "left"
            let sideSets = selectedExercise.loggedSets.filter { $0.side == sideValue }
            return min(selectedExercise.targetSets - 1, sideSets.count)
        }
        return min(selectedExercise.targetSets - 1, selectedExercise.loggedSets.count)
    }

    func refresh() {
        guard WCSession.isSupported() else {
            statusText = "WatchConnectivity is not available."
            return
        }

        let message: [String: Any] = ["type": WatchWorkoutMessageType.requestActiveWorkout]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message) { [weak self] reply in
                Task { @MainActor in
                    self?.handle(reply)
                }
            } errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.statusText = "Could not reach iPhone. Open Iron on iPhone."
                }
            }
        } else {
            statusText = "Open Iron on iPhone to sync the active workout."
        }
    }

    func selectExercise(_ exercise: WatchExerciseSnapshot) {
        guard let index = workout?.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        selectedExerciseIndex = index
        applyDefaults(for: exercise)
    }

    func adjustReps(by amount: Int) {
        reps = max(1, reps + amount)
    }

    func adjustWeight(by amount: Double) {
        let current = weightLb ?? 0
        let updated = max(0, current + amount)
        weightLb = updated == 0 ? nil : updated
    }

    func logSet() {
        guard let workout, let selectedExercise else { return }
        let request = WatchLogSetRequest(
            workoutId: workout.workoutId,
            programExerciseId: selectedExercise.programExerciseId,
            orderIndex: nextOrderIndex,
            side: selectedExercise.isUnilateral ? (side ?? "left") : nil,
            reps: reps,
            weightLb: weightLb,
            rir: rir
        )

        guard let payload = try? encoder.encode(request) else { return }
        let message: [String: Any] = [
            "type": WatchWorkoutMessageType.logSet,
            "payload": payload,
        ]

        statusText = "Logging set..."
        WCSession.default.sendMessage(message) { [weak self] reply in
            Task { @MainActor in
                self?.handle(reply)
            }
        } errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.statusText = "Could not send set to iPhone."
            }
        }
    }

    private func configureSession() {
        guard WCSession.isSupported() else {
            statusText = "WatchConnectivity is not available."
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func handle(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case WatchWorkoutMessageType.activeWorkout:
            guard let data = message["payload"] as? Data,
                  let snapshot = try? decoder.decode(WatchActiveWorkoutSnapshot.self, from: data) else {
                statusText = "Could not read workout from iPhone."
                return
            }
            workout = snapshot
            selectedExerciseIndex = min(selectedExerciseIndex, max(0, snapshot.exercises.count - 1))
            if let selectedExercise {
                applyDefaults(for: selectedExercise)
            }
            statusText = "Synced"

        case WatchWorkoutMessageType.noActiveWorkout:
            workout = nil
            statusText = "Start a workout on iPhone."

        case WatchWorkoutMessageType.error:
            statusText = (message["message"] as? String) ?? "Watch sync error."

        default:
            break
        }
    }

    private func applyDefaults(for exercise: WatchExerciseSnapshot) {
        reps = exercise.targetRepsMin
        rir = exercise.targetRIR ?? 2
        if exercise.isUnilateral {
            side = side ?? "left"
        } else {
            side = nil
        }
    }
}

extension WatchWorkoutViewModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            WatchWorkoutViewModel.findActiveInstance()?.refresh()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let envelope = WatchMessageEnvelope(message: applicationContext)
        Task { @MainActor in
            WatchWorkoutViewModel.findActiveInstance()?.handle(envelope.message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let envelope = WatchMessageEnvelope(message: message)
        Task { @MainActor in
            WatchWorkoutViewModel.findActiveInstance()?.handle(envelope.message)
        }
    }

    private static weak var activeInstance: WatchWorkoutViewModel?

    private static func findActiveInstance() -> WatchWorkoutViewModel? {
        activeInstance
    }

    func markActiveForConnectivityCallbacks() {
        Self.activeInstance = self
    }
}
