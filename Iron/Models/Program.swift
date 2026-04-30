import Foundation
import SwiftData

@Model
final class Program {
    var id: UUID = UUID()
    var name: String = ""
    var author: String?
    var programDescription: String?
    var isBuiltIn: Bool = false
    var weeksLength: Int?
    var createdAt: Date = Date()
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ProgramDay.program)
    var days: [ProgramDay] = []

    init(
        id: UUID = UUID(),
        name: String,
        author: String? = nil,
        programDescription: String? = nil,
        isBuiltIn: Bool = false,
        weeksLength: Int? = nil,
        createdAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.programDescription = programDescription
        self.isBuiltIn = isBuiltIn
        self.weeksLength = weeksLength
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

@Model
final class ProgramDay {
    var id: UUID = UUID()
    var name: String = ""
    var weekIndex: Int?
    var dayIndex: Int = 0
    var notes: String?
    var program: Program?

    @Relationship(deleteRule: .cascade, inverse: \ProgramExercise.programDay)
    var exercises: [ProgramExercise] = []

    init(
        id: UUID = UUID(),
        name: String,
        weekIndex: Int? = nil,
        dayIndex: Int = 0,
        notes: String? = nil,
        program: Program? = nil
    ) {
        self.id = id
        self.name = name
        self.weekIndex = weekIndex
        self.dayIndex = dayIndex
        self.notes = notes
        self.program = program
    }
}

@Model
final class ProgramExercise {
    var id: UUID = UUID()
    var orderIndex: Int = 0
    var targetSets: Int = 0
    var targetRepsMin: Int = 0
    var targetRepsMax: Int = 0
    var targetRPE: Double?
    var targetPercent1RM: Double?
    var restSeconds: Int = 90
    var notes: String?
    var exercise: Exercise?
    var programDay: ProgramDay?

    init(
        id: UUID = UUID(),
        orderIndex: Int = 0,
        targetSets: Int,
        targetRepsMin: Int,
        targetRepsMax: Int,
        targetRPE: Double? = nil,
        targetPercent1RM: Double? = nil,
        restSeconds: Int = 90,
        notes: String? = nil,
        exercise: Exercise? = nil,
        programDay: ProgramDay? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.targetRepsMin = targetRepsMin
        self.targetRepsMax = targetRepsMax
        self.targetRPE = targetRPE
        self.targetPercent1RM = targetPercent1RM
        self.restSeconds = restSeconds
        self.notes = notes
        self.exercise = exercise
        self.programDay = programDay
    }
}
