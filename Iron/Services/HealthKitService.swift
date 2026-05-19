import Foundation
import HealthKit

enum HealthKitPreferenceKeys {
    static let writeWorkouts = "healthkit.writeWorkouts"
    static let readBodyMetrics = "healthkit.readBodyMetrics"
    static let writeBodyMetrics = "healthkit.writeBodyMetrics"
    static let readNutrition = "healthkit.readNutrition"
    static let writeNutrition = "healthkit.writeNutrition"
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
        writeNutrition: Bool = false
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

        if workoutStatus == .sharingAuthorized
            || bodyStatus.contains(.sharingAuthorized)
            || nutritionStatus.contains(.sharingAuthorized) {
            return "Connected"
        }
        if workoutStatus == .sharingDenied
            || bodyStatus.contains(.sharingDenied)
            || nutritionStatus.contains(.sharingDenied) {
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
