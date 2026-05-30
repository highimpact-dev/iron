import XCTest
import HealthKit
@testable import Iron

final class DailyHealthCalculatorTests: XCTestCase {
    func testCompleteDataProducesScoresWithBaselines() {
        let history = baselineHistory()
        let today = input(dayOffset: 0, hrvMs: 47, restingHeartRate: 58, sleepDurationMinutes: 470, timeInBedMinutes: 510)

        let scores = DailyHealthCalculator.scores(for: today, history: history)

        XCTAssertNotNil(scores.recoveryScore)
        XCTAssertNotNil(scores.sleepScore)
        XCTAssertNotNil(scores.strainScore)
        XCTAssertNotNil(scores.hrvBaselineMs)
        XCTAssertNotNil(scores.restingHeartRateBaseline)
        XCTAssertNotNil(scores.strainBaseline)
        XCTAssertTrue((0...100).contains(scores.recoveryScore ?? -1))
        XCTAssertTrue((0...100).contains(scores.sleepScore ?? -1))
        XCTAssertTrue((0...100).contains(scores.strainScore ?? -1))
    }

    func testMissingBaselineShowsInsufficientRecoveryData() {
        let today = input(dayOffset: 0, hrvMs: 47, restingHeartRate: 58, sleepDurationMinutes: 470, timeInBedMinutes: 510)

        let scores = DailyHealthCalculator.scores(for: today, history: [])

        XCTAssertNil(scores.recoveryScore)
        XCTAssertNotNil(scores.sleepScore)
        XCTAssertNotNil(scores.strainScore)
        XCTAssertTrue(scores.trainingReadiness.contains("14 days"))
    }

    func testLowHRVAndHighRestingHeartRateLowerRecovery() {
        let history = baselineHistory()
        let strong = input(dayOffset: 0, hrvMs: 52, restingHeartRate: 56, sleepDurationMinutes: 480, timeInBedMinutes: 520)
        let poor = input(dayOffset: 0, hrvMs: 30, restingHeartRate: 72, sleepDurationMinutes: 480, timeInBedMinutes: 520)

        let strongScore = DailyHealthCalculator.scores(for: strong, history: history).recoveryScore
        let poorScore = DailyHealthCalculator.scores(for: poor, history: history).recoveryScore

        XCTAssertNotNil(strongScore)
        XCTAssertNotNil(poorScore)
        XCTAssertLessThan(poorScore ?? 100, strongScore ?? 0)
    }

    func testPoorSleepLowersSleepScore() {
        let good = input(dayOffset: 0, sleepDurationMinutes: 480, timeInBedMinutes: 520)
        let poor = input(dayOffset: 0, sleepDurationMinutes: 250, timeInBedMinutes: 520)

        let goodScore = DailyHealthCalculator.sleepScore(for: good)
        let poorScore = DailyHealthCalculator.sleepScore(for: poor)

        XCTAssertNotNil(goodScore)
        XCTAssertNotNil(poorScore)
        XCTAssertLessThan(poorScore ?? 100, goodScore ?? 0)
    }

    func testHighStrainDayScoresAboveBaseline() {
        let history = baselineHistory(activeEnergyKcal: 350, exerciseMinutes: 25, steps: 5000)
        let highStrain = input(dayOffset: 0, activeEnergyKcal: 900, exerciseMinutes: 80, steps: 14000, workoutCount: 2)

        let scores = DailyHealthCalculator.scores(for: highStrain, history: history)

        XCTAssertNotNil(scores.strainScore)
        XCTAssertGreaterThanOrEqual(scores.strainScore ?? 0, 75)
    }

    func testInputNormalizesDayStartAroundMidnight() {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 29
        components.hour = 23
        components.minute = 59
        let date = Calendar.current.date(from: components)!

        let input = DailyHealthInput(dayStart: date)

        XCTAssertEqual(input.dayStart, Calendar.current.startOfDay(for: date))
    }

    func testScoredInputsUsesEarlierDaysForRollingBaselines() {
        let inputs = baselineHistory() + [
            input(dayOffset: 0, hrvMs: 47, restingHeartRate: 58, sleepDurationMinutes: 470, timeInBedMinutes: 510),
        ]

        let scored = DailyHealthCalculator.scoredInputs(inputs)

        XCTAssertNil(scored.first?.1.recoveryScore)
        XCTAssertNotNil(scored.last?.1.recoveryScore)
    }

    func testSleepAggregatorAssignsOvernightSleepToWakeDay() {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 29
        let wakeDay = Calendar.current.date(from: components)!
        let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: wakeDay)!
        let start = Calendar.current.date(bySettingHour: 22, minute: 30, second: 0, of: previousDay)!
        let midnight = wakeDay
        let end = Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: wakeDay)!

        let segments = [
            SleepSegment(startDate: start, endDate: midnight, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue),
            SleepSegment(startDate: midnight, endDate: end, value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue),
        ]

        let sleepByDay = SleepAggregator.byWakeDay(
            segments: segments,
            start: wakeDay,
            end: Calendar.current.date(byAdding: .day, value: 1, to: wakeDay)!
        )

        XCTAssertEqual(sleepByDay[wakeDay]?.sleepDurationMinutes, 480)
        XCTAssertEqual(sleepByDay[wakeDay]?.timeInBedMinutes, 480)
    }

    func testSleepAggregatorDoesNotDoubleCountOverlappingInBedAndStages() {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 29
        let wakeDay = Calendar.current.date(from: components)!
        let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: wakeDay)!
        let start = Calendar.current.date(bySettingHour: 22, minute: 30, second: 0, of: previousDay)!
        let end = Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: wakeDay)!

        let segments = [
            SleepSegment(startDate: start, endDate: end, value: HKCategoryValueSleepAnalysis.inBed.rawValue),
            SleepSegment(startDate: start, endDate: end, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue),
            SleepSegment(startDate: start, endDate: end, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue),
        ]

        let sleepByDay = SleepAggregator.byWakeDay(
            segments: segments,
            start: wakeDay,
            end: Calendar.current.date(byAdding: .day, value: 1, to: wakeDay)!
        )

        XCTAssertEqual(sleepByDay[wakeDay]?.sleepDurationMinutes, 480)
        XCTAssertEqual(sleepByDay[wakeDay]?.timeInBedMinutes, 480)
    }

    func testGoodButNotPerfectSleepCanScoreHigh() {
        let input = self.input(dayOffset: 0, sleepDurationMinutes: 390, timeInBedMinutes: 430)

        let score = DailyHealthCalculator.sleepScore(for: input)

        XCTAssertGreaterThanOrEqual(score ?? 0, 80)
    }

    private func baselineHistory(
        activeEnergyKcal: Double = 450,
        exerciseMinutes: Double = 40,
        steps: Double = 7000
    ) -> [DailyHealthInput] {
        (-15 ..< -1).map { offset in
            input(
                dayOffset: offset,
                hrvMs: 44,
                restingHeartRate: 60,
                sleepDurationMinutes: 455,
                timeInBedMinutes: 505,
                activeEnergyKcal: activeEnergyKcal,
                exerciseMinutes: exerciseMinutes,
                steps: steps
            )
        }
    }

    private func input(
        dayOffset: Int,
        hrvMs: Double? = 44,
        restingHeartRate: Double? = 60,
        sleepDurationMinutes: Double? = 455,
        timeInBedMinutes: Double? = 505,
        activeEnergyKcal: Double? = 450,
        exerciseMinutes: Double? = 40,
        steps: Double? = 7000,
        workoutCount: Int = 1
    ) -> DailyHealthInput {
        let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date())!
        return DailyHealthInput(
            dayStart: day,
            sleepDurationMinutes: sleepDurationMinutes,
            timeInBedMinutes: timeInBedMinutes,
            hrvMs: hrvMs,
            restingHeartRate: restingHeartRate,
            respiratoryRate: 14,
            oxygenSaturationPercent: 97,
            wristTemperatureCelsius: 0.1,
            vo2Max: 42,
            steps: steps,
            activeEnergyKcal: activeEnergyKcal,
            restingEnergyKcal: 1650,
            exerciseMinutes: exerciseMinutes,
            workoutCount: workoutCount
        )
    }
}
