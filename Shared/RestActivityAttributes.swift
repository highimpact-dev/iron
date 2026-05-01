import ActivityKit
import Foundation

struct RestActivityAttributes: ActivityAttributes {
    typealias ContentState = RestState

    struct RestState: Codable, Hashable {
        var startedAt: Date
        var endsAt: Date
        var totalSeconds: Int
    }

    var exerciseName: String
}
