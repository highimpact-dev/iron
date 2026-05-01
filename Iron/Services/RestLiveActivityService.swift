@preconcurrency import ActivityKit
import Foundation

@MainActor
enum RestLiveActivityService {
    private static var current: Activity<RestActivityAttributes>?

    static func start(startedAt: Date, endsAt: Date, totalSeconds: Int, exerciseName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task { await endCurrent() }
        do {
            let attributes = RestActivityAttributes(exerciseName: exerciseName)
            let state = RestActivityAttributes.RestState(
                startedAt: startedAt,
                endsAt: endsAt,
                totalSeconds: totalSeconds
            )
            let content = ActivityContent(
                state: state,
                staleDate: endsAt.addingTimeInterval(60)
            )
            current = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            #if DEBUG
            print("[RestLiveActivity] start failed: \(error)")
            #endif
        }
    }

    static func update(startedAt: Date, endsAt: Date, totalSeconds: Int) {
        guard let activity = current else { return }
        let state = RestActivityAttributes.RestState(
            startedAt: startedAt,
            endsAt: endsAt,
            totalSeconds: totalSeconds
        )
        let content = ActivityContent(
            state: state,
            staleDate: endsAt.addingTimeInterval(60)
        )
        Task { await activity.update(content) }
    }

    static func end() {
        guard let activity = current else { return }
        current = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private static func endCurrent() async {
        guard let activity = current else { return }
        current = nil
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
