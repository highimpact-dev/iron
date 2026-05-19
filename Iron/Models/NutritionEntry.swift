import Foundation
import SwiftData

@Model
final class NutritionEntry {
    var id: UUID = UUID()
    var loggedAt: Date = Date()
    var mealName: String = "Meal"
    var foodName: String = ""
    var servingDescription: String?
    var quantity: Double = 1
    var quantityUnit: String = "serving"
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fiberG: Double?
    var sugarG: Double?
    var saturatedFatG: Double?
    var monounsaturatedFatG: Double?
    var polyunsaturatedFatG: Double?
    var transFatG: Double?
    var omega3G: Double?
    var alaOmega3G: Double?
    var epaOmega3G: Double?
    var dpaOmega3G: Double?
    var dhaOmega3G: Double?
    var omega6G: Double?
    var linoleicAcidG: Double?
    var arachidonicAcidG: Double?
    var omega9G: Double?
    var sodiumMg: Double?
    var potassiumMg: Double?
    var calciumMg: Double?
    var ironMg: Double?
    var magnesiumMg: Double?
    var phosphorusMg: Double?
    var zincMg: Double?
    var seleniumMcg: Double?
    var copperMg: Double?
    var manganeseMg: Double?
    var iodineMcg: Double?
    var vitaminAMcg: Double?
    var vitaminCMg: Double?
    var vitaminDMcg: Double?
    var vitaminEMg: Double?
    var vitaminKMcg: Double?
    var thiaminMg: Double?
    var riboflavinMg: Double?
    var niacinMg: Double?
    var pantothenicAcidMg: Double?
    var vitaminB6Mg: Double?
    var biotinMcg: Double?
    var folateMcg: Double?
    var folicAcidMcg: Double?
    var vitaminB12Mcg: Double?
    var cholineMg: Double?
    var cholesterolMg: Double?
    var notes: String?
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        loggedAt: Date = Date(),
        mealName: String = "Meal",
        foodName: String,
        servingDescription: String? = nil,
        quantity: Double = 1,
        quantityUnit: String = "serving",
        calories: Double = 0,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        saturatedFatG: Double? = nil,
        monounsaturatedFatG: Double? = nil,
        polyunsaturatedFatG: Double? = nil,
        transFatG: Double? = nil,
        omega3G: Double? = nil,
        alaOmega3G: Double? = nil,
        epaOmega3G: Double? = nil,
        dpaOmega3G: Double? = nil,
        dhaOmega3G: Double? = nil,
        omega6G: Double? = nil,
        linoleicAcidG: Double? = nil,
        arachidonicAcidG: Double? = nil,
        omega9G: Double? = nil,
        sodiumMg: Double? = nil,
        potassiumMg: Double? = nil,
        calciumMg: Double? = nil,
        ironMg: Double? = nil,
        magnesiumMg: Double? = nil,
        phosphorusMg: Double? = nil,
        zincMg: Double? = nil,
        seleniumMcg: Double? = nil,
        copperMg: Double? = nil,
        manganeseMg: Double? = nil,
        iodineMcg: Double? = nil,
        vitaminAMcg: Double? = nil,
        vitaminCMg: Double? = nil,
        vitaminDMcg: Double? = nil,
        vitaminEMg: Double? = nil,
        vitaminKMcg: Double? = nil,
        thiaminMg: Double? = nil,
        riboflavinMg: Double? = nil,
        niacinMg: Double? = nil,
        pantothenicAcidMg: Double? = nil,
        vitaminB6Mg: Double? = nil,
        biotinMcg: Double? = nil,
        folateMcg: Double? = nil,
        folicAcidMcg: Double? = nil,
        vitaminB12Mcg: Double? = nil,
        cholineMg: Double? = nil,
        cholesterolMg: Double? = nil,
        notes: String? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.mealName = mealName
        self.foodName = foodName
        self.servingDescription = servingDescription
        self.quantity = quantity
        self.quantityUnit = quantityUnit
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.saturatedFatG = saturatedFatG
        self.monounsaturatedFatG = monounsaturatedFatG
        self.polyunsaturatedFatG = polyunsaturatedFatG
        self.transFatG = transFatG
        self.omega3G = omega3G
        self.alaOmega3G = alaOmega3G
        self.epaOmega3G = epaOmega3G
        self.dpaOmega3G = dpaOmega3G
        self.dhaOmega3G = dhaOmega3G
        self.omega6G = omega6G
        self.linoleicAcidG = linoleicAcidG
        self.arachidonicAcidG = arachidonicAcidG
        self.omega9G = omega9G
        self.sodiumMg = sodiumMg
        self.potassiumMg = potassiumMg
        self.calciumMg = calciumMg
        self.ironMg = ironMg
        self.magnesiumMg = magnesiumMg
        self.phosphorusMg = phosphorusMg
        self.zincMg = zincMg
        self.seleniumMcg = seleniumMcg
        self.copperMg = copperMg
        self.manganeseMg = manganeseMg
        self.iodineMcg = iodineMcg
        self.vitaminAMcg = vitaminAMcg
        self.vitaminCMg = vitaminCMg
        self.vitaminDMcg = vitaminDMcg
        self.vitaminEMg = vitaminEMg
        self.vitaminKMcg = vitaminKMcg
        self.thiaminMg = thiaminMg
        self.riboflavinMg = riboflavinMg
        self.niacinMg = niacinMg
        self.pantothenicAcidMg = pantothenicAcidMg
        self.vitaminB6Mg = vitaminB6Mg
        self.biotinMcg = biotinMcg
        self.folateMcg = folateMcg
        self.folicAcidMcg = folicAcidMcg
        self.vitaminB12Mcg = vitaminB12Mcg
        self.cholineMg = cholineMg
        self.cholesterolMg = cholesterolMg
        self.notes = notes
        self.deletedAt = deletedAt
    }
}

extension NutritionEntry {
    var macroCalories: Double {
        proteinG * 4 + carbsG * 4 + fatG * 9
    }

    var netCarbsG: Double {
        max(0, carbsG - (fiberG ?? 0))
    }

    var hasMicronutrients: Bool {
        saturatedFatG != nil
            || monounsaturatedFatG != nil
            || polyunsaturatedFatG != nil
            || transFatG != nil
            || omega3G != nil
            || alaOmega3G != nil
            || epaOmega3G != nil
            || dpaOmega3G != nil
            || dhaOmega3G != nil
            || omega6G != nil
            || linoleicAcidG != nil
            || arachidonicAcidG != nil
            || omega9G != nil
            || sugarG != nil
            || sodiumMg != nil
            || potassiumMg != nil
            || calciumMg != nil
            || ironMg != nil
            || magnesiumMg != nil
            || phosphorusMg != nil
            || zincMg != nil
            || seleniumMcg != nil
            || copperMg != nil
            || manganeseMg != nil
            || iodineMcg != nil
            || vitaminAMcg != nil
            || vitaminCMg != nil
            || vitaminDMcg != nil
            || vitaminEMg != nil
            || vitaminKMcg != nil
            || thiaminMg != nil
            || riboflavinMg != nil
            || niacinMg != nil
            || pantothenicAcidMg != nil
            || vitaminB6Mg != nil
            || biotinMcg != nil
            || folateMcg != nil
            || folicAcidMcg != nil
            || vitaminB12Mcg != nil
            || cholineMg != nil
            || cholesterolMg != nil
    }
}
