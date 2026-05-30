import XCTest
@testable import Iron

final class MealDraftTests: XCTestCase {
    func testDecodesMealDraftAndConvertsEntries() throws {
        let json = """
        {
          "transcript": "two eggs and oatmeal",
          "mealName": "Breakfast",
          "items": [
            {
              "foodName": "Eggs",
              "quantity": 2,
              "unit": "piece",
              "servingDescription": "2 large eggs",
              "calories": 140,
              "proteinG": 12,
              "carbsG": 1,
              "fatG": 10,
              "confidence": 0.9
            },
            {
              "foodName": "Oatmeal",
              "quantity": 1,
              "unit": "cup",
              "calories": 160,
              "proteinG": 6,
              "carbsG": 27,
              "fatG": 3
            }
          ]
        }
        """.data(using: .utf8)!

        let draft = try JSONDecoder().decode(MealDraft.self, from: json)
        let entries = draft.nutritionEntries(loggedAt: fixedDate(hour: 8))

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].mealName, "Breakfast")
        XCTAssertEqual(entries[0].foodName, "Eggs")
        XCTAssertEqual(entries[0].quantity, 2)
        XCTAssertEqual(entries[0].quantityUnit, "piece")
        XCTAssertEqual(entries[0].calories, 140)
        XCTAssertEqual(entries[1].carbsG, 27)
        XCTAssertTrue(entries[0].notes?.contains("AI voice estimate: two eggs and oatmeal") == true)
    }

    func testDefaultMealNamesUseLoggedAtHour() {
        XCTAssertEqual(MealDraft.defaultMealName(for: fixedDate(hour: 6)), "Breakfast")
        XCTAssertEqual(MealDraft.defaultMealName(for: fixedDate(hour: 12)), "Lunch")
        XCTAssertEqual(MealDraft.defaultMealName(for: fixedDate(hour: 18)), "Dinner")
        XCTAssertEqual(MealDraft.defaultMealName(for: fixedDate(hour: 23)), "Snack")
    }

    func testBlankMealNameDefaultsFromSelectedDate() throws {
        let draft = MealDraft(
            transcript: "chipotle bowl",
            mealName: " ",
            items: [
                MealDraftItem(foodName: "Chicken bowl", calories: 700, proteinG: 45, carbsG: 75, fatG: 22),
            ]
        )

        let entries = draft.nutritionEntries(loggedAt: fixedDate(hour: 13))

        XCTAssertEqual(entries.first?.mealName, "Lunch")
    }

    func testMalformedDraftSkipsMissingFoodsAndKeepsPartialMacros() throws {
        let json = """
        {
          "transcript": "",
          "items": [
            {
              "quantity": -2,
              "unit": "serving",
              "calories": "a lot",
              "proteinG": 10
            },
            {
              "foodName": "Protein shake",
              "quantity": "1.5",
              "unit": "serving",
              "calories": "240",
              "protein_g": "35",
              "carbs_g": "8",
              "fat_g": "3"
            }
          ]
        }
        """.data(using: .utf8)!

        let draft = try JSONDecoder().decode(MealDraft.self, from: json)
        let entries = draft.nutritionEntries(loggedAt: fixedDate(hour: 22))

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.foodName, "Protein shake")
        XCTAssertEqual(entries.first?.quantity, 1.5)
        XCTAssertEqual(entries.first?.calories, 240)
        XCTAssertEqual(entries.first?.proteinG, 35)
        XCTAssertEqual(entries.first?.mealName, "Snack")
    }

    func testProteinShakePlusBananaFixture() {
        let draft = MealDraft(
            transcript: "protein shake plus banana",
            mealName: nil,
            items: [
                MealDraftItem(foodName: "Protein shake", quantity: 1, unit: "serving", calories: 180, proteinG: 30, carbsG: 5, fatG: 3),
                MealDraftItem(foodName: "Banana", quantity: 1, unit: "piece", calories: 105, proteinG: 1, carbsG: 27, fatG: 0),
            ]
        )

        let entries = draft.nutritionEntries(loggedAt: fixedDate(hour: 16))

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.foodName), ["Protein shake", "Banana"])
        XCTAssertEqual(entries.reduce(0) { $0 + $1.calories }, 285)
        XCTAssertEqual(entries.first?.mealName, "Dinner")
    }

    func testDecodesTopLevelFoodArrayFromGemini() throws {
        let json = """
        [
          {
            "foodName": "Greek yogurt",
            "quantity": 1,
            "unit": "cup",
            "calories": 150,
            "proteinG": 20,
            "carbsG": 8,
            "fatG": 4
          }
        ]
        """.data(using: .utf8)!

        let draft = try JSONDecoder().decode(MealDraft.self, from: json)
        let entries = draft.nutritionEntries(loggedAt: fixedDate(hour: 12))

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.mealName, "Lunch")
        XCTAssertEqual(entries.first?.foodName, "Greek yogurt")
    }

    func testDecodesAlternateGeminiKeys() throws {
        let json = """
        {
          "text": "chicken rice bowl",
          "meal_name": "Dinner",
          "foods": [
            {
              "name": "Chicken rice bowl",
              "quantity": 1,
              "quantityUnit": "bowl",
              "calories": 650,
              "protein_g": 45,
              "carbs_g": 70,
              "fat_g": 18
            }
          ]
        }
        """.data(using: .utf8)!

        let draft = try JSONDecoder().decode(MealDraft.self, from: json)
        let entries = draft.nutritionEntries(loggedAt: fixedDate(hour: 18))

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.mealName, "Dinner")
        XCTAssertEqual(entries.first?.foodName, "Chicken rice bowl")
        XCTAssertTrue(entries.first?.notes?.contains("AI voice estimate: chicken rice bowl") == true)
    }

    func testDecodesGeminiObjectWithMicronutrients() throws {
        let json = """
        {
          "transcript": "one large avocado, 29 grams of baked sweet potato",
          "mealName": "Dinner",
          "items": [
            {
              "foodName": "avocado",
              "quantity": 1,
              "unit": "large",
              "calories": 322,
              "proteinG": 4,
              "carbsG": 17,
              "fatG": 29,
              "fiberG": 13.5,
              "sugarG": 1.3
            },
            {
              "foodName": "baked sweet potato",
              "quantity": 29,
              "unit": "g",
              "calories": 26,
              "proteinG": 0.5,
              "carbsG": 6,
              "fatG": 0
            }
          ]
        }
        """.data(using: .utf8)!

        let draft = try JSONDecoder().decode(MealDraft.self, from: json)
        let entries = draft.nutritionEntries(loggedAt: fixedDate(hour: 18))

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.mealName, "Dinner")
        XCTAssertEqual(entries.first?.quantityUnit, "large")
        XCTAssertEqual(entries.first?.fiberG, 13.5)
    }

    func testGeminiServiceFallbackDecodesScreenshotShape() throws {
        let json = """
        {
          "transcript": "one large avocado, 29 grams of baked sweet potato",
          "mealName": "Dinner",
          "items": [
            {
              "foodName": "avocado",
              "quantity": 1,
              "unit": "large",
              "calories": 322,
              "proteinG": 4,
              "carbsG": 17,
              "fatG": 29,
              "fiberG": 13.5,
              "sugarG": 1.3,
              "sodiumMg": 14,
              "potassiumMg": 975,
              "calciumMg": 24,
              "ironMg": 1.1,
              "vitaminDMcg": 0,
              "cholesterolMg": 0
            }
          ]
        }
        """.data(using: .utf8)!

        let draft = try GeminiNutritionService.decodeDraft(from: json)
        let entries = draft.nutritionEntries(loggedAt: fixedDate(hour: 18))

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.foodName, "avocado")
        XCTAssertEqual(entries.first?.calories, 322)
        XCTAssertEqual(entries.first?.potassiumMg, 975)
    }

    private func fixedDate(hour: Int) -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.calendar = calendar
        components.year = 2026
        components.month = 5
        components.day = 29
        components.hour = hour
        return components.date!
    }
}
