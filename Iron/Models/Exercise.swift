import Foundation
import SwiftData

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var slug: String = ""
    var category: ExerciseCategory = ExerciseCategory.compound
    var movementPattern: MovementPattern = MovementPattern.push
    var primaryMuscles: [Muscle] = []
    var secondaryMuscles: [Muscle] = []
    var equipment: [Equipment] = []
    var instructions: String?
    var videoURL: URL?
    var progressionIncrementLb: Double = 5.0
    var isCustom: Bool = false
    var createdAt: Date = Date()
    var deletedAt: Date?

    @Relationship(inverse: \SetEntry.exercise)
    var setEntries: [SetEntry] = []

    init(
        id: UUID = UUID(),
        name: String,
        slug: String,
        category: ExerciseCategory,
        movementPattern: MovementPattern,
        primaryMuscles: [Muscle] = [],
        secondaryMuscles: [Muscle] = [],
        equipment: [Equipment] = [],
        instructions: String? = nil,
        videoURL: URL? = nil,
        progressionIncrementLb: Double = 5.0,
        isCustom: Bool = false,
        createdAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.category = category
        self.movementPattern = movementPattern
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.instructions = instructions
        self.videoURL = videoURL
        self.progressionIncrementLb = progressionIncrementLb
        self.isCustom = isCustom
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}
