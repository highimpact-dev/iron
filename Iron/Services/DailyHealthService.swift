import Foundation
import SwiftData

@MainActor
enum DailyHealthService {
    static func refreshRecentSnapshots(context: ModelContext, days: Int = 60) async throws -> Int {
        let inputs = try await HealthKitService.shared.fetchDailyHealthInputs(days: days)
        guard !inputs.isEmpty else { return 0 }

        let scoredInputs = DailyHealthCalculator.scoredInputs(inputs)
        let calendar = Calendar.current
        let start = scoredInputs.first?.0.dayStart ?? calendar.startOfDay(for: Date())
        let existingDescriptor = FetchDescriptor<DailyHealthSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.dayStart >= start
            }
        )
        let existing = try context.fetch(existingDescriptor)
        var snapshotsByDay = Dictionary(uniqueKeysWithValues: existing.map { ($0.dayStart, $0) })

        for (input, scores) in scoredInputs {
            let day = calendar.startOfDay(for: input.dayStart)
            let snapshot = snapshotsByDay[day] ?? DailyHealthSnapshot(dayStart: day)
            snapshot.apply(input: input, scores: scores)
            if snapshotsByDay[day] == nil {
                context.insert(snapshot)
                snapshotsByDay[day] = snapshot
            }
        }

        try context.save()
        return scoredInputs.count
    }
}
