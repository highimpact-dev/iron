import Foundation
import SwiftData

enum NutritionGoal: String, Codable, CaseIterable, Identifiable {
    case fatLoss
    case maintenance
    case muscleGain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fatLoss: return "Fat loss"
        case .maintenance: return "Maintenance"
        case .muscleGain: return "Muscle gain"
        }
    }

    var calorieAdjustment: Double {
        switch self {
        case .fatLoss: return -500
        case .maintenance: return 0
        case .muscleGain: return 250
        }
    }
}

@Model
final class NutritionTarget {
    var id: UUID = UUID()
    var effectiveDate: Date = Date()
    var goal: NutritionGoal = NutritionGoal.maintenance
    var calories: Double = 2400
    var proteinG: Double = 180
    var carbsG: Double = 250
    var fatG: Double = 70
    var notes: String?
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        effectiveDate: Date = Date(),
        goal: NutritionGoal = .maintenance,
        calories: Double = 2400,
        proteinG: Double = 180,
        carbsG: Double = 250,
        fatG: Double = 70,
        notes: String? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.effectiveDate = effectiveDate
        self.goal = goal
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.notes = notes
        self.deletedAt = deletedAt
    }
}
