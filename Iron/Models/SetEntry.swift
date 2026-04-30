import Foundation
import SwiftData

@Model
final class SetEntry {
    var id: UUID = UUID()
    var orderIndex: Int = 0
    var exerciseOrderIndex: Int = 0
    var setType: SetType = SetType.working
    var reps: Int = 0
    var weightLb: Double?
    var rpe: Double?
    var rir: Int?
    var restSeconds: Int?
    var notes: String?
    var completedAt: Date = Date()
    var workout: Workout?
    var exercise: Exercise?

    init(
        id: UUID = UUID(),
        orderIndex: Int = 0,
        exerciseOrderIndex: Int = 0,
        setType: SetType = .working,
        reps: Int = 0,
        weightLb: Double? = nil,
        rpe: Double? = nil,
        rir: Int? = nil,
        restSeconds: Int? = nil,
        notes: String? = nil,
        completedAt: Date = Date(),
        workout: Workout? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.exerciseOrderIndex = exerciseOrderIndex
        self.setType = setType
        self.reps = reps
        self.weightLb = weightLb
        self.rpe = rpe
        self.rir = rir
        self.restSeconds = restSeconds
        self.notes = notes
        self.completedAt = completedAt
        self.workout = workout
        self.exercise = exercise
    }
}
