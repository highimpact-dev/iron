import Foundation
import SwiftData

@Model
final class PersonalRecord {
    var id: UUID = UUID()
    var prType: PRType = PRType.oneRM
    var value: Double = 0
    var setEntry: SetEntry?
    var exercise: Exercise?
    var achievedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        prType: PRType,
        value: Double,
        setEntry: SetEntry? = nil,
        exercise: Exercise? = nil,
        achievedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.prType = prType
        self.value = value
        self.setEntry = setEntry
        self.exercise = exercise
        self.achievedAt = achievedAt
        self.deletedAt = deletedAt
    }
}
