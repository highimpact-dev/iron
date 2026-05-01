import Foundation

struct PlateLoad: Equatable {
    let weightLb: Double
    let countPerSide: Int
}

enum PlateCalculator {
    static let standardBarLb: Double = 45
    static let standardPlatesLb: [Double] = [45, 35, 25, 10, 5, 2.5]

    /// Compute per-side plate load. Returns nil when target ≤ bar weight or
    /// the remainder isn't loadable with the supplied plates.
    static func plates(
        targetLb: Double,
        barLb: Double = standardBarLb,
        availableLb: [Double] = standardPlatesLb
    ) -> [PlateLoad]? {
        guard targetLb > barLb else { return nil }
        let perSide = (targetLb - barLb) / 2
        guard perSide > 0 else { return nil }

        var remaining = perSide
        var loads: [PlateLoad] = []
        for plate in availableLb.sorted(by: >) {
            let count = Int((remaining / plate).rounded(.down))
            if count > 0 {
                loads.append(PlateLoad(weightLb: plate, countPerSide: count))
                remaining -= Double(count) * plate
            }
        }
        guard abs(remaining) < 0.01 else { return nil }
        return loads
    }

    /// Human-readable per-side breakdown, e.g. "45 + 25 + 2.5".
    static func breakdownText(for loads: [PlateLoad]) -> String {
        loads
            .flatMap { Array(repeating: $0.weightLb, count: $0.countPerSide) }
            .map(formatPlate)
            .joined(separator: " + ")
    }

    private static func formatPlate(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}
