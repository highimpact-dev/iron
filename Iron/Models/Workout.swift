import Foundation
import SwiftData

@Model
final class Workout {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var finishedAt: Date?
    var name: String?
    var notes: String?
    var bodyweightLb: Double?
    var rpeOverall: Double?
    var sourceProgram: Program?
    var sourceProgramDay: ProgramDay?
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.workout)
    var setEntries: [SetEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ConditioningEntry.workout)
    var conditioningEntries: [ConditioningEntry] = []

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        name: String? = nil,
        notes: String? = nil,
        bodyweightLb: Double? = nil,
        rpeOverall: Double? = nil,
        sourceProgram: Program? = nil,
        sourceProgramDay: ProgramDay? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.name = name
        self.notes = notes
        self.bodyweightLb = bodyweightLb
        self.rpeOverall = rpeOverall
        self.sourceProgram = sourceProgram
        self.sourceProgramDay = sourceProgramDay
        self.deletedAt = deletedAt
    }
}
