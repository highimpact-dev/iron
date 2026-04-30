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
    let instructions: String?
}

private struct ProgramSeed: Decodable {
    let name: String
    let author: String?
    let programDescription: String?
    let isBuiltIn: Bool
    let weeksLength: Int?
    let days: [ProgramDaySeed]
}

private struct ProgramDaySeed: Decodable {
    let name: String
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
    let restSeconds: Int
    let notes: String?
}

@MainActor
enum SeedService {
    static func seedIfNeeded(context: ModelContext) {
        do {
            let exerciseCount = try context.fetchCount(FetchDescriptor<Exercise>())
            if exerciseCount == 0 {
                try seedExercises(context: context)
            }

            let programCount = try context.fetchCount(FetchDescriptor<Program>())
            if programCount == 0 {
                try seedPrograms(context: context)
            }

            try context.save()
        } catch {
            log.error("Seed failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func seedExercises(context: ModelContext) throws {
        let seeds: [ExerciseSeed] = try loadJSON("exercises")
        for seed in seeds {
            let exercise = Exercise(
                name: seed.name,
                slug: seed.slug,
                category: seed.category,
                movementPattern: seed.movementPattern,
                primaryMuscles: seed.primaryMuscles,
                secondaryMuscles: seed.secondaryMuscles,
                equipment: seed.equipment,
                instructions: seed.instructions
            )
            context.insert(exercise)
        }
        log.info("Seeded \(seeds.count, privacy: .public) exercises")
    }

    private static func seedPrograms(context: ModelContext) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let bySlug = Dictionary(uniqueKeysWithValues: exercises.map { ($0.slug, $0) })

        let seeds: [ProgramSeed] = try loadJSON("programs")
        for seed in seeds {
            let program = Program(
                name: seed.name,
                author: seed.author,
                programDescription: seed.programDescription,
                isBuiltIn: seed.isBuiltIn,
                weeksLength: seed.weeksLength
            )
            context.insert(program)

            for daySeed in seed.days {
                let day = ProgramDay(
                    name: daySeed.name,
                    dayIndex: daySeed.dayIndex,
                    notes: daySeed.notes,
                    program: program
                )
                context.insert(day)

                for exSeed in daySeed.exercises {
                    guard let exercise = bySlug[exSeed.exerciseSlug] else {
                        log.error("Program \(seed.name, privacy: .public) references missing exercise slug \(exSeed.exerciseSlug, privacy: .public)")
                        continue
                    }
                    let pe = ProgramExercise(
                        orderIndex: exSeed.orderIndex,
                        targetSets: exSeed.targetSets,
                        targetRepsMin: exSeed.targetRepsMin,
                        targetRepsMax: exSeed.targetRepsMax,
                        restSeconds: exSeed.restSeconds,
                        notes: exSeed.notes,
                        exercise: exercise,
                        programDay: day
                    )
                    context.insert(pe)
                }
            }
            log.info("Seeded program: \(seed.name, privacy: .public)")
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
