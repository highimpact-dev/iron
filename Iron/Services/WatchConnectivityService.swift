import Foundation
import SwiftData
@preconcurrency import WatchConnectivity

private struct WatchPhoneMessageEnvelope: @unchecked Sendable {
    let message: [String: Any]
    let replyHandler: ([String: Any]) -> Void
}

@MainActor
final class WatchConnectivityService: NSObject {
    static let shared = WatchConnectivityService()

    private var modelContext: ModelContext?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private override init() {
        super.init()
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publishActiveWorkoutIfAvailable() {
        guard let snapshot = activeWorkoutSnapshot() else { return }
        publish(snapshot)
    }

    func publish(_ snapshot: WatchActiveWorkoutSnapshot) {
        guard WCSession.isSupported() else { return }
        guard let data = try? encoder.encode(snapshot) else { return }

        let message: [String: Any] = [
            "type": WatchWorkoutMessageType.activeWorkout,
            "payload": data,
        ]

        try? WCSession.default.updateApplicationContext(message)

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        }
    }

    func publishNoActiveWorkout() {
        guard WCSession.isSupported() else { return }
        let message: [String: Any] = ["type": WatchWorkoutMessageType.noActiveWorkout]
        try? WCSession.default.updateApplicationContext(message)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        }
    }

    private func handleMessage(_ message: [String: Any]) -> [String: Any] {
        guard let type = message["type"] as? String else {
            return errorReply("Missing message type.")
        }

        switch type {
        case WatchWorkoutMessageType.requestActiveWorkout:
            guard let snapshot = activeWorkoutSnapshot(),
                  let data = try? encoder.encode(snapshot) else {
                return ["type": WatchWorkoutMessageType.noActiveWorkout]
            }
            return [
                "type": WatchWorkoutMessageType.activeWorkout,
                "payload": data,
            ]

        case WatchWorkoutMessageType.logSet:
            guard let data = message["payload"] as? Data,
                  let request = try? decoder.decode(WatchLogSetRequest.self, from: data) else {
                return errorReply("Could not decode set log.")
            }
            return logSet(request)

        default:
            return errorReply("Unsupported message type.")
        }
    }

    private func activeWorkoutSnapshot() -> WatchActiveWorkoutSnapshot? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.finishedAt == nil && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let workout = try? modelContext.fetch(descriptor).first else { return nil }
        return snapshot(for: workout)
    }

    private func snapshot(for workout: Workout) -> WatchActiveWorkoutSnapshot {
        let programExercises = ((workout.sourceProgramDay?.exercises ?? []) + workout.additionalExercises)
            .sorted { $0.orderIndex < $1.orderIndex }

        let exerciseSnapshots = programExercises.compactMap { programExercise -> WatchExerciseSnapshot? in
            let exercise = programExercise.preferredExercise ?? programExercise.exercise
            guard let exercise else { return nil }
            let loggedSets = workout.setEntries
                .filter { $0.exerciseOrderIndex == programExercise.orderIndex }
                .filter { $0.setType != .warmup }
                .sorted { lhs, rhs in
                    if lhs.orderIndex != rhs.orderIndex { return lhs.orderIndex < rhs.orderIndex }
                    return (lhs.side?.rawValue ?? "") < (rhs.side?.rawValue ?? "")
                }
                .map {
                    WatchSetSnapshot(
                        id: $0.id,
                        orderIndex: $0.orderIndex,
                        reps: $0.reps,
                        weightLb: $0.weightLb,
                        rir: $0.rir,
                        side: $0.side?.rawValue
                    )
                }

            return WatchExerciseSnapshot(
                programExerciseId: programExercise.id,
                exerciseName: exercise.name,
                orderIndex: programExercise.orderIndex,
                targetSets: programExercise.targetSets,
                targetRepsMin: programExercise.targetRepsMin,
                targetRepsMax: programExercise.targetRepsMax,
                targetRIR: programExercise.targetRIR,
                isUnilateral: exercise.isUnilateral,
                loggedSets: loggedSets
            )
        }

        return WatchActiveWorkoutSnapshot(
            workoutId: workout.id,
            workoutName: workout.name ?? "Workout",
            programName: workout.sourceProgram?.name,
            startedAt: workout.startedAt,
            exercises: exerciseSnapshots
        )
    }

    private func logSet(_ request: WatchLogSetRequest) -> [String: Any] {
        guard let modelContext else { return errorReply("Phone database is unavailable.") }

        let workoutId = request.workoutId
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.id == workoutId && $0.finishedAt == nil && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1

        guard let workout = try? modelContext.fetch(descriptor).first else {
            return errorReply("No active workout found.")
        }

        let programExercises = (workout.sourceProgramDay?.exercises ?? []) + workout.additionalExercises
        guard let programExercise = programExercises.first(where: { $0.id == request.programExerciseId }),
              let exercise = programExercise.preferredExercise ?? programExercise.exercise else {
            return errorReply("Exercise is no longer available.")
        }

        let side = request.side.flatMap(SetSide.init(rawValue:))
        let existing = workout.setEntries.first {
            $0.exerciseOrderIndex == programExercise.orderIndex
                && $0.orderIndex == request.orderIndex
                && $0.side == side
                && $0.setType != .warmup
        }

        if let existing {
            existing.reps = request.reps
            existing.weightLb = request.weightLb
            existing.rir = request.rir
            existing.completedAt = Date()
        } else {
            let entry = SetEntry(
                orderIndex: request.orderIndex,
                exerciseOrderIndex: programExercise.orderIndex,
                setType: .working,
                reps: request.reps,
                weightLb: request.weightLb,
                rir: request.rir,
                side: side,
                workout: workout,
                exercise: exercise
            )
            modelContext.insert(entry)
        }

        try? modelContext.save()

        guard let snapshot = activeWorkoutSnapshot(),
              let data = try? encoder.encode(snapshot) else {
            return ["type": WatchWorkoutMessageType.noActiveWorkout]
        }
        publish(snapshot)
        return [
            "type": WatchWorkoutMessageType.activeWorkout,
            "payload": data,
        ]
    }

    private func errorReply(_ message: String) -> [String: Any] {
        [
            "type": WatchWorkoutMessageType.error,
            "message": message,
        ]
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            WatchConnectivityService.shared.publishActiveWorkoutIfAvailable()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let envelope = WatchPhoneMessageEnvelope(message: message, replyHandler: replyHandler)
        Task { @MainActor in
            let reply = WatchConnectivityService.shared.handleMessage(envelope.message)
            envelope.replyHandler(reply)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
