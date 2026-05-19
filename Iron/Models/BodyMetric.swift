import Foundation
import SwiftData

@Model
final class BodyMetric {
    var id: UUID = UUID()
    var loggedAt: Date = Date()
    var bodyweightLb: Double?
    var bodyFatPercent: Double?
    var waistIn: Double?
    var chestIn: Double?
    var hipsIn: Double?
    var leftArmIn: Double?
    var rightArmIn: Double?
    var leftForearmIn: Double?
    var rightForearmIn: Double?
    var leftThighIn: Double?
    var rightThighIn: Double?
    var leftCalfIn: Double?
    var rightCalfIn: Double?
    var notes: String?
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        loggedAt: Date = Date(),
        bodyweightLb: Double? = nil,
        bodyFatPercent: Double? = nil,
        waistIn: Double? = nil,
        chestIn: Double? = nil,
        hipsIn: Double? = nil,
        leftArmIn: Double? = nil,
        rightArmIn: Double? = nil,
        leftForearmIn: Double? = nil,
        rightForearmIn: Double? = nil,
        leftThighIn: Double? = nil,
        rightThighIn: Double? = nil,
        leftCalfIn: Double? = nil,
        rightCalfIn: Double? = nil,
        notes: String? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.bodyweightLb = bodyweightLb
        self.bodyFatPercent = bodyFatPercent
        self.waistIn = waistIn
        self.chestIn = chestIn
        self.hipsIn = hipsIn
        self.leftArmIn = leftArmIn
        self.rightArmIn = rightArmIn
        self.leftForearmIn = leftForearmIn
        self.rightForearmIn = rightForearmIn
        self.leftThighIn = leftThighIn
        self.rightThighIn = rightThighIn
        self.leftCalfIn = leftCalfIn
        self.rightCalfIn = rightCalfIn
        self.notes = notes
        self.deletedAt = deletedAt
    }
}
