import Foundation
import SwiftData

@Model
final class WarmupSet {
    var id: UUID = UUID()
    var orderIndex: Int = 0
    var percentOfWorkWeight: Double?
    var fixedWeightLb: Double?
    var reps: Int = 5
    var notes: String?
    var programExercise: ProgramExercise?

    init(
        id: UUID = UUID(),
        orderIndex: Int = 0,
        percentOfWorkWeight: Double? = nil,
        fixedWeightLb: Double? = nil,
        reps: Int = 5,
        notes: String? = nil,
        programExercise: ProgramExercise? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.percentOfWorkWeight = percentOfWorkWeight
        self.fixedWeightLb = fixedWeightLb
        self.reps = reps
        self.notes = notes
        self.programExercise = programExercise
    }
}
