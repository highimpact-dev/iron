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
    var daysPerWeek: Int?
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
        daysPerWeek: Int? = nil,
        createdAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.programDescription = programDescription
        self.isBuiltIn = isBuiltIn
        self.weeksLength = weeksLength
        self.daysPerWeek = daysPerWeek
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

@Model
final class ProgramDay {
    var id: UUID = UUID()
    var name: String = ""
    var weekIndex: Int?
    var phaseIndex: Int?
    var phaseName: String?
    var dayIndex: Int = 0
    var notes: String?
    var program: Program?

    @Relationship(deleteRule: .cascade, inverse: \ProgramExercise.programDay)
    var exercises: [ProgramExercise] = []

    init(
        id: UUID = UUID(),
        name: String,
        weekIndex: Int? = nil,
        phaseIndex: Int? = nil,
        phaseName: String? = nil,
        dayIndex: Int = 0,
        notes: String? = nil,
        program: Program? = nil
    ) {
        self.id = id
        self.name = name
        self.weekIndex = weekIndex
        self.phaseIndex = phaseIndex
        self.phaseName = phaseName
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
    var targetRIR: Int?
    var earlySetTargetRPE: String?
    var lastSetTargetRPE: String?
    var targetPercent1RM: Double?
    var restSeconds: Int = 90
    var intensityTechnique: String?
    var videoURLString: String?
    var substitutionOption1Name: String?
    var substitutionOption1URLString: String?
    var substitutionOption2Name: String?
    var substitutionOption2URLString: String?
    var notes: String?
    var exercise: Exercise?
    var preferredExercise: Exercise?
    var programDay: ProgramDay?

    @Relationship(deleteRule: .cascade, inverse: \WarmupSet.programExercise)
    var warmupSets: [WarmupSet] = []

    init(
        id: UUID = UUID(),
        orderIndex: Int = 0,
        targetSets: Int,
        targetRepsMin: Int,
        targetRepsMax: Int,
        targetRPE: Double? = nil,
        targetRIR: Int? = nil,
        earlySetTargetRPE: String? = nil,
        lastSetTargetRPE: String? = nil,
        targetPercent1RM: Double? = nil,
        restSeconds: Int = 90,
        intensityTechnique: String? = nil,
        videoURLString: String? = nil,
        substitutionOption1Name: String? = nil,
        substitutionOption1URLString: String? = nil,
        substitutionOption2Name: String? = nil,
        substitutionOption2URLString: String? = nil,
        notes: String? = nil,
        exercise: Exercise? = nil,
        preferredExercise: Exercise? = nil,
        programDay: ProgramDay? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.targetRepsMin = targetRepsMin
        self.targetRepsMax = targetRepsMax
        self.targetRPE = targetRPE
        self.targetRIR = targetRIR
        self.earlySetTargetRPE = earlySetTargetRPE
        self.lastSetTargetRPE = lastSetTargetRPE
        self.targetPercent1RM = targetPercent1RM
        self.restSeconds = restSeconds
        self.intensityTechnique = intensityTechnique
        self.videoURLString = videoURLString
        self.substitutionOption1Name = substitutionOption1Name
        self.substitutionOption1URLString = substitutionOption1URLString
        self.substitutionOption2Name = substitutionOption2Name
        self.substitutionOption2URLString = substitutionOption2URLString
        self.notes = notes
        self.exercise = exercise
        self.preferredExercise = preferredExercise
        self.programDay = programDay
    }
}
