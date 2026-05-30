import Foundation
import SwiftData

enum IronSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        IronSchemaV2.models
    }
}

enum IronSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 1, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            Program.self,
            ProgramDay.self,
            ProgramExercise.self,
            WarmupSet.self,
            Workout.self,
            SetEntry.self,
            ConditioningEntry.self,
            PersonalRecord.self,
            BodyMetric.self,
            NutritionEntry.self,
            NutritionTarget.self,
            UserSettings.self,
        ]
    }
}

enum IronSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 2, 0) }

    static var models: [any PersistentModel.Type] {
        IronSchemaV2.models + [
            DailyHealthSnapshot.self,
        ]
    }
}

enum IronMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [IronSchemaV2.self, IronSchemaV3.self]
    }

    static var stages: [MigrationStage] { [] }
}
