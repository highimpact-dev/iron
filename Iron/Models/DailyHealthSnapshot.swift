import Foundation
import SwiftData

@Model
final class DailyHealthSnapshot {
    var id: UUID = UUID()
    var dayStart: Date = Date()
    var importedAt: Date = Date()

    var sleepStart: Date?
    var sleepEnd: Date?
    var sleepDurationMinutes: Double?
    var timeInBedMinutes: Double?
    var sleepEfficiency: Double?

    var hrvMs: Double?
    var hrvBaselineMs: Double?
    var restingHeartRate: Double?
    var restingHeartRateBaseline: Double?
    var respiratoryRate: Double?
    var oxygenSaturationPercent: Double?
    var wristTemperatureCelsius: Double?
    var vo2Max: Double?

    var steps: Double?
    var activeEnergyKcal: Double?
    var restingEnergyKcal: Double?
    var exerciseMinutes: Double?
    var workoutCount: Int = 0
    var strainBaseline: Double?

    var recoveryScore: Int?
    var sleepScore: Int?
    var strainScore: Int?
    var trainingReadiness: String?

    init(
        id: UUID = UUID(),
        dayStart: Date,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.dayStart = dayStart
        self.importedAt = importedAt
    }

    func apply(input: DailyHealthInput, scores: DailyHealthScores) {
        dayStart = input.dayStart
        importedAt = Date()
        sleepStart = input.sleepStart
        sleepEnd = input.sleepEnd
        sleepDurationMinutes = input.sleepDurationMinutes
        timeInBedMinutes = input.timeInBedMinutes
        sleepEfficiency = input.sleepEfficiency
        hrvMs = input.hrvMs
        restingHeartRate = input.restingHeartRate
        respiratoryRate = input.respiratoryRate
        oxygenSaturationPercent = input.oxygenSaturationPercent
        wristTemperatureCelsius = input.wristTemperatureCelsius
        vo2Max = input.vo2Max
        steps = input.steps
        activeEnergyKcal = input.activeEnergyKcal
        restingEnergyKcal = input.restingEnergyKcal
        exerciseMinutes = input.exerciseMinutes
        workoutCount = input.workoutCount
        hrvBaselineMs = scores.hrvBaselineMs
        restingHeartRateBaseline = scores.restingHeartRateBaseline
        strainBaseline = scores.strainBaseline
        recoveryScore = scores.recoveryScore
        sleepScore = scores.sleepScore
        strainScore = scores.strainScore
        trainingReadiness = scores.trainingReadiness
    }
}

struct DailyHealthInput: Equatable, Identifiable {
    var id: Date { dayStart }
    var dayStart: Date
    var sleepStart: Date?
    var sleepEnd: Date?
    var sleepDurationMinutes: Double?
    var timeInBedMinutes: Double?
    var hrvMs: Double?
    var restingHeartRate: Double?
    var respiratoryRate: Double?
    var oxygenSaturationPercent: Double?
    var wristTemperatureCelsius: Double?
    var vo2Max: Double?
    var steps: Double?
    var activeEnergyKcal: Double?
    var restingEnergyKcal: Double?
    var exerciseMinutes: Double?
    var workoutCount: Int

    init(
        dayStart: Date,
        sleepStart: Date? = nil,
        sleepEnd: Date? = nil,
        sleepDurationMinutes: Double? = nil,
        timeInBedMinutes: Double? = nil,
        hrvMs: Double? = nil,
        restingHeartRate: Double? = nil,
        respiratoryRate: Double? = nil,
        oxygenSaturationPercent: Double? = nil,
        wristTemperatureCelsius: Double? = nil,
        vo2Max: Double? = nil,
        steps: Double? = nil,
        activeEnergyKcal: Double? = nil,
        restingEnergyKcal: Double? = nil,
        exerciseMinutes: Double? = nil,
        workoutCount: Int = 0
    ) {
        self.dayStart = Calendar.current.startOfDay(for: dayStart)
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.sleepDurationMinutes = sleepDurationMinutes
        self.timeInBedMinutes = timeInBedMinutes
        self.hrvMs = hrvMs
        self.restingHeartRate = restingHeartRate
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturationPercent = oxygenSaturationPercent
        self.wristTemperatureCelsius = wristTemperatureCelsius
        self.vo2Max = vo2Max
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.restingEnergyKcal = restingEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.workoutCount = workoutCount
    }

    var sleepEfficiency: Double? {
        guard let sleepDurationMinutes, let timeInBedMinutes, timeInBedMinutes > 0 else { return nil }
        return min(max(sleepDurationMinutes / timeInBedMinutes, 0), 1)
    }
}

struct DailyHealthScores: Equatable {
    var recoveryScore: Int?
    var sleepScore: Int?
    var strainScore: Int?
    var hrvBaselineMs: Double?
    var restingHeartRateBaseline: Double?
    var strainBaseline: Double?
    var trainingReadiness: String
}

enum DailyHealthCalculator {
    static let sleepGoalMinutes = 480.0
    static let minimumBaselineDays = 14

    static func scoredInputs(_ inputs: [DailyHealthInput]) -> [(DailyHealthInput, DailyHealthScores)] {
        let sorted = inputs.sorted { $0.dayStart < $1.dayStart }
        return sorted.enumerated().map { index, input in
            let history = Array(sorted[..<index])
            return (input, scores(for: input, history: history))
        }
    }

    static func scores(for input: DailyHealthInput, history: [DailyHealthInput]) -> DailyHealthScores {
        let sleepScore = sleepScore(for: input)
        let hrvBaseline = baseline(history.compactMap(\.hrvMs))
        let rhrBaseline = baseline(history.compactMap(\.restingHeartRate))
        let strainBaseline = baseline(history.map(strainLoad).filter { $0 > 0 })
        let strainScore = strainScore(for: input, baseline: strainBaseline)
        let recoveryScore = recoveryScore(
            input: input,
            sleepScore: sleepScore,
            hrvBaseline: hrvBaseline,
            restingHeartRateBaseline: rhrBaseline
        )

        return DailyHealthScores(
            recoveryScore: recoveryScore,
            sleepScore: sleepScore,
            strainScore: strainScore,
            hrvBaselineMs: hrvBaseline,
            restingHeartRateBaseline: rhrBaseline,
            strainBaseline: strainBaseline,
            trainingReadiness: readinessText(recoveryScore: recoveryScore, strainScore: strainScore)
        )
    }

    static func sleepScore(for input: DailyHealthInput) -> Int? {
        guard let sleepMinutes = input.sleepDurationMinutes, sleepMinutes > 0 else { return nil }
        let durationScore = min(sleepMinutes / sleepGoalMinutes, 1) * 100
        let efficiencyScore = (input.sleepEfficiency ?? 0.9) * 100
        return clampedScore(durationScore * 0.75 + efficiencyScore * 0.25)
    }

    static func recoveryScore(
        input: DailyHealthInput,
        sleepScore: Int?,
        hrvBaseline: Double?,
        restingHeartRateBaseline: Double?
    ) -> Int? {
        guard let sleepScore,
              let hrv = input.hrvMs,
              let hrvBaseline,
              hrvBaseline > 0,
              let rhr = input.restingHeartRate,
              let restingHeartRateBaseline,
              restingHeartRateBaseline > 0 else {
            return nil
        }

        let hrvScore = ratioScore(hrv / hrvBaseline, low: 0.75, high: 1.2)
        let rhrScore = ratioScore(restingHeartRateBaseline / rhr, low: 0.88, high: 1.1)
        let vitalsScore = vitalsStabilityScore(input)
        return clampedScore(Double(sleepScore) * 0.35 + hrvScore * 0.35 + rhrScore * 0.2 + vitalsScore * 0.1)
    }

    static func strainScore(for input: DailyHealthInput, baseline: Double?) -> Int? {
        let load = strainLoad(input)
        guard load > 0 else { return nil }
        guard let baseline, baseline > 0 else {
            return clampedScore(min(load / 120.0, 1) * 100)
        }
        return clampedScore(ratioScore(load / baseline, low: 0.3, high: 1.8))
    }

    static func strainLoad(_ input: DailyHealthInput) -> Double {
        let activeEnergy = input.activeEnergyKcal ?? 0
        let exercise = input.exerciseMinutes ?? 0
        let steps = (input.steps ?? 0) / 100
        let workoutBonus = Double(input.workoutCount) * 25
        return activeEnergy * 0.25 + exercise * 2 + steps * 0.8 + workoutBonus
    }

    static func readinessText(recoveryScore: Int?, strainScore: Int?) -> String {
        guard let recoveryScore else { return "Import at least 14 days of sleep, HRV, and resting heart rate to estimate readiness." }
        if recoveryScore >= 75 { return "Ready to push. Keep technique tight and let performance guide load jumps." }
        if recoveryScore >= 55 { return "Train normally, but avoid forcing PRs if warm-ups feel slow." }
        if let strainScore, strainScore >= 75 { return "Recovery is low after a high-strain day. Favor easy cardio, mobility, or a deload." }
        return "Recovery is low. Consider lighter volume, longer rests, and earlier sleep tonight."
    }

    private static func baseline(_ values: [Double]) -> Double? {
        guard values.count >= minimumBaselineDays else { return nil }
        let window = values.suffix(30)
        return window.reduce(0, +) / Double(window.count)
    }

    private static func vitalsStabilityScore(_ input: DailyHealthInput) -> Double {
        var score = 100.0
        if let oxygen = input.oxygenSaturationPercent, oxygen < 95 { score -= (95 - oxygen) * 8 }
        if let respiratoryRate = input.respiratoryRate, respiratoryRate < 10 || respiratoryRate > 22 { score -= 12 }
        if let temperature = input.wristTemperatureCelsius, abs(temperature) > 1 { score -= min(abs(temperature) * 10, 20) }
        return min(max(score, 0), 100)
    }

    private static func ratioScore(_ ratio: Double, low: Double, high: Double) -> Double {
        guard high > low else { return 50 }
        return min(max((ratio - low) / (high - low), 0), 1) * 100
    }

    private static func clampedScore(_ value: Double) -> Int {
        Int(min(max(value.rounded(), 0), 100))
    }
}
