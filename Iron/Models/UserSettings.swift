import Foundation
import SwiftData

@Model
final class UserSettings {
    var id: UUID = UUID()
    var weightUnit: WeightUnit = WeightUnit.lb
    var distanceUnit: DistanceUnit = DistanceUnit.miles
    var defaultRestSeconds: Int = 90
    var plateConfigLb: [Double] = [45, 35, 25, 10, 5, 2.5]
    var plateConfigKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    var hapticFeedback: Bool = true
    var watchAutoPause: Bool = true
    var firstDayOfWeek: Int = 2
    var bodyweightSource: BodyweightSource = BodyweightSource.healthKit

    init(
        id: UUID = UUID(),
        weightUnit: WeightUnit = .lb,
        distanceUnit: DistanceUnit = .miles,
        defaultRestSeconds: Int = 90,
        plateConfigLb: [Double] = [45, 35, 25, 10, 5, 2.5],
        plateConfigKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25],
        hapticFeedback: Bool = true,
        watchAutoPause: Bool = true,
        firstDayOfWeek: Int = 2,
        bodyweightSource: BodyweightSource = .healthKit
    ) {
        self.id = id
        self.weightUnit = weightUnit
        self.distanceUnit = distanceUnit
        self.defaultRestSeconds = defaultRestSeconds
        self.plateConfigLb = plateConfigLb
        self.plateConfigKg = plateConfigKg
        self.hapticFeedback = hapticFeedback
        self.watchAutoPause = watchAutoPause
        self.firstDayOfWeek = firstDayOfWeek
        self.bodyweightSource = bodyweightSource
    }
}
