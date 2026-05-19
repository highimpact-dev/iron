import Foundation
import SwiftData
import OSLog

private let log = Logger(subsystem: "dev.highimpact.iron", category: "SeedService")

enum SeedError: Error {
    case missingResource(String)
}

private struct ExerciseSeed: Decodable {
    let name: String
    let slug: String
    let category: ExerciseCategory
    let movementPattern: MovementPattern
    let primaryMuscles: [Muscle]
    let secondaryMuscles: [Muscle]
    let equipment: [Equipment]
    let videoURLString: String?
    let progressionIncrementLb: Double?
    let isUnilateral: Bool?
    let instructions: String?
}

private struct ProgramSeed: Decodable {
    let name: String
    let author: String?
    let programDescription: String?
    let isBuiltIn: Bool
    let weeksLength: Int?
    let daysPerWeek: Int?
    let days: [ProgramDaySeed]
}

private struct ProgramDaySeed: Decodable {
    let name: String
    let weekIndex: Int?
    let phaseIndex: Int?
    let phaseName: String?
    let dayIndex: Int
    let notes: String?
    let exercises: [ProgramExerciseSeed]
}

private struct ProgramExerciseSeed: Decodable {
    let exerciseSlug: String
    let orderIndex: Int
    let targetSets: Int
    let targetRepsMin: Int
    let targetRepsMax: Int
    let targetRPE: Double?
    let targetRIR: Int?
    let earlySetTargetRPE: String?
    let lastSetTargetRPE: String?
    let restSeconds: Int
    let intensityTechnique: String?
    let videoURLString: String?
    let substitutionOption1Name: String?
    let substitutionOption1URLString: String?
    let substitutionOption2Name: String?
    let substitutionOption2URLString: String?
    let notes: String?
    let warmupSets: [WarmupSetSeed]?
}

private struct WarmupSetSeed: Decodable {
    let orderIndex: Int
    let percentOfWorkWeight: Double?
    let fixedWeightLb: Double?
    let reps: Int
    let notes: String?
}

@MainActor
enum SeedService {
    static func seedIfNeeded(context: ModelContext) {
        do {
            try seedExercises(context: context)
            try seedPrograms(context: context)
            try context.save()
        } catch {
            log.error("Seed failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func seedExercises(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let existingBySlug = Dictionary(uniqueKeysWithValues: existing.map { ($0.slug, $0) })

        let seeds: [ExerciseSeed] = try loadJSON("exercises")
        var inserted = 0
        for seed in seeds {
            if let exercise = existingBySlug[seed.slug] {
                guard !exercise.isCustom else { continue }
                apply(seed, to: exercise)
            } else {
                let exercise = Exercise(
                    name: seed.name,
                    slug: seed.slug,
                    category: seed.category,
                    movementPattern: seed.movementPattern
                )
                apply(seed, to: exercise)
                context.insert(exercise)
                inserted += 1
            }
        }
        if inserted > 0 {
            log.info("Seeded \(inserted, privacy: .public) new exercises")
        }
    }

    private static func apply(_ seed: ExerciseSeed, to exercise: Exercise) {
        exercise.name = seed.name
        exercise.category = seed.category
        exercise.movementPattern = seed.movementPattern
        exercise.primaryMuscles = seed.primaryMuscles
        exercise.secondaryMuscles = seed.secondaryMuscles
        exercise.equipment = seed.equipment
        exercise.instructions = seed.instructions
        exercise.videoURL = seed.videoURLString.flatMap(URL.init(string:))
        exercise.progressionIncrementLb = seed.progressionIncrementLb ?? 5.0
        exercise.isUnilateral = seed.isUnilateral ?? false
        exercise.deletedAt = nil
    }

    private static func seedPrograms(context: ModelContext) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let bySlug = Dictionary(uniqueKeysWithValues: exercises.map { ($0.slug, $0) })

        let existingPrograms = try context.fetch(FetchDescriptor<Program>())
        var existingByName: [String: Program] = [:]
        for program in existingPrograms where existingByName[program.name] == nil {
            existingByName[program.name] = program
        }

        let seeds: [ProgramSeed] = try loadJSON("programs")
        let seedNames = Set(seeds.map(\.name))
        for existing in existingPrograms where existing.isBuiltIn && !seedNames.contains(existing.name) {
            existing.deletedAt = existing.deletedAt ?? Date()
        }

        for seed in seeds {
            if let existing = existingByName[seed.name] {
                guard existing.isBuiltIn || seed.isBuiltIn else { continue }
                syncProgram(existing, with: seed, exercises: bySlug, context: context)
                log.info("Refreshed built-in program: \(seed.name, privacy: .public)")
            } else {
                let program = Program(name: seed.name)
                context.insert(program)
                syncProgram(program, with: seed, exercises: bySlug, context: context)
                log.info("Seeded program: \(seed.name, privacy: .public)")
            }
        }
    }

    private static func syncProgram(
        _ program: Program,
        with seed: ProgramSeed,
        exercises bySlug: [String: Exercise],
        context: ModelContext
    ) {
        program.name = seed.name
        program.author = seed.author
        program.programDescription = seed.programDescription
        program.isBuiltIn = seed.isBuiltIn
        program.weeksLength = seed.weeksLength
        program.daysPerWeek = seed.daysPerWeek
        program.deletedAt = nil

        let seededDayKeys = Set(seed.days.map { dayKey($0.dayIndex, $0.weekIndex, $0.phaseIndex) })
        for day in program.days where !seededDayKeys.contains(dayKey(day.dayIndex, day.weekIndex, day.phaseIndex)) {
            context.delete(day)
        }

        for daySeed in seed.days {
            let day = program.days.first {
                $0.dayIndex == daySeed.dayIndex
                    && $0.weekIndex == daySeed.weekIndex
                    && $0.phaseIndex == daySeed.phaseIndex
            } ?? {
                let day = ProgramDay(name: daySeed.name, program: program)
                context.insert(day)
                return day
            }()

            day.name = daySeed.name
            day.weekIndex = daySeed.weekIndex
            day.phaseIndex = daySeed.phaseIndex
            day.phaseName = daySeed.phaseName
            day.dayIndex = daySeed.dayIndex
            day.notes = daySeed.notes

            syncProgramExercises(day, with: daySeed, programName: seed.name, exercises: bySlug, context: context)
        }
    }

    private static func syncProgramExercises(
        _ day: ProgramDay,
        with seed: ProgramDaySeed,
        programName: String,
        exercises bySlug: [String: Exercise],
        context: ModelContext
    ) {
        let seedIndexes = Set(seed.exercises.map(\.orderIndex))
        for exercise in day.exercises where !seedIndexes.contains(exercise.orderIndex) {
            context.delete(exercise)
        }

        for exSeed in seed.exercises {
            guard let exercise = bySlug[exSeed.exerciseSlug] else {
                log.error("Program \(programName, privacy: .public) references missing exercise slug \(exSeed.exerciseSlug, privacy: .public)")
                continue
            }

            let pe = day.exercises.first { $0.orderIndex == exSeed.orderIndex } ?? {
                let pe = ProgramExercise(
                    orderIndex: exSeed.orderIndex,
                    targetSets: exSeed.targetSets,
                    targetRepsMin: exSeed.targetRepsMin,
                    targetRepsMax: exSeed.targetRepsMax,
                    programDay: day
                )
                context.insert(pe)
                return pe
            }()

            pe.orderIndex = exSeed.orderIndex
            pe.targetSets = exSeed.targetSets
            pe.targetRepsMin = exSeed.targetRepsMin
            pe.targetRepsMax = exSeed.targetRepsMax
            pe.targetRPE = exSeed.targetRPE
            pe.targetRIR = exSeed.targetRIR
            pe.earlySetTargetRPE = exSeed.earlySetTargetRPE
            pe.lastSetTargetRPE = exSeed.lastSetTargetRPE
            pe.restSeconds = exSeed.restSeconds
            pe.intensityTechnique = exSeed.intensityTechnique
            pe.videoURLString = exSeed.videoURLString
            pe.substitutionOption1Name = exSeed.substitutionOption1Name
            pe.substitutionOption1URLString = exSeed.substitutionOption1URLString
            pe.substitutionOption2Name = exSeed.substitutionOption2Name
            pe.substitutionOption2URLString = exSeed.substitutionOption2URLString
            pe.notes = exSeed.notes
            pe.exercise = exercise
            if pe.preferredExercise?.deletedAt != nil {
                pe.preferredExercise = nil
            }
            pe.programDay = day

            syncWarmupSets(pe, with: exSeed.warmupSets ?? [], context: context)
        }
    }

    private static func dayKey(_ dayIndex: Int, _ weekIndex: Int?, _ phaseIndex: Int?) -> String {
        "\(dayIndex)-\(weekIndex ?? -1)-\(phaseIndex ?? -1)"
    }

    private static func syncWarmupSets(_ programExercise: ProgramExercise, with seeds: [WarmupSetSeed], context: ModelContext) {
        let seedIndexes = Set(seeds.map(\.orderIndex))
        for warmup in programExercise.warmupSets where !seedIndexes.contains(warmup.orderIndex) {
            context.delete(warmup)
        }

        for seed in seeds {
            let warmup = programExercise.warmupSets.first { $0.orderIndex == seed.orderIndex } ?? {
                let warmup = WarmupSet(orderIndex: seed.orderIndex, reps: seed.reps, programExercise: programExercise)
                context.insert(warmup)
                return warmup
            }()

            warmup.orderIndex = seed.orderIndex
            warmup.percentOfWorkWeight = seed.percentOfWorkWeight
            warmup.fixedWeightLb = seed.fixedWeightLb
            warmup.reps = seed.reps
            warmup.notes = seed.notes
            warmup.programExercise = programExercise
        }
    }

    private static func loadJSON<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw SeedError.missingResource(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
