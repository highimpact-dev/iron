import Foundation

struct USDAFoodDataPreferenceKeys {
    static let apiKey = "usdaFoodData.apiKey"
}

actor USDAFoodDataService {
    static let shared = USDAFoodDataService()

    private let decoder = JSONDecoder()
    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ query: String, apiKey: String? = nil) async throws -> [OpenFoodFactsFood] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let resolvedKey = try resolvedAPIKey(apiKey)
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: resolvedKey),
            URLQueryItem(name: "query", value: normalized),
            URLQueryItem(name: "pageSize", value: "20"),
        ]
        guard let url = components?.url else { return [] }

        let response: SearchResponse = try await fetch(url)
        return response.foods.compactMap(\.foodLookup)
    }

    func lookupBarcode(_ barcode: String, apiKey: String? = nil) async throws -> OpenFoodFactsFood? {
        let normalized = barcode.filter(\.isNumber)
        guard !normalized.isEmpty else { return nil }
        let results = try await search(normalized, apiKey: apiKey)
        return results.first { $0.barcode == normalized } ?? results.first
    }

    private func resolvedAPIKey(_ apiKey: String?) throws -> String {
        let explicit = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit, !explicit.isEmpty { return explicit }

        let stored = UserDefaults.standard
            .string(forKey: USDAFoodDataPreferenceKeys.apiKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }

        throw USDAFoodDataError.missingAPIKey
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Iron/0.1.0 (dev.highimpact.iron)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw USDAFoodDataError.serverStatus(http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
}

enum USDAFoodDataError: LocalizedError {
    case missingAPIKey
    case serverStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your USDA FoodData Central API key in Settings."
        case .serverStatus(let status):
            return "USDA FoodData Central returned status \(status)."
        }
    }
}

private struct SearchResponse: Decodable {
    let foods: [USDAFood]
}

private struct USDAFood: Decodable {
    let fdcId: Int
    let description: String
    let brandOwner: String?
    let brandName: String?
    let gtinUpc: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let foodNutrients: [USDANutrient]

    var foodLookup: OpenFoodFactsFood? {
        guard let calories = nutrient(.calories, servingFactor: servingFactor) else { return nil }
        let barcode = gtinUpc ?? "fdc-\(fdcId)"

        return OpenFoodFactsFood(
            id: "usda-\(fdcId)",
            barcode: barcode,
            name: description.capitalized,
            brand: brandName ?? brandOwner,
            serving: servingText,
            servingGrams: servingGrams,
            calories: calories,
            proteinG: nutrient(.protein, servingFactor: servingFactor) ?? 0,
            carbsG: nutrient(.carbohydrate, servingFactor: servingFactor) ?? 0,
            fatG: nutrient(.fat, servingFactor: servingFactor) ?? 0,
            fiberG: nutrient(.fiber, servingFactor: servingFactor),
            sugarG: nutrient(.sugar, servingFactor: servingFactor),
            saturatedFatG: nutrient(.saturatedFat, servingFactor: servingFactor),
            monounsaturatedFatG: nutrient(.monounsaturatedFat, servingFactor: servingFactor),
            polyunsaturatedFatG: nutrient(.polyunsaturatedFat, servingFactor: servingFactor),
            transFatG: nutrient(.transFat, servingFactor: servingFactor),
            omega3G: nutrient(.omega3, servingFactor: servingFactor),
            alaOmega3G: nutrient(.ala, servingFactor: servingFactor),
            epaOmega3G: nutrient(.epa, servingFactor: servingFactor),
            dpaOmega3G: nutrient(.dpa, servingFactor: servingFactor),
            dhaOmega3G: nutrient(.dha, servingFactor: servingFactor),
            omega6G: nutrient(.omega6, servingFactor: servingFactor),
            linoleicAcidG: nutrient(.linoleic, servingFactor: servingFactor),
            arachidonicAcidG: nutrient(.arachidonic, servingFactor: servingFactor),
            omega9G: nutrient(.oleic, servingFactor: servingFactor),
            sodiumMg: nutrient(.sodium, servingFactor: servingFactor),
            potassiumMg: nutrient(.potassium, servingFactor: servingFactor),
            calciumMg: nutrient(.calcium, servingFactor: servingFactor),
            ironMg: nutrient(.iron, servingFactor: servingFactor),
            magnesiumMg: nutrient(.magnesium, servingFactor: servingFactor),
            phosphorusMg: nutrient(.phosphorus, servingFactor: servingFactor),
            zincMg: nutrient(.zinc, servingFactor: servingFactor),
            seleniumMcg: nutrient(.selenium, servingFactor: servingFactor),
            copperMg: nutrient(.copper, servingFactor: servingFactor),
            manganeseMg: nutrient(.manganese, servingFactor: servingFactor),
            iodineMcg: nutrient(.iodine, servingFactor: servingFactor),
            vitaminAMcg: nutrient(.vitaminA, servingFactor: servingFactor),
            vitaminCMg: nutrient(.vitaminC, servingFactor: servingFactor),
            vitaminDMcg: nutrient(.vitaminD, servingFactor: servingFactor),
            vitaminEMg: nutrient(.vitaminE, servingFactor: servingFactor),
            vitaminKMcg: nutrient(.vitaminK, servingFactor: servingFactor),
            thiaminMg: nutrient(.thiamin, servingFactor: servingFactor),
            riboflavinMg: nutrient(.riboflavin, servingFactor: servingFactor),
            niacinMg: nutrient(.niacin, servingFactor: servingFactor),
            pantothenicAcidMg: nutrient(.pantothenicAcid, servingFactor: servingFactor),
            vitaminB6Mg: nutrient(.vitaminB6, servingFactor: servingFactor),
            biotinMcg: nutrient(.biotin, servingFactor: servingFactor),
            folateMcg: nutrient(.folate, servingFactor: servingFactor),
            folicAcidMcg: nutrient(.folicAcid, servingFactor: servingFactor),
            vitaminB12Mcg: nutrient(.vitaminB12, servingFactor: servingFactor),
            cholineMg: nutrient(.choline, servingFactor: servingFactor),
            cholesterolMg: nutrient(.cholesterol, servingFactor: servingFactor)
        )
    }

    private var servingText: String? {
        guard let servingSize else { return nil }
        let unit = servingSizeUnit ?? "g"
        return "\(formatServing(servingSize)) \(unit)"
    }

    private var servingGrams: Double? {
        guard let servingSize else { return nil }
        let unit = servingSizeUnit?.lowercased() ?? "g"
        switch unit {
        case "g", "gram", "grams":
            return servingSize
        case "kg", "kilogram", "kilograms":
            return servingSize * 1000
        case "mg", "milligram", "milligrams":
            return servingSize / 1000
        case "oz", "ounce", "ounces":
            return servingSize * 28.3495
        default:
            return nil
        }
    }

    private var servingFactor: Double? {
        nil
    }

    private func nutrient(_ type: NutrientKind, servingFactor: Double?) -> Double? {
        guard let raw = foodNutrients.first(where: { type.matches($0) })?.value else { return nil }
        return servingFactor.map { raw * $0 } ?? raw
    }

    private func formatServing(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

private struct USDANutrient: Decodable {
    let nutrientId: Int?
    let nutrientName: String?
    let nutrientNumber: String?
    let unitName: String?
    let value: Double?
}

private enum NutrientKind {
    case calories
    case protein
    case carbohydrate
    case fat
    case fiber
    case sugar
    case saturatedFat
    case monounsaturatedFat
    case polyunsaturatedFat
    case transFat
    case omega3
    case ala
    case epa
    case dpa
    case dha
    case omega6
    case linoleic
    case arachidonic
    case oleic
    case sodium
    case potassium
    case calcium
    case iron
    case magnesium
    case phosphorus
    case zinc
    case selenium
    case copper
    case manganese
    case iodine
    case vitaminA
    case vitaminC
    case vitaminD
    case vitaminE
    case vitaminK
    case thiamin
    case riboflavin
    case niacin
    case pantothenicAcid
    case vitaminB6
    case biotin
    case folate
    case folicAcid
    case vitaminB12
    case choline
    case cholesterol

    func matches(_ nutrient: USDANutrient) -> Bool {
        if let nutrientId = nutrient.nutrientId, ids.contains(nutrientId) {
            return true
        }
        let name = nutrient.nutrientName?.lowercased() ?? ""
        return names.contains { name.contains($0) }
    }

    private var ids: Set<Int> {
        switch self {
        case .calories: return [1008, 2047, 2048]
        case .protein: return [1003]
        case .carbohydrate: return [1005, 1050]
        case .fat: return [1004]
        case .fiber: return [1079]
        case .sugar: return [2000, 1063]
        case .saturatedFat: return [1258]
        case .monounsaturatedFat: return [1292]
        case .polyunsaturatedFat: return [1293]
        case .transFat: return [1257]
        case .omega3: return []
        case .ala: return [1404]
        case .epa: return [1278]
        case .dpa: return [1280]
        case .dha: return [1272]
        case .omega6: return []
        case .linoleic: return [1269]
        case .arachidonic: return [1274]
        case .oleic: return [1268]
        case .sodium: return [1093]
        case .potassium: return [1092]
        case .calcium: return [1087]
        case .iron: return [1089]
        case .magnesium: return [1090]
        case .phosphorus: return [1091]
        case .zinc: return [1095]
        case .selenium: return [1103]
        case .copper: return [1098]
        case .manganese: return [1101]
        case .iodine: return [1100]
        case .vitaminA: return [1106]
        case .vitaminC: return [1162]
        case .vitaminD: return [1114]
        case .vitaminE: return [1109]
        case .vitaminK: return [1185]
        case .thiamin: return [1165]
        case .riboflavin: return [1166]
        case .niacin: return [1167]
        case .pantothenicAcid: return [1170]
        case .vitaminB6: return [1175]
        case .biotin: return [1176]
        case .folate: return [1190, 1177]
        case .folicAcid: return [1177]
        case .vitaminB12: return [1178]
        case .choline: return [1180]
        case .cholesterol: return [1253]
        }
    }

    private var names: [String] {
        switch self {
        case .calories: return ["energy"]
        case .protein: return ["protein"]
        case .carbohydrate: return ["carbohydrate"]
        case .fat: return ["total lipid", "total fat"]
        case .fiber: return ["fiber"]
        case .sugar: return ["sugars"]
        case .saturatedFat: return ["saturated"]
        case .monounsaturatedFat: return ["monounsaturated"]
        case .polyunsaturatedFat: return ["polyunsaturated"]
        case .transFat: return ["trans"]
        case .omega3: return ["omega-3", "omega 3"]
        case .ala: return ["alpha-linolenic"]
        case .epa: return ["eicosapentaenoic"]
        case .dpa: return ["docosapentaenoic"]
        case .dha: return ["docosahexaenoic"]
        case .omega6: return ["omega-6", "omega 6"]
        case .linoleic: return ["linoleic"]
        case .arachidonic: return ["arachidonic"]
        case .oleic: return ["oleic"]
        case .sodium: return ["sodium"]
        case .potassium: return ["potassium"]
        case .calcium: return ["calcium"]
        case .iron: return ["iron"]
        case .magnesium: return ["magnesium"]
        case .phosphorus: return ["phosphorus"]
        case .zinc: return ["zinc"]
        case .selenium: return ["selenium"]
        case .copper: return ["copper"]
        case .manganese: return ["manganese"]
        case .iodine: return ["iodine"]
        case .vitaminA: return ["vitamin a"]
        case .vitaminC: return ["vitamin c", "ascorbic"]
        case .vitaminD: return ["vitamin d"]
        case .vitaminE: return ["vitamin e", "tocopherol"]
        case .vitaminK: return ["vitamin k"]
        case .thiamin: return ["thiamin", "vitamin b1"]
        case .riboflavin: return ["riboflavin", "vitamin b2"]
        case .niacin: return ["niacin"]
        case .pantothenicAcid: return ["pantothenic"]
        case .vitaminB6: return ["vitamin b-6", "vitamin b6"]
        case .biotin: return ["biotin"]
        case .folate: return ["folate"]
        case .folicAcid: return ["folic acid"]
        case .vitaminB12: return ["vitamin b-12", "vitamin b12"]
        case .choline: return ["choline"]
        case .cholesterol: return ["cholesterol"]
        }
    }
}
