# Iron — SwiftData Schema

**Date:** 2026-04-30
**Target:** iOS 18+, watchOS 11+, Swift 6

## Design Principles

1. **Local-first** — SwiftData on-device, CloudKit sync free
2. **Append-only history** — workouts are immutable once finished
3. **Programs are templates** — workouts are instances; never edit a logged workout's "program"
4. **Soft delete** — every entity has `deletedAt: Date?` for sync conflict resolution
5. **Stable IDs** — UUIDs everywhere; no auto-increment

---

## Models

### Exercise
The library entry — what the user can do.

```swift
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String                    // "Barbell Back Squat"
    var slug: String                    // "barbell-back-squat"
    var category: ExerciseCategory      // .compound, .isolation, .conditioning
    var movementPattern: MovementPattern // .squat, .hinge, .push, .pull, .carry, .core, .conditioning
    var primaryMuscles: [Muscle]        // .quads, .glutes
    var secondaryMuscles: [Muscle]      // .hamstrings, .core
    var equipment: [Equipment]          // .barbell, .rack
    var instructions: String?
    var videoURL: URL?                  // optional demo video
    var isCustom: Bool                  // user-created vs library
    var createdAt: Date
    var deletedAt: Date?

    @Relationship(inverse: \SetEntry.exercise)
    var setEntries: [SetEntry] = []
}

enum ExerciseCategory: String, Codable {
    case compound, isolation, conditioning
}

enum MovementPattern: String, Codable {
    case squat, hinge, push, pull, carry, core, conditioning
}

enum Muscle: String, Codable, CaseIterable {
    case quads, glutes, hamstrings, calves
    case chest, lats, traps, rearDelts, sideDelts, frontDelts
    case biceps, triceps, forearms
    case core, lowerBack
    case fullBody
}

enum Equipment: String, Codable, CaseIterable {
    case barbell, dumbbell, kettlebell, machine, cable
    case bodyweight, band, rack, bench, box
    case treadmill, rower, bike, assault, ski
}
```

### Program
A reusable template. e.g. "5/3/1 BBB", "PPL Hypertrophy".

```swift
@Model
final class Program {
    @Attribute(.unique) var id: UUID
    var name: String
    var author: String?                 // "Jim Wendler" or nil for user-created
    var description: String?
    var isBuiltIn: Bool                 // shipped with app vs user-created
    var weeksLength: Int?               // nil = open-ended
    var createdAt: Date
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ProgramDay.program)
    var days: [ProgramDay] = []
}
```

### ProgramDay
A single day's template within a program.

```swift
@Model
final class ProgramDay {
    @Attribute(.unique) var id: UUID
    var name: String                    // "Monday — Squat Day", "Day 1 — Push"
    var weekIndex: Int?                 // for periodized programs (week 1, 2, 3)
    var dayIndex: Int                   // order within week
    var notes: String?
    var program: Program?

    @Relationship(deleteRule: .cascade, inverse: \ProgramExercise.programDay)
    var exercises: [ProgramExercise] = []
}
```

### ProgramExercise
A planned exercise slot in a program day.

```swift
@Model
final class ProgramExercise {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var targetSets: Int
    var targetRepsMin: Int
    var targetRepsMax: Int
    var targetRPE: Double?              // 7.5, 8, etc.
    var targetPercent1RM: Double?       // 0.85 for 5/3/1 type schemes
    var restSeconds: Int                // default rest timer
    var notes: String?
    var exercise: Exercise?
    var programDay: ProgramDay?
}
```

### Workout
A logged session. Immutable once `finishedAt` is set.

```swift
@Model
final class Workout {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var finishedAt: Date?               // nil = in progress
    var name: String?                   // user-set or derived from program day
    var notes: String?
    var bodyweightLb: Double?           // pulled from HealthKit at start
    var rpeOverall: Double?             // session RPE 0–10
    var sourceProgram: Program?         // reference; copy values, don't edit program
    var sourceProgramDay: ProgramDay?
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.workout)
    var setEntries: [SetEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ConditioningEntry.workout)
    var conditioningEntries: [ConditioningEntry] = []
}
```

### SetEntry
A single set within a workout.

```swift
@Model
final class SetEntry {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int                 // within exercise within workout
    var exerciseOrderIndex: Int         // exercise position in workout
    var setType: SetType                // .working, .warmup, .dropSet, .amrap, .restPause
    var reps: Int
    var weightLb: Double?
    var rpe: Double?                    // 0–10, half-points allowed
    var rir: Int?                       // reps in reserve, alternative to RPE
    var restSeconds: Int?               // actual rest taken
    var notes: String?
    var completedAt: Date
    var workout: Workout?
    var exercise: Exercise?
}

enum SetType: String, Codable {
    case working, warmup, dropSet, amrap, restPause, failure
}
```

### ConditioningEntry
Cardio/HIIT/intervals within a workout.

```swift
@Model
final class ConditioningEntry {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var modality: ConditioningModality   // .run, .row, .bike, .hiit, .interval, .ruck
    var durationSeconds: Int
    var distanceMeters: Double?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var caloriesActive: Int?
    var rpe: Double?
    var notes: String?
    var healthKitWorkoutUUID: UUID?      // link to HKWorkout if pulled from Health
    var completedAt: Date
    var workout: Workout?
}

enum ConditioningModality: String, Codable {
    case run, row, bike, hiit, interval, ruck, swim, ski, custom
}
```

### PersonalRecord
Materialized view of PRs for fast lookups.

```swift
@Model
final class PersonalRecord {
    @Attribute(.unique) var id: UUID
    var prType: PRType                  // .oneRM, .threeRM, .fiveRM, .e1RM, .volume, .amrapReps
    var value: Double                   // weight, reps, or volume
    var setEntry: SetEntry?             // the set that earned it
    var exercise: Exercise?
    var achievedAt: Date
    var deletedAt: Date?
}

enum PRType: String, Codable {
    case oneRM, threeRM, fiveRM, e1RM, volume, amrapReps
}
```

### UserSettings
Single-row config. Could be `@AppStorage` but model lets us sync via CloudKit.

```swift
@Model
final class UserSettings {
    @Attribute(.unique) var id: UUID    // always one row
    var weightUnit: WeightUnit          // .lb, .kg
    var distanceUnit: DistanceUnit      // .miles, .km
    var defaultRestSeconds: Int
    var plateConfigLb: [Double]         // [45, 35, 25, 10, 5, 2.5]
    var plateConfigKg: [Double]
    var hapticFeedback: Bool
    var watchAutoPause: Bool
    var firstDayOfWeek: Int             // 1 = Sunday, 2 = Monday
    var bodyweightSource: BodyweightSource // .healthKit, .manual
}

enum WeightUnit: String, Codable { case lb, kg }
enum DistanceUnit: String, Codable { case miles, km }
enum BodyweightSource: String, Codable { case healthKit, manual }
```

---

## Indexes (Performance)

Add `#Index` attributes for hot query paths:

```swift
extension Workout {
    @Index var startedAtIndex: Date { startedAt }
}

extension SetEntry {
    @Index var completedAtIndex: Date { completedAt }
}

extension PersonalRecord {
    @Index var exerciseAndType: String { "\(exercise?.id.uuidString ?? "")-\(prType.rawValue)" }
}
```

---

## CloudKit Sync

SwiftData → CloudKit is automatic when you set:
- All relationships are `optional` ✓
- All non-optional properties have defaults ✓
- No `@Attribute(.unique)` on non-id fields (CloudKit will reject) ✓
- Container is configured with `.private` database

```swift
let modelContainer = try ModelContainer(
    for: Workout.self, SetEntry.self, Exercise.self, /* ... */,
    configurations: ModelConfiguration(
        cloudKitDatabase: .private("iCloud.dev.highimpact.iron")
    )
)
```

---

## Migrations

Use `VersionedSchema` from day 1, even for v1. Schema migration is the #1 SwiftData footgun:

```swift
enum IronSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Exercise.self, Program.self, ProgramDay.self, ProgramExercise.self,
         Workout.self, SetEntry.self, ConditioningEntry.self,
         PersonalRecord.self, UserSettings.self]
    }
}
```

---

## Open Questions

- [ ] Should `Exercise` be CloudKit-synced or shipped as bundled JSON? (Lean: bundled JSON for built-ins, CloudKit for custom)
- [ ] How do we handle a user editing a built-in exercise? (Lean: copy-on-write into custom)
- [ ] Where do programs live? (Lean: shipped JSON for built-ins, CloudKit for custom + community shared)
- [ ] Coach mode multi-user: separate Convex schema, link via Sign in with Apple ID
