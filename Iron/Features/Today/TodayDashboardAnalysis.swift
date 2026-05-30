import Foundation

enum TodayScoreKind: String, Identifiable, CaseIterable {
    case recovery = "Recovery"
    case sleep = "Sleep"
    case strain = "Strain"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .recovery: "battery.75percent"
        case .sleep: "bed.double.fill"
        case .strain: "figure.strengthtraining.traditional"
        }
    }
}

struct TodayDashboardAnalysis {
    let snapshot: DailyHealthSnapshot?
    let history: [DailyHealthSnapshot]

    var morningSummary: String {
        guard let snapshot else { return "Refresh HealthKit data to build today's dashboard." }

        let sleep = descriptor(for: snapshot.sleepScore, strong: "strong sleep", normal: "decent sleep", low: "poor sleep")
        let recovery = descriptor(for: snapshot.recoveryScore, strong: "high recovery", normal: "normal recovery", low: "low recovery")
        let strain = descriptor(for: snapshot.strainScore, strong: "high strain", normal: "moderate strain", low: "low strain")
        return "\(sleep.capitalized), \(recovery), and \(strain). \(readiness.action)"
    }

    var readiness: ReadinessRecommendation {
        guard let snapshot else {
            return ReadinessRecommendation(
                title: "Import Health Data",
                action: "Refresh after enabling Daily Health access.",
                systemImage: "questionmark.circle",
                details: ["No daily snapshot is available yet."]
            )
        }

        let recovery = snapshot.recoveryScore
        let strain = snapshot.strainScore
        let sleep = snapshot.sleepScore

        if (recovery ?? 0) >= 80 && (strain ?? 0) < 70 {
            return ReadinessRecommendation(
                title: "Push Heavy",
                action: "Good day for hard training.",
                systemImage: "bolt.circle",
                details: ["Keep warm-ups honest.", "Push top sets if bar speed feels good.", "Avoid adding volume just because recovery is high."]
            )
        }
        if (recovery ?? 0) >= 65 && (sleep ?? 0) >= 65 {
            return ReadinessRecommendation(
                title: "Train Normal",
                action: "Run the planned workout.",
                systemImage: "checkmark.circle",
                details: ["Use normal loads and rests.", "Skip forced PR attempts if early sets feel slow.", "Keep conditioning moderate."]
            )
        }
        if (recovery ?? 0) >= 50 || (sleep ?? 0) >= 70 {
            return ReadinessRecommendation(
                title: "Technique / Volume Day",
                action: "Reduce intensity slightly.",
                systemImage: "exclamationmark.circle",
                details: ["Keep main lifts around 2-3 reps in reserve.", "Reduce accessory volume by about 20%.", "Prefer Zone 2 over sprints today."]
            )
        }
        return ReadinessRecommendation(
            title: "Recovery Day",
            action: "Favor recovery work.",
            systemImage: "pause.circle",
            details: ["Use mobility, walking, or easy cardio.", "Avoid max attempts and sprint intervals.", "Prioritize calories, hydration, and an earlier bedtime."]
        )
    }

    var vitalsAlerts: [VitalsAlert] {
        guard let snapshot else { return [] }
        var alerts: [VitalsAlert] = []

        if let hrv = snapshot.hrvMs, let baseline = snapshot.hrvBaselineMs, baseline > 0, hrv < baseline * 0.8 {
            alerts.append(VitalsAlert(title: "HRV is down", detail: "HRV is more than 20% below baseline.", systemImage: "waveform.path.ecg"))
        }
        if let rhr = snapshot.restingHeartRate, let baseline = snapshot.restingHeartRateBaseline, rhr >= baseline + 8 {
            alerts.append(VitalsAlert(title: "Resting heart rate is elevated", detail: "RHR is at least 8 bpm above baseline.", systemImage: "heart"))
        }
        if let oxygen = snapshot.oxygenSaturationPercent, oxygen < 95 {
            alerts.append(VitalsAlert(title: "Blood oxygen is low", detail: "SpO2 is below 95%. Recheck source data if this is unusual.", systemImage: "drop"))
        }
        if let respiratoryRate = snapshot.respiratoryRate, respiratoryRate < 10 || respiratoryRate > 22 {
            alerts.append(VitalsAlert(title: "Respiratory rate is outside usual range", detail: "This can reflect stress, illness, or measurement noise.", systemImage: "lungs"))
        }
        if let wristTemperature = snapshot.wristTemperatureCelsius, wristTemperature > 0.8 {
            alerts.append(VitalsAlert(title: "Wrist temperature is elevated", detail: "Temperature is above recent sleep baseline.", systemImage: "thermometer"))
        }
        if sleepDebtHours >= 4 {
            alerts.append(VitalsAlert(title: "Sleep debt is building", detail: "You are about \(Int(sleepDebtHours.rounded())) hours short over the last 7 days.", systemImage: "moon.zzz"))
        }

        return alerts
    }

    var sleepDebtHours: Double {
        let recent = Array(history.prefix(7))
        guard !recent.isEmpty else { return 0 }
        let debtMinutes = recent.reduce(0.0) { total, day in
            total + max(DailyHealthCalculator.sleepGoalMinutes - (day.sleepDurationMinutes ?? 0), 0)
        }
        return debtMinutes / 60
    }

    var trendCards: [TrendCardModel] {
        [
            trendCard(title: "Recovery", unit: "pts", values: history.compactMap { $0.recoveryScore.map(Double.init) }, systemImage: TodayScoreKind.recovery.systemImage),
            trendCard(title: "Sleep", unit: "pts", values: history.compactMap { $0.sleepScore.map(Double.init) }, systemImage: TodayScoreKind.sleep.systemImage),
            trendCard(title: "Strain", unit: "pts", values: history.compactMap { $0.strainScore.map(Double.init) }, systemImage: TodayScoreKind.strain.systemImage),
            trendCard(title: "HRV", unit: "ms", values: history.compactMap(\.hrvMs), systemImage: "waveform.path.ecg"),
            trendCard(title: "RHR", unit: "bpm", values: history.compactMap(\.restingHeartRate), systemImage: "heart"),
            trendCard(title: "VO2", unit: "", values: history.compactMap(\.vo2Max), systemImage: "gauge.with.dots.needle.67percent"),
        ].compactMap(\.self)
    }

    var weeklyLoad: [DailyLoadPoint] {
        Array(history.prefix(7).reversed()).map {
            DailyLoadPoint(day: $0.dayStart, load: strainLoad($0), score: $0.strainScore)
        }
    }

    var diagnostics: [DataDiagnostic] {
        [
            diagnostic("Sleep", value: snapshot?.sleepDurationMinutes, date: snapshot?.sleepEnd ?? latestDate(\.sleepDurationMinutes), systemImage: "bed.double"),
            diagnostic("HRV", value: snapshot?.hrvMs, date: latestDate(\.hrvMs), systemImage: "waveform.path.ecg"),
            diagnostic("Resting heart rate", value: snapshot?.restingHeartRate, date: latestDate(\.restingHeartRate), systemImage: "heart"),
            diagnostic("Wrist temperature", value: snapshot?.wristTemperatureCelsius, date: latestDate(\.wristTemperatureCelsius), systemImage: "thermometer"),
            diagnostic("VO2 max", value: snapshot?.vo2Max, date: latestDate(\.vo2Max), systemImage: "gauge.with.dots.needle.67percent"),
            diagnostic("Workouts", value: snapshot?.workoutCount == 0 ? nil : Double(snapshot?.workoutCount ?? 0), date: latestWorkoutDate, systemImage: "dumbbell"),
        ]
    }

    func scoreBreakdown(for kind: TodayScoreKind) -> ScoreBreakdown {
        guard let snapshot else {
            return ScoreBreakdown(title: kind.rawValue, score: nil, components: [], notes: ["No snapshot is available yet."])
        }

        switch kind {
        case .sleep:
            let durationScore = min((snapshot.sleepDurationMinutes ?? 0) / DailyHealthCalculator.sleepGoalMinutes, 1) * 100
            let efficiencyScore = (snapshot.sleepEfficiency ?? 0.9) * 100
            return ScoreBreakdown(
                title: "Sleep Score",
                score: snapshot.sleepScore,
                components: [
                    ScoreComponent(title: "Duration", value: durationScore, weight: 0.75, detail: "\(formatMinutes(snapshot.sleepDurationMinutes)) vs 8h goal"),
                    ScoreComponent(title: "Efficiency", value: efficiencyScore, weight: 0.25, detail: "\(Int((snapshot.sleepEfficiency ?? 0).rounded() * 100))% asleep / in bed"),
                ],
                notes: ["Today uses the sleep session that ended this morning."]
            )
        case .recovery:
            let hrvScore = ratioScore((snapshot.hrvMs ?? 0) / max(snapshot.hrvBaselineMs ?? 0, 0.1), low: 0.75, high: 1.2)
            let rhrScore = ratioScore((snapshot.restingHeartRateBaseline ?? 0) / max(snapshot.restingHeartRate ?? 0, 0.1), low: 0.88, high: 1.1)
            let sleepScore = Double(snapshot.sleepScore ?? 0)
            let vitalsScore = vitalsStabilityScore(snapshot)
            return ScoreBreakdown(
                title: "Recovery Score",
                score: snapshot.recoveryScore,
                components: [
                    ScoreComponent(title: "Sleep", value: sleepScore, weight: 0.35, detail: "Last night's sleep score"),
                    ScoreComponent(title: "HRV", value: hrvScore, weight: 0.35, detail: baselineText(value: snapshot.hrvMs, baseline: snapshot.hrvBaselineMs, suffix: " ms")),
                    ScoreComponent(title: "Resting HR", value: rhrScore, weight: 0.20, detail: baselineText(value: snapshot.restingHeartRate, baseline: snapshot.restingHeartRateBaseline, suffix: " bpm")),
                    ScoreComponent(title: "Vitals", value: vitalsScore, weight: 0.10, detail: "SpO2, respiratory rate, and wrist temperature stability"),
                ],
                notes: ["Recovery needs sleep, HRV, resting heart rate, and 14 prior baseline days."]
            )
        case .strain:
            let load = strainLoad(snapshot)
            let baseline = snapshot.strainBaseline ?? 0
            let score = baseline > 0 ? ratioScore(load / baseline, low: 0.3, high: 1.8) : min(load / 120, 1) * 100
            return ScoreBreakdown(
                title: "Strain Score",
                score: snapshot.strainScore,
                components: [
                    ScoreComponent(title: "Active energy", value: min((snapshot.activeEnergyKcal ?? 0) / 800, 1) * 100, weight: 0.25, detail: "\(Int(snapshot.activeEnergyKcal ?? 0)) kcal"),
                    ScoreComponent(title: "Exercise", value: min((snapshot.exerciseMinutes ?? 0) / 60, 1) * 100, weight: 0.35, detail: "\(Int(snapshot.exerciseMinutes ?? 0)) minutes"),
                    ScoreComponent(title: "Steps", value: min((snapshot.steps ?? 0) / 10000, 1) * 100, weight: 0.25, detail: "\(Int(snapshot.steps ?? 0)) steps"),
                    ScoreComponent(title: "Workouts", value: min(Double(snapshot.workoutCount) / 2, 1) * 100, weight: 0.15, detail: "\(snapshot.workoutCount) workouts"),
                ],
                notes: ["Current load \(Int(load)) vs baseline \(baseline > 0 ? "\(Int(baseline))" : "not ready"). Estimated score \(Int(score.rounded()))."]
            )
        }
    }

    private func trendCard(title: String, unit: String, values: [Double], systemImage: String) -> TrendCardModel? {
        guard let current = values.first else { return nil }
        let prior = Array(values.dropFirst().prefix(7))
        let average = prior.isEmpty ? nil : prior.reduce(0, +) / Double(prior.count)
        let delta = average.map { current - $0 }
        return TrendCardModel(title: title, unit: unit, current: current, delta: delta, values: Array(values.prefix(14).reversed()), systemImage: systemImage)
    }

    private func diagnostic(_ title: String, value: Double?, date: Date?, systemImage: String) -> DataDiagnostic {
        DataDiagnostic(title: title, systemImage: systemImage, status: value == nil ? "No sample" : "Available", date: date)
    }

    private func latestDate(_ keyPath: KeyPath<DailyHealthSnapshot, Double?>) -> Date? {
        history.first { $0[keyPath: keyPath] != nil }?.dayStart
    }

    private var latestWorkoutDate: Date? {
        history.first { $0.workoutCount > 0 }?.dayStart
    }

    private func descriptor(for score: Int?, strong: String, normal: String, low: String) -> String {
        guard let score else { return "insufficient data" }
        if score >= 75 { return strong }
        if score >= 55 { return normal }
        return low
    }
}

struct ReadinessRecommendation {
    let title: String
    let action: String
    let systemImage: String
    let details: [String]
}

struct VitalsAlert: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let systemImage: String
}

struct TrendCardModel: Identifiable {
    let id = UUID()
    let title: String
    let unit: String
    let current: Double
    let delta: Double?
    let values: [Double]
    let systemImage: String
}

struct DailyLoadPoint: Identifiable {
    let id = UUID()
    let day: Date
    let load: Double
    let score: Int?
}

struct DataDiagnostic: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let status: String
    let date: Date?
}

struct ScoreBreakdown {
    let title: String
    let score: Int?
    let components: [ScoreComponent]
    let notes: [String]
}

struct ScoreComponent: Identifiable {
    let id = UUID()
    let title: String
    let value: Double
    let weight: Double
    let detail: String
}

private func strainLoad(_ snapshot: DailyHealthSnapshot) -> Double {
    let input = DailyHealthInput(
        dayStart: snapshot.dayStart,
        steps: snapshot.steps,
        activeEnergyKcal: snapshot.activeEnergyKcal,
        exerciseMinutes: snapshot.exerciseMinutes,
        workoutCount: snapshot.workoutCount
    )
    return DailyHealthCalculator.strainLoad(input)
}

private func vitalsStabilityScore(_ snapshot: DailyHealthSnapshot) -> Double {
    var score = 100.0
    if let oxygen = snapshot.oxygenSaturationPercent, oxygen < 95 { score -= (95 - oxygen) * 8 }
    if let respiratoryRate = snapshot.respiratoryRate, respiratoryRate < 10 || respiratoryRate > 22 { score -= 12 }
    if let temperature = snapshot.wristTemperatureCelsius, abs(temperature) > 1 { score -= min(abs(temperature) * 10, 20) }
    return min(max(score, 0), 100)
}

private func ratioScore(_ ratio: Double, low: Double, high: Double) -> Double {
    guard high > low else { return 50 }
    return min(max((ratio - low) / (high - low), 0), 1) * 100
}

private func baselineText(value: Double?, baseline: Double?, suffix: String) -> String {
    guard let value, let baseline else { return "Missing baseline" }
    return "\(Int(value.rounded()))\(suffix) vs \(Int(baseline.rounded()))\(suffix) baseline"
}

private func formatMinutes(_ minutes: Double?) -> String {
    guard let minutes else { return "--" }
    return "\(Int(minutes) / 60)h \(Int(minutes) % 60)m"
}
