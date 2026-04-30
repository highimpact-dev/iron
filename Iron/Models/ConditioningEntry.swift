import Foundation
import SwiftData

@Model
final class ConditioningEntry {
    var id: UUID = UUID()
    var orderIndex: Int = 0
    var modality: ConditioningModality = ConditioningModality.run
    var durationSeconds: Int = 0
    var distanceMeters: Double?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var caloriesActive: Int?
    var rpe: Double?
    var notes: String?
    var healthKitWorkoutUUID: UUID?
    var completedAt: Date = Date()
    var workout: Workout?

    init(
        id: UUID = UUID(),
        orderIndex: Int = 0,
        modality: ConditioningModality = .run,
        durationSeconds: Int = 0,
        distanceMeters: Double? = nil,
        avgHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        caloriesActive: Int? = nil,
        rpe: Double? = nil,
        notes: String? = nil,
        healthKitWorkoutUUID: UUID? = nil,
        completedAt: Date = Date(),
        workout: Workout? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.modality = modality
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.caloriesActive = caloriesActive
        self.rpe = rpe
        self.notes = notes
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.completedAt = completedAt
        self.workout = workout
    }
}
