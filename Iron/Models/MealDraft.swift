import Foundation

struct MealDraft: Identifiable, Codable, Sendable {
    let id: UUID
    var transcript: String
    var mealName: String?
    var items: [MealDraftItem]

    enum CodingKeys: String, CodingKey {
        case transcript
        case text
        case mealName
        case meal_name
        case items
        case foods
        case foodItems
        case entries
        case draft
        case mealDraft
    }

    init(
        id: UUID = UUID(),
        transcript: String = "",
        mealName: String? = nil,
        items: [MealDraftItem] = []
    ) {
        self.id = id
        self.transcript = transcript
        self.mealName = mealName
        self.items = items
    }

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var decodedItems: [MealDraftItem] = []
            while !unkeyed.isAtEnd {
                if let item = try? unkeyed.decode(MealDraftItem.self) {
                    decodedItems.append(item)
                } else {
                    _ = try? unkeyed.decode(DiscardedJSONValue.self)
                }
            }
            self.id = UUID()
            self.transcript = ""
            self.mealName = nil
            self.items = decodedItems
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = (try? container.decode(MealDraft.self, forKey: .draft))
            ?? (try? container.decode(MealDraft.self, forKey: .mealDraft)) {
            self = nested
            return
        }

        self.id = UUID()
        self.transcript = container.trimmedString(for: .transcript) ?? container.trimmedString(for: .text) ?? ""
        self.mealName = container.trimmedString(for: .mealName) ?? container.trimmedString(for: .meal_name)
        self.items = (try? container.decode([MealDraftItem].self, forKey: .items))
            ?? (try? container.decode([MealDraftItem].self, forKey: .foods))
            ?? (try? container.decode([MealDraftItem].self, forKey: .foodItems))
            ?? (try? container.decode([MealDraftItem].self, forKey: .entries))
            ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transcript, forKey: .transcript)
        try container.encodeIfPresent(mealName, forKey: .mealName)
        try container.encode(items, forKey: .items)
    }

    func nutritionEntries(loggedAt: Date, calendar: Calendar = .current) -> [NutritionEntry] {
        let resolvedMealName = normalizedMealName ?? Self.defaultMealName(for: loggedAt, calendar: calendar)
        return items.compactMap { item in
            item.nutritionEntry(
                loggedAt: loggedAt,
                mealName: resolvedMealName,
                transcript: transcript
            )
        }
    }

    var normalizedMealName: String? {
        let trimmed = mealName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func defaultMealName(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5 ... 10:
            return "Breakfast"
        case 11 ... 15:
            return "Lunch"
        case 16 ... 21:
            return "Dinner"
        default:
            return "Snack"
        }
    }
}

struct MealDraftItem: Identifiable, Codable, Sendable {
    let id: UUID
    var foodName: String?
    var quantity: Double?
    var unit: String?
    var servingDescription: String?
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var fiberG: Double?
    var sugarG: Double?
    var sodiumMg: Double?
    var potassiumMg: Double?
    var calciumMg: Double?
    var ironMg: Double?
    var vitaminDMcg: Double?
    var cholesterolMg: Double?
    var confidence: Double?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case foodName
        case name
        case quantity
        case unit
        case quantityUnit
        case servingDescription
        case serving
        case calories
        case proteinG
        case protein_g
        case carbsG
        case carbs_g
        case fatG
        case fat_g
        case fiberG
        case fiber_g
        case sugarG
        case sugar_g
        case sodiumMg
        case sodium_mg
        case potassiumMg
        case potassium_mg
        case calciumMg
        case calcium_mg
        case ironMg
        case iron_mg
        case vitaminDMcg
        case vitamin_d_mcg
        case cholesterolMg
        case cholesterol_mg
        case confidence
        case notes
    }

    init(
        id: UUID = UUID(),
        foodName: String? = nil,
        quantity: Double? = nil,
        unit: String? = nil,
        servingDescription: String? = nil,
        calories: Double? = nil,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatG: Double? = nil,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        sodiumMg: Double? = nil,
        potassiumMg: Double? = nil,
        calciumMg: Double? = nil,
        ironMg: Double? = nil,
        vitaminDMcg: Double? = nil,
        cholesterolMg: Double? = nil,
        confidence: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.foodName = foodName
        self.quantity = quantity
        self.unit = unit
        self.servingDescription = servingDescription
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
        self.confidence = confidence
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.foodName = container.trimmedString(for: .foodName) ?? container.trimmedString(for: .name)
        self.quantity = container.nonNegativeDouble(for: .quantity)
        self.unit = container.trimmedString(for: .unit) ?? container.trimmedString(for: .quantityUnit)
        self.servingDescription = container.trimmedString(for: .servingDescription) ?? container.trimmedString(for: .serving)
        self.calories = container.nonNegativeDouble(for: .calories)
        self.proteinG = container.nonNegativeDouble(for: .proteinG) ?? container.nonNegativeDouble(for: .protein_g)
        self.carbsG = container.nonNegativeDouble(for: .carbsG) ?? container.nonNegativeDouble(for: .carbs_g)
        self.fatG = container.nonNegativeDouble(for: .fatG) ?? container.nonNegativeDouble(for: .fat_g)
        self.fiberG = container.nonNegativeDouble(for: .fiberG) ?? container.nonNegativeDouble(for: .fiber_g)
        self.sugarG = container.nonNegativeDouble(for: .sugarG) ?? container.nonNegativeDouble(for: .sugar_g)
        self.sodiumMg = container.nonNegativeDouble(for: .sodiumMg) ?? container.nonNegativeDouble(for: .sodium_mg)
        self.potassiumMg = container.nonNegativeDouble(for: .potassiumMg) ?? container.nonNegativeDouble(for: .potassium_mg)
        self.calciumMg = container.nonNegativeDouble(for: .calciumMg) ?? container.nonNegativeDouble(for: .calcium_mg)
        self.ironMg = container.nonNegativeDouble(for: .ironMg) ?? container.nonNegativeDouble(for: .iron_mg)
        self.vitaminDMcg = container.nonNegativeDouble(for: .vitaminDMcg) ?? container.nonNegativeDouble(for: .vitamin_d_mcg)
        self.cholesterolMg = container.nonNegativeDouble(for: .cholesterolMg) ?? container.nonNegativeDouble(for: .cholesterol_mg)
        self.confidence = container.clampedDouble(for: .confidence, range: 0 ... 1)
        self.notes = container.trimmedString(for: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(foodName, forKey: .foodName)
        try container.encodeIfPresent(quantity, forKey: .quantity)
        try container.encodeIfPresent(unit, forKey: .unit)
        try container.encodeIfPresent(servingDescription, forKey: .servingDescription)
        try container.encodeIfPresent(calories, forKey: .calories)
        try container.encodeIfPresent(proteinG, forKey: .proteinG)
        try container.encodeIfPresent(carbsG, forKey: .carbsG)
        try container.encodeIfPresent(fatG, forKey: .fatG)
        try container.encodeIfPresent(fiberG, forKey: .fiberG)
        try container.encodeIfPresent(sugarG, forKey: .sugarG)
        try container.encodeIfPresent(sodiumMg, forKey: .sodiumMg)
        try container.encodeIfPresent(potassiumMg, forKey: .potassiumMg)
        try container.encodeIfPresent(calciumMg, forKey: .calciumMg)
        try container.encodeIfPresent(ironMg, forKey: .ironMg)
        try container.encodeIfPresent(vitaminDMcg, forKey: .vitaminDMcg)
        try container.encodeIfPresent(cholesterolMg, forKey: .cholesterolMg)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(notes, forKey: .notes)
    }

    var normalizedFoodName: String? {
        let trimmed = foodName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    var resolvedQuantity: Double {
        guard let quantity, quantity.isFinite, quantity > 0 else { return 1 }
        return quantity
    }

    var resolvedUnit: String {
        guard let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return "serving"
        }
        return trimmed
    }

    func nutritionEntry(loggedAt: Date, mealName: String, transcript: String) -> NutritionEntry? {
        guard let foodName = normalizedFoodName else { return nil }
        return NutritionEntry(
            loggedAt: loggedAt,
            mealName: mealName,
            foodName: foodName,
            servingDescription: servingDescription?.nilIfBlank,
            quantity: resolvedQuantity,
            quantityUnit: resolvedUnit,
            calories: calories ?? 0,
            proteinG: proteinG ?? 0,
            carbsG: carbsG ?? 0,
            fatG: fatG ?? 0,
            fiberG: fiberG,
            sugarG: sugarG,
            sodiumMg: sodiumMg,
            potassiumMg: potassiumMg,
            calciumMg: calciumMg,
            ironMg: ironMg,
            vitaminDMcg: vitaminDMcg,
            cholesterolMg: cholesterolMg,
            notes: estimateNote(transcript: transcript)
        )
    }

    private func estimateNote(transcript: String) -> String {
        let base = transcript.nilIfBlank.map { "AI voice estimate: \($0)" } ?? "AI voice estimate"
        guard let notes = notes?.nilIfBlank else { return base }
        return "\(base); \(notes)"
    }
}

private extension KeyedDecodingContainer where Key: CodingKey {
    func trimmedString(for key: Key) -> String? {
        guard let value = try? decode(String.self, forKey: key) else { return nil }
        return value.nilIfBlank
    }

    func nonNegativeDouble(for key: Key) -> Double? {
        guard let value = flexibleDouble(for: key), value.isFinite else { return nil }
        return max(0, value)
    }

    func clampedDouble(for key: Key, range: ClosedRange<Double>) -> Double? {
        guard let value = flexibleDouble(for: key), value.isFinite else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func flexibleDouble(for key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        guard let stringValue = try? decode(String.self, forKey: key) else {
            return nil
        }
        return Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct DiscardedJSONValue: Decodable {}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
