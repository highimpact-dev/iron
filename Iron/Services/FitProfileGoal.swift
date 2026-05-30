import Foundation

// Map a FitProfileReport from FitProfile to your existing NutritionGoal.
func goal(from report: FitProfileReport) -> NutritionGoal {
    // Negative fatMassControlLb → app should be in fat-loss mode.
    if let fat = report.fatMassControlLb, fat < 0 {
        return .fatLoss
    }

    // Positive weightControlLb (and not in fat-loss) → muscle gain / weight gain.
    if let weight = report.weightControlLb, weight > 0 {
        return .muscleGain
    }

    // Otherwise treat as maintenance.
    return .maintenance
}



//
//  FitProfileGoal.swift
//  Iron
//
//  Created by Douglas Marzean on 5/29/26.
//

