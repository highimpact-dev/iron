import Foundation

struct WatchActiveWorkoutSnapshot: Codable {
    var workoutId: UUID
    var workoutName: String
    var programName: String?
    var startedAt: Date
    var exercises: [WatchExerciseSnapshot]
}

struct WatchExerciseSnapshot: Codable, Identifiable {
    var id: UUID { programExerciseId }

    var programExerciseId: UUID
    var exerciseName: String
    var orderIndex: Int
    var targetSets: Int
    var targetRepsMin: Int
    var targetRepsMax: Int
    var targetRIR: Int?
    var isUnilateral: Bool
    var loggedSets: [WatchSetSnapshot]
}

struct WatchSetSnapshot: Codable, Identifiable {
    var id: UUID
    var orderIndex: Int
    var reps: Int
    var weightLb: Double?
    var rir: Int?
    var side: String?
}

struct WatchLogSetRequest: Codable {
    var workoutId: UUID
    var programExerciseId: UUID
    var orderIndex: Int
    var side: String?
    var reps: Int
    var weightLb: Double?
    var rir: Int?
}

enum WatchWorkoutMessageType {
    static let requestActiveWorkout = "requestActiveWorkout"
    static let activeWorkout = "activeWorkout"
    static let logSet = "logSet"
    static let noActiveWorkout = "noActiveWorkout"
    static let error = "error"
}

