import Foundation
import HealthKit

enum HealthKitPreferenceKeys {
    static let writeWorkouts = "healthkit.writeWorkouts"
    static let readBodyMetrics = "healthkit.readBodyMetrics"
    static let writeBodyMetrics = "healthkit.writeBodyMetrics"
    static let readNutrition = "healthkit.readNutrition"
    static let writeNutrition = "healthkit.writeNutrition"
    static let readDailyHealth = "healthkit.readDailyHealth"
}

struct HealthWorkoutSnapshot {
    let id: UUID
    let name: String
    let startedAt: Date
    let finishedAt: Date
    let bodyweightLb: Double?
    let rpeOverall: Double?
    let notes: String?
    let exerciseCount: Int
    let workingSetCount: Int
    let totalReps: Int
    let totalVolumeLb: Double

    init(workout: Workout) {
        let workingSets = workout.setEntries.filter { $0.setType != .warmup }
        self.id = workout.id
        self.name = workout.name ?? workout.sourceProgramDay?.name ?? "Strength Training"
        self.startedAt = workout.startedAt
        self.finishedAt = workout.finishedAt ?? Date()
        self.bodyweightLb = workout.bodyweightLb
        self.rpeOverall = workout.rpeOverall
        self.notes = workout.notes
        self.exerciseCount = Set(workingSets.compactMap { $0.exercise?.id }).count
        self.workingSetCount = workingSets.count
        self.totalReps = workingSets.reduce(0) { $0 + $1.reps }
        self.totalVolumeLb = workingSets.reduce(0) { total, set in
            total + (set.weightLb ?? 0) * Double(set.reps)
        }
    }
}

struct HealthBodyMetricSnapshot: Identifiable {
    let id = UUID()
    let loggedAt: Date
    let bodyweightLb: Double?
    let bodyFatPercent: Double?
    let waistIn: Double?

    init(
        loggedAt: Date,
        bodyweightLb: Double? = nil,
        bodyFatPercent: Double? = nil,
        waistIn: Double? = nil
    ) {
        self.loggedAt = loggedAt
        self.bodyweightLb = bodyweightLb
        self.bodyFatPercent = bodyFatPercent
        self.waistIn = waistIn
    }

    init(metric: BodyMetric) {
        self.loggedAt = metric.loggedAt
        self.bodyweightLb = metric.bodyweightLb
        self.bodyFatPercent = metric.bodyFatPercent
        self.waistIn = metric.waistIn
    }
}

struct HealthNutritionSnapshot: Identifiable {
    let id = UUID()
    let loggedAt: Date
    let mealName: String
    let foodName: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double?
    let sugarG: Double?
    let sodiumMg: Double?
    let potassiumMg: Double?
    let calciumMg: Double?
    let ironMg: Double?
    let vitaminDMcg: Double?
    let cholesterolMg: Double?

    init(
        loggedAt: Date,
        mealName: String = "Health",
        foodName: String = "Health nutrition import",
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        sodiumMg: Double? = nil,
        potassiumMg: Double? = nil,
        calciumMg: Double? = nil,
        ironMg: Double? = nil,
        vitaminDMcg: Double? = nil,
        cholesterolMg: Double? = nil
    ) {
        self.loggedAt = loggedAt
        self.mealName = mealName
        self.foodName = foodName
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
        self.potassiumMg = potassiumMg
        self.calciumMg = calciumMg
        self.ironMg = ironMg
        self.vitaminDMcg = vitaminDMcg
        self.cholesterolMg = cholesterolMg
    }

    init(entry: NutritionEntry) {
        self.loggedAt = entry.loggedAt
        self.mealName = entry.mealName
        self.foodName = entry.foodName
        self.calories = entry.calories
        self.proteinG = entry.proteinG
        self.carbsG = entry.carbsG
        self.fatG = entry.fatG
        self.fiberG = entry.fiberG
        self.sugarG = entry.sugarG
        self.sodiumMg = entry.sodiumMg
        self.potassiumMg = entry.potassiumMg
        self.calciumMg = entry.calciumMg
        self.ironMg = entry.ironMg
        self.vitaminDMcg = entry.vitaminDMcg
        self.cholesterolMg = entry.cholesterolMg
    }
}

@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private let healthStore = HKHealthStore()

    private init() {}

    func requestAuthorization(
        readBodyMetrics: Bool,
        writeBodyMetrics: Bool,
        writeWorkouts: Bool,
        readNutrition: Bool = false,
        writeNutrition: Bool = false,
        readDailyHealth: Bool = false
    ) async throws {
        guard Self.isAvailable else { throw HealthKitError.unavailable }

        var shareTypes = Set<HKSampleType>()
        var readTypes = Set<HKObjectType>()

        if writeWorkouts {
            shareTypes.insert(HKObjectType.workoutType())
        }

        let bodyTypes = supportedBodyQuantityTypes()
        if writeBodyMetrics {
            shareTypes.formUnion(bodyTypes)
        }
        if readBodyMetrics {
            readTypes.formUnion(bodyTypes)
        }

        let nutritionTypes = supportedNutritionQuantityTypes()
        if writeNutrition {
            shareTypes.formUnion(nutritionTypes)
        }
        if readNutrition {
            readTypes.formUnion(nutritionTypes)
        }

        if readDailyHealth {
            readTypes.formUnion(supportedDailyHealthTypes())
        }

        guard !shareTypes.isEmpty || !readTypes.isEmpty else { return }
        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func authorizationSummary() -> String {
        guard Self.isAvailable else { return "Unavailable" }

        let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        let bodyStatus = supportedBodyQuantityTypes()
            .map { healthStore.authorizationStatus(for: $0) }
        let nutritionStatus = supportedNutritionQuantityTypes()
            .map { healthStore.authorizationStatus(for: $0) }
        let dailyHealthStatus = supportedDailyHealthQuantityTypes()
            .map { healthStore.authorizationStatus(for: $0) }

        if workoutStatus == .sharingAuthorized
            || bodyStatus.contains(.sharingAuthorized)
            || nutritionStatus.contains(.sharingAuthorized)
            || dailyHealthStatus.contains(.sharingAuthorized) {
            return "Connected"
        }
        if workoutStatus == .sharingDenied
            || bodyStatus.contains(.sharingDenied)
            || nutritionStatus.contains(.sharingDenied)
            || dailyHealthStatus.contains(.sharingDenied) {
            return "Limited"
        }
        return "Not connected"
    }

    func saveCompletedWorkout(_ snapshot: HealthWorkoutSnapshot) async throws {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        guard UserDefaults.standard.bool(forKey: HealthKitPreferenceKeys.writeWorkouts) else { return }

        try await requestAuthorization(
            readBodyMetrics: false,
            writeBodyMetrics: UserDefaults.standard.bool(forKey: HealthKitPreferenceKeys.writeBodyMetrics),
            writeWorkouts: true
        )

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .unknown

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )
        try await builder.beginCollection(at: snapshot.startedAt)
        try await addMetadata(workoutMetadata(for: snapshot), to: builder)
        try await builder.endCollection(at: snapshot.finishedAt)
        _ = try await builder.finishWorkout()

        if UserDefaults.standard.bool(forKey: HealthKitPreferenceKeys.writeBodyMetrics),
           let bodyweight = snapshot.bodyweightLb {
            try await saveBodyMetric(
                HealthBodyMetricSnapshot(
                    loggedAt: snapshot.finishedAt,
                    bodyweightLb: bodyweight
                )
            )
        }
    }

    func saveBodyMetric(_ snapshot: HealthBodyMetricSnapshot) async throws {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        guard UserDefaults.standard.bool(forKey: HealthKitPreferenceKeys.writeBodyMetrics) else { return }

        try await requestAuthorization(
            readBodyMetrics: false,
            writeBodyMetrics: true,
            writeWorkouts: false
        )

        let samples = bodySamples(for: snapshot)
        guard !samples.isEmpty else { return }
        try await healthStore.save(samples)
    }

    func fetchRecentBodyMetrics(days: Int = 365, limit: Int = 240) async throws -> [HealthBodyMetricSnapshot] {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        guard UserDefaults.standard.bool(forKey: HealthKitPreferenceKeys.readBodyMetrics) else { return [] }

        try await requestAuthorization(
            readBodyMetrics: true,
            writeBodyMetrics: false,
            writeWorkouts: false
        )

        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let weights = try await fetchQuantityValues(identifier: .bodyMass, unit: .pound(), since: since, limit: limit)
        let bodyFat = try await fetchQuantityValues(identifier: .bodyFatPercentage, unit: .percent(), since: since, limit: limit)
            .map { HealthQuantityValue(date: $0.date, value: $0.value * 100) }
        let waist = try await fetchQuantityValues(identifier: .waistCircumference, unit: .inch(), since: since, limit: limit)

        var grouped: [Date: BodyAccumulator] = [:]
        for value in weights {
            grouped.accumulate(value, keyPath: \.bodyweightLb)
        }
        for value in bodyFat {
            grouped.accumulate(value, keyPath: \.bodyFatPercent)
        }
        for value in waist {
            grouped.accumulate(value, keyPath: \.waistIn)
        }

        return grouped.values
            .map { $0.snapshot }
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    func saveNutrition(_ snapshot: HealthNutritionSnapshot) async throws {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        guard UserDefaults.standard.bool(forKey: HealthKitPreferenceKeys.writeNutrition) else { return }

        try await requestAuthorization(
            readBodyMetrics: false,
            writeBodyMetrics: false,
            writeWorkouts: false,
            writeNutrition: true
        )

        let samples = nutritionSamples(for: snapshot)
        guard !samples.isEmpty else { return }
        try await healthStore.save(samples)
    }

    func fetchRecentNutrition(days: Int = 30, limit: Int = 500) async throws -> [HealthNutritionSnapshot] {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        guard UserDefaults.standard.bool(forKey: HealthKitPreferenceKeys.readNutrition) else { return [] }

        try await requestAuthorization(
            readBodyMetrics: false,
            writeBodyMetrics: false,
            writeWorkouts: false,
            readNutrition: true
        )

        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let calories = try await fetchQuantityValues(identifier: .dietaryEnergyConsumed, unit: .kilocalorie(), since: since, limit: limit)
        let protein = try await fetchQuantityValues(identifier: .dietaryProtein, unit: .gram(), since: since, limit: limit)
        let carbs = try await fetchQuantityValues(identifier: .dietaryCarbohydrates, unit: .gram(), since: since, limit: limit)
        let fat = try await fetchQuantityValues(identifier: .dietaryFatTotal, unit: .gram(), since: since, limit: limit)
        let fiber = try await fetchQuantityValues(identifier: .dietaryFiber, unit: .gram(), since: since, limit: limit)
        let sugar = try await fetchQuantityValues(identifier: .dietarySugar, unit: .gram(), since: since, limit: limit)
        let sodium = try await fetchQuantityValues(identifier: .dietarySodium, unit: .gramUnit(with: .milli), since: since, limit: limit)
        let potassium = try await fetchQuantityValues(identifier: .dietaryPotassium, unit: .gramUnit(with: .milli), since: since, limit: limit)
        let calcium = try await fetchQuantityValues(identifier: .dietaryCalcium, unit: .gramUnit(with: .milli), since: since, limit: limit)
        let iron = try await fetchQuantityValues(identifier: .dietaryIron, unit: .gramUnit(with: .milli), since: since, limit: limit)
        let vitaminD = try await fetchQuantityValues(identifier: .dietaryVitaminD, unit: .gramUnit(with: .micro), since: since, limit: limit)
        let cholesterol = try await fetchQuantityValues(identifier: .dietaryCholesterol, unit: .gramUnit(with: .milli), since: since, limit: limit)

        var grouped: [Date: NutritionAccumulator] = [:]
        for value in calories {
            grouped.add(value, keyPath: \.calories)
        }
        for value in protein {
            grouped.add(value, keyPath: \.proteinG)
        }
        for value in carbs {
            grouped.add(value, keyPath: \.carbsG)
        }
        for value in fat {
            grouped.add(value, keyPath: \.fatG)
        }
        for value in fiber {
            grouped.addOptional(value, keyPath: \.fiberG)
        }
        for value in sugar {
            grouped.addOptional(value, keyPath: \.sugarG)
        }
        for value in sodium {
            grouped.addOptional(value, keyPath: \.sodiumMg)
        }
        for value in potassium {
            grouped.addOptional(value, keyPath: \.potassiumMg)
        }
        for value in calcium {
            grouped.addOptional(value, keyPath: \.calciumMg)
        }
        for value in iron {
            grouped.addOptional(value, keyPath: \.ironMg)
        }
        for value in vitaminD {
            grouped.addOptional(value, keyPath: \.vitaminDMcg)
        }
        for value in cholesterol {
            grouped.addOptional(value, keyPath: \.cholesterolMg)
        }

        return grouped.values
            .filter { $0.calories > 0 || $0.proteinG > 0 || $0.carbsG > 0 || $0.fatG > 0 }
            .map(\.snapshot)
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    func fetchDailyHealthInputs(days: Int = 60) async throws -> [DailyHealthInput] {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        guard UserDefaults.standard.bool(forKey: HealthKitPreferenceKeys.readDailyHealth) else { return [] }

        try await requestAuthorization(
            readBodyMetrics: false,
            writeBodyMetrics: false,
            writeWorkouts: false,
            readDailyHealth: true
        )

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? Date()

        async let sleep = fetchSleepByDay(start: start, end: end)
        async let hrv = fetchDailyAverage(identifier: .heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), start: start, end: end)
        async let restingHeartRate = fetchDailyAverage(identifier: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end)
        async let respiratoryRate = fetchDailyAverage(identifier: .respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end)
        async let oxygen = fetchDailyAverage(identifier: .oxygenSaturation, unit: .percent(), start: start, end: end)
        async let wristTemperature = fetchLatestQuantityByDay(identifier: .appleSleepingWristTemperature, unit: .degreeCelsius(), start: start, end: end)
        async let steps = fetchDailySum(identifier: .stepCount, unit: .count(), start: start, end: end)
        async let activeEnergy = fetchDailySum(identifier: .activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let restingEnergy = fetchDailySum(identifier: .basalEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let exerciseTime = fetchDailySum(identifier: .appleExerciseTime, unit: .minute(), start: start, end: end)
        async let vo2Max = fetchLatestQuantityByDay(identifier: .vo2Max, unit: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute())), start: start, end: end)
        async let workouts = fetchWorkoutCountByDay(start: start, end: end)

        let sleepByDay = try await sleep
        let hrvByDay = try await hrv
        let rhrByDay = try await restingHeartRate
        let respiratoryByDay = try await respiratoryRate
        let oxygenByDay = try await oxygen
        let wristTemperatureByDay = try await wristTemperature
        let stepsByDay = try await steps
        let activeEnergyByDay = try await activeEnergy
        let restingEnergyByDay = try await restingEnergy
        let exerciseTimeByDay = try await exerciseTime
        let vo2MaxByDay = try await vo2Max
        let workoutsByDay = try await workouts

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = calendar.startOfDay(for: day)
            let sleep = sleepByDay[key]
            return DailyHealthInput(
                dayStart: key,
                sleepStart: sleep?.sleepStart,
                sleepEnd: sleep?.sleepEnd,
                sleepDurationMinutes: sleep?.sleepDurationMinutes,
                timeInBedMinutes: sleep?.timeInBedMinutes,
                hrvMs: hrvByDay[key],
                restingHeartRate: rhrByDay[key],
                respiratoryRate: respiratoryByDay[key],
                oxygenSaturationPercent: oxygenByDay[key].map { $0 * 100 },
                wristTemperatureCelsius: wristTemperatureByDay[key],
                vo2Max: vo2MaxByDay[key],
                steps: stepsByDay[key],
                activeEnergyKcal: activeEnergyByDay[key],
                restingEnergyKcal: restingEnergyByDay[key],
                exerciseMinutes: exerciseTimeByDay[key],
                workoutCount: workoutsByDay[key] ?? 0
            )
        }
    }

    private func supportedBodyQuantityTypes() -> Set<HKQuantityType> {
        [
            HKObjectType.quantityType(forIdentifier: .bodyMass),
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage),
            HKObjectType.quantityType(forIdentifier: .waistCircumference),
        ].compactMap(\.self).reduce(into: Set<HKQuantityType>()) { result, type in
            result.insert(type)
        }
    }

    private func supportedNutritionQuantityTypes() -> Set<HKQuantityType> {
        [
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed),
            HKObjectType.quantityType(forIdentifier: .dietaryProtein),
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates),
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal),
            HKObjectType.quantityType(forIdentifier: .dietaryFiber),
            HKObjectType.quantityType(forIdentifier: .dietarySugar),
            HKObjectType.quantityType(forIdentifier: .dietarySodium),
            HKObjectType.quantityType(forIdentifier: .dietaryPotassium),
            HKObjectType.quantityType(forIdentifier: .dietaryCalcium),
            HKObjectType.quantityType(forIdentifier: .dietaryIron),
            HKObjectType.quantityType(forIdentifier: .dietaryVitaminD),
            HKObjectType.quantityType(forIdentifier: .dietaryCholesterol),
        ].compactMap(\.self).reduce(into: Set<HKQuantityType>()) { result, type in
            result.insert(type)
        }
    }

    private func supportedDailyHealthTypes() -> Set<HKObjectType> {
        var result = Set<HKObjectType>()
        result.formUnion(supportedDailyHealthQuantityTypes())
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            result.insert(sleep)
        }
        result.insert(HKObjectType.workoutType())
        return result
    }

    private func supportedDailyHealthQuantityTypes() -> Set<HKQuantityType> {
        [
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .respiratoryRate),
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation),
            HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime),
            HKObjectType.quantityType(forIdentifier: .vo2Max),
        ].compactMap(\.self).reduce(into: Set<HKQuantityType>()) { result, type in
            result.insert(type)
        }
    }

    private func workoutMetadata(for snapshot: HealthWorkoutSnapshot) -> [String: Any] {
        var metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: "Iron",
            "IronWorkoutID": snapshot.id.uuidString,
            "IronWorkoutName": snapshot.name,
            "IronExerciseCount": snapshot.exerciseCount,
            "IronWorkingSetCount": snapshot.workingSetCount,
            "IronTotalReps": snapshot.totalReps,
            "IronTotalVolumeLb": snapshot.totalVolumeLb,
        ]
        if let rpe = snapshot.rpeOverall {
            metadata["IronSessionRPE"] = rpe
        }
        if let notes = snapshot.notes, !notes.isEmpty {
            metadata[HKMetadataKeyCoachedWorkout] = false
            metadata["IronNotes"] = notes
        }
        return metadata
    }

    private func bodySamples(for snapshot: HealthBodyMetricSnapshot) -> [HKQuantitySample] {
        var samples: [HKQuantitySample] = []

        if let value = snapshot.bodyweightLb,
           let type = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            samples.append(quantitySample(type: type, unit: .pound(), value: value, date: snapshot.loggedAt))
        }

        if let value = snapshot.bodyFatPercent,
           let type = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) {
            samples.append(quantitySample(type: type, unit: .percent(), value: value / 100, date: snapshot.loggedAt))
        }

        if let value = snapshot.waistIn,
           let type = HKObjectType.quantityType(forIdentifier: .waistCircumference) {
            samples.append(quantitySample(type: type, unit: .inch(), value: value, date: snapshot.loggedAt))
        }

        return samples
    }

    private func nutritionSamples(for snapshot: HealthNutritionSnapshot) -> [HKQuantitySample] {
        var samples: [HKQuantitySample] = []

        let metadata: [String: Any] = [
            HKMetadataKeyWasUserEntered: true,
            "IronMealName": snapshot.mealName,
            "IronFoodName": snapshot.foodName,
        ]

        if let type = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed), snapshot.calories > 0 {
            samples.append(quantitySample(type: type, unit: .kilocalorie(), value: snapshot.calories, date: snapshot.loggedAt, metadata: metadata))
        }
        if let type = HKObjectType.quantityType(forIdentifier: .dietaryProtein), snapshot.proteinG > 0 {
            samples.append(quantitySample(type: type, unit: .gram(), value: snapshot.proteinG, date: snapshot.loggedAt, metadata: metadata))
        }
        if let type = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates), snapshot.carbsG > 0 {
            samples.append(quantitySample(type: type, unit: .gram(), value: snapshot.carbsG, date: snapshot.loggedAt, metadata: metadata))
        }
        if let type = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal), snapshot.fatG > 0 {
            samples.append(quantitySample(type: type, unit: .gram(), value: snapshot.fatG, date: snapshot.loggedAt, metadata: metadata))
        }
        if let fiber = snapshot.fiberG,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryFiber),
           fiber > 0 {
            samples.append(quantitySample(type: type, unit: .gram(), value: fiber, date: snapshot.loggedAt, metadata: metadata))
        }
        if let sugar = snapshot.sugarG,
           let type = HKObjectType.quantityType(forIdentifier: .dietarySugar),
           sugar > 0 {
            samples.append(quantitySample(type: type, unit: .gram(), value: sugar, date: snapshot.loggedAt, metadata: metadata))
        }
        if let sodium = snapshot.sodiumMg,
           let type = HKObjectType.quantityType(forIdentifier: .dietarySodium),
           sodium > 0 {
            samples.append(quantitySample(type: type, unit: .gramUnit(with: .milli), value: sodium, date: snapshot.loggedAt, metadata: metadata))
        }
        if let potassium = snapshot.potassiumMg,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryPotassium),
           potassium > 0 {
            samples.append(quantitySample(type: type, unit: .gramUnit(with: .milli), value: potassium, date: snapshot.loggedAt, metadata: metadata))
        }
        if let calcium = snapshot.calciumMg,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryCalcium),
           calcium > 0 {
            samples.append(quantitySample(type: type, unit: .gramUnit(with: .milli), value: calcium, date: snapshot.loggedAt, metadata: metadata))
        }
        if let iron = snapshot.ironMg,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryIron),
           iron > 0 {
            samples.append(quantitySample(type: type, unit: .gramUnit(with: .milli), value: iron, date: snapshot.loggedAt, metadata: metadata))
        }
        if let vitaminD = snapshot.vitaminDMcg,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryVitaminD),
           vitaminD > 0 {
            samples.append(quantitySample(type: type, unit: .gramUnit(with: .micro), value: vitaminD, date: snapshot.loggedAt, metadata: metadata))
        }
        if let cholesterol = snapshot.cholesterolMg,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryCholesterol),
           cholesterol > 0 {
            samples.append(quantitySample(type: type, unit: .gramUnit(with: .milli), value: cholesterol, date: snapshot.loggedAt, metadata: metadata))
        }

        return samples
    }

    private func addMetadata(_ metadata: [String: Any], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.addMetadata(metadata) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitError.metadataSaveFailed)
                }
            }
        }
    }

    private func quantitySample(
        type: HKQuantityType,
        unit: HKUnit,
        value: Double,
        date: Date,
        metadata: [String: Any] = [HKMetadataKeyWasUserEntered: true]
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: date,
            end: date,
            metadata: metadata
        )
    }

    private func fetchQuantityValues(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        since: Date,
        limit: Int
    ) async throws -> [HealthQuantityValue] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [.strictStartDate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let values = (samples as? [HKQuantitySample] ?? []).map {
                    HealthQuantityValue(
                        date: $0.startDate,
                        value: $0.quantity.doubleValue(for: unit)
                    )
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    private func fetchDailyAverage(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [Date: Double] {
        let samples = try await fetchQuantitySamples(identifier: identifier, unit: unit, start: start, end: end)
        let grouped = Dictionary(grouping: samples) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.mapValues { values in
            values.reduce(0) { $0 + $1.value } / Double(values.count)
        }
    }

    private func fetchDailySum(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [Date: Double] {
        let samples = try await fetchQuantitySamples(identifier: identifier, unit: unit, start: start, end: end)
        let grouped = Dictionary(grouping: samples) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.mapValues { values in
            values.reduce(0) { $0 + $1.value }
        }
    }

    private func fetchLatestQuantityByDay(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        lookbackDays: Int = 365
    ) async throws -> [Date: Double] {
        let calendar = Calendar.current
        let lookbackStart = calendar.date(byAdding: .day, value: -lookbackDays, to: start) ?? start
        let samples = try await fetchQuantitySamples(identifier: identifier, unit: unit, start: lookbackStart, end: end)
            .sorted { $0.date < $1.date }
        guard !samples.isEmpty else { return [:] }

        var result: [Date: Double] = [:]
        var latestValue: Double?
        var sampleIndex = 0
        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        for offset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else {
                continue
            }

            while sampleIndex < samples.count, samples[sampleIndex].date < dayEnd {
                latestValue = samples[sampleIndex].value
                sampleIndex += 1
            }

            if let latestValue {
                result[calendar.startOfDay(for: day)] = latestValue
            }
        }

        return result
    }

    private func fetchQuantitySamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [HealthQuantityValue] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let values = (samples as? [HKQuantitySample] ?? []).map {
                    HealthQuantityValue(
                        date: $0.startDate,
                        value: $0.quantity.doubleValue(for: unit)
                    )
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    private func fetchSleepByDay(start: Date, end: Date) async throws -> [Date: SleepAccumulator] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let calendar = Calendar.current
        let queryStart = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            healthStore.execute(query)
        }

        let segments = samples.map {
            SleepSegment(startDate: $0.startDate, endDate: $0.endDate, value: $0.value)
        }
        return SleepAggregator.byWakeDay(segments: segments, start: start, end: end, calendar: calendar)
    }

    private func fetchWorkoutCountByDay(start: Date, end: Date) async throws -> [Date: Int] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            healthStore.execute(query)
        }

        return Dictionary(grouping: workouts) { Calendar.current.startOfDay(for: $0.startDate) }
            .mapValues(\.count)
    }
}

enum HealthKitError: LocalizedError {
    case unavailable
    case metadataSaveFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Health data is not available on this device."
        case .metadataSaveFailed:
            return "HealthKit could not save workout metadata."
        }
    }
}

private struct HealthQuantityValue {
    let date: Date
    let value: Double
}

struct SleepSegment {
    let startDate: Date
    let endDate: Date
    let value: Int
}

struct SleepAccumulator {
    var sleepStart: Date?
    var sleepEnd: Date?
    var sleepDurationMinutes: Double = 0
    var timeInBedMinutes: Double = 0
    var intervalStart: Date?
    var intervalEnd: Date?
    private var asleepIntervals: [DateInterval] = []
    private var inBedIntervals: [DateInterval] = []
    private var sessionIntervals: [DateInterval] = []

    mutating func add(_ sample: HKCategorySample) {
        add(SleepSegment(startDate: sample.startDate, endDate: sample.endDate, value: sample.value))
    }

    mutating func add(_ segment: SleepSegment) {
        let minutes = segment.endDate.timeIntervalSince(segment.startDate) / 60
        guard minutes > 0 else { return }
        let interval = DateInterval(start: segment.startDate, end: segment.endDate)

        intervalStart = minDate(intervalStart, segment.startDate)
        intervalEnd = maxDate(intervalEnd, segment.endDate)
        sessionIntervals.append(interval)

        if segment.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
            inBedIntervals.append(interval)
        } else if Self.isAsleep(segment.value) {
            asleepIntervals.append(interval)
            sleepStart = minDate(sleepStart, segment.startDate)
            sleepEnd = maxDate(sleepEnd, segment.endDate)
        }
    }

    mutating func merge(_ other: SleepAccumulator) {
        sleepStart = minDate(sleepStart, other.sleepStart)
        sleepEnd = maxDate(sleepEnd, other.sleepEnd)
        intervalStart = minDate(intervalStart, other.intervalStart)
        intervalEnd = maxDate(intervalEnd, other.intervalEnd)
        asleepIntervals.append(contentsOf: other.asleepIntervals)
        inBedIntervals.append(contentsOf: other.inBedIntervals)
        sessionIntervals.append(contentsOf: other.sessionIntervals)
        normalizeTimeInBed()
    }

    mutating func normalizeTimeInBed() {
        sleepDurationMinutes = Self.unionDurationMinutes(asleepIntervals)
        let inBedMinutes = Self.unionDurationMinutes(inBedIntervals)
        let sessionMinutes = Self.unionDurationMinutes(sessionIntervals)
        timeInBedMinutes = max(inBedMinutes, sessionMinutes, sleepDurationMinutes)
    }

    static func isSleepRelated(_ value: Int) -> Bool {
        value == HKCategoryValueSleepAnalysis.inBed.rawValue
            || value == HKCategoryValueSleepAnalysis.awake.rawValue
            || isAsleep(value)
    }

    static func isAsleep(_ value: Int) -> Bool {
        value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            || value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
            || value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            || value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
    }

    private static func unionDurationMinutes(_ intervals: [DateInterval]) -> Double {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []

        for interval in sorted {
            guard interval.duration > 0 else { continue }
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }

            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }

        return merged.reduce(0) { $0 + $1.duration / 60 }
    }

    private func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let rhs else { return lhs }
        guard let lhs else { return rhs }
        return min(lhs, rhs)
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let rhs else { return lhs }
        guard let lhs else { return rhs }
        return max(lhs, rhs)
    }
}

enum SleepAggregator {
    static func byWakeDay(
        segments: [SleepSegment],
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> [Date: SleepAccumulator] {
        var sessions: [SleepAccumulator] = []
        let sorted = segments
            .filter { SleepAccumulator.isSleepRelated($0.value) }
            .sorted { $0.startDate < $1.startDate }

        for segment in sorted {
            if let last = sessions.indices.last,
               let previousEnd = sessions[last].intervalEnd,
               segment.startDate.timeIntervalSince(previousEnd) <= 3 * 60 * 60 {
                sessions[last].add(segment)
            } else {
                var session = SleepAccumulator()
                session.add(segment)
                sessions.append(session)
            }
        }

        return sessions.reduce(into: [Date: SleepAccumulator]()) { result, session in
            guard let wakeDate = session.sleepEnd ?? session.intervalEnd else { return }
            let wakeDay = calendar.startOfDay(for: wakeDate)
            guard wakeDay >= start && wakeDay < end else { return }

            var normalized = session
            normalized.normalizeTimeInBed()
            guard normalized.sleepDurationMinutes >= 90 || normalized.timeInBedMinutes >= 120 else { return }

            if let existing = result[wakeDay],
               existing.sleepDurationMinutes >= normalized.sleepDurationMinutes {
                return
            }
            result[wakeDay] = normalized
        }
    }
}

private struct BodyAccumulator {
    var loggedAt: Date
    var bodyweightLb: Double?
    var bodyFatPercent: Double?
    var waistIn: Double?

    var snapshot: HealthBodyMetricSnapshot {
        HealthBodyMetricSnapshot(
            loggedAt: loggedAt,
            bodyweightLb: bodyweightLb,
            bodyFatPercent: bodyFatPercent,
            waistIn: waistIn
        )
    }

    mutating func update(_ value: HealthQuantityValue, keyPath: WritableKeyPath<BodyAccumulator, Double?>) {
        loggedAt = max(loggedAt, value.date)
        if self[keyPath: keyPath] == nil {
            self[keyPath: keyPath] = value.value
        }
    }
}

private extension Dictionary where Key == Date, Value == BodyAccumulator {
    mutating func accumulate(_ value: HealthQuantityValue, keyPath: WritableKeyPath<BodyAccumulator, Double?>) {
        let day = Calendar.current.startOfDay(for: value.date)
        var accumulator = self[day] ?? BodyAccumulator(loggedAt: value.date)
        accumulator.update(value, keyPath: keyPath)
        self[day] = accumulator
    }
}

private struct NutritionAccumulator {
    var loggedAt: Date
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fiberG: Double?
    var sugarG: Double?
    var sodiumMg: Double?
    var potassiumMg: Double?
    var calciumMg: Double?
    var ironMg: Double?
    var vitaminDMcg: Double?
    var cholesterolMg: Double?

    var snapshot: HealthNutritionSnapshot {
        HealthNutritionSnapshot(
            loggedAt: loggedAt,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fiberG: fiberG,
            sugarG: sugarG,
            sodiumMg: sodiumMg,
            potassiumMg: potassiumMg,
            calciumMg: calciumMg,
            ironMg: ironMg,
            vitaminDMcg: vitaminDMcg,
            cholesterolMg: cholesterolMg
        )
    }

    mutating func add(_ value: HealthQuantityValue, keyPath: WritableKeyPath<NutritionAccumulator, Double>) {
        loggedAt = max(loggedAt, value.date)
        self[keyPath: keyPath] += value.value
    }

    mutating func addOptional(_ value: HealthQuantityValue, keyPath: WritableKeyPath<NutritionAccumulator, Double?>) {
        loggedAt = max(loggedAt, value.date)
        self[keyPath: keyPath] = (self[keyPath: keyPath] ?? 0) + value.value
    }
}

private extension Dictionary where Key == Date, Value == NutritionAccumulator {
    mutating func add(_ value: HealthQuantityValue, keyPath: WritableKeyPath<NutritionAccumulator, Double>) {
        let day = Calendar.current.startOfDay(for: value.date)
        var accumulator = self[day] ?? NutritionAccumulator(loggedAt: value.date)
        accumulator.add(value, keyPath: keyPath)
        self[day] = accumulator
    }

    mutating func addOptional(_ value: HealthQuantityValue, keyPath: WritableKeyPath<NutritionAccumulator, Double?>) {
        let day = Calendar.current.startOfDay(for: value.date)
        var accumulator = self[day] ?? NutritionAccumulator(loggedAt: value.date)
        accumulator.addOptional(value, keyPath: keyPath)
        self[day] = accumulator
    }
}
