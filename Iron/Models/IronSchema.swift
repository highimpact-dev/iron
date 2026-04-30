import Foundation
import SwiftData

enum IronSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            Program.self,
            ProgramDay.self,
            ProgramExercise.self,
            Workout.self,
            SetEntry.self,
            ConditioningEntry.self,
            PersonalRecord.self,
            UserSettings.self,
        ]
    }
}

enum IronMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [IronSchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}
