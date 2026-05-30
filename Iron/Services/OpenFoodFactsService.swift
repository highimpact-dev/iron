import Foundation

struct OpenFoodFactsFood: Identifiable, Hashable, Sendable {
    let id: String
    let barcode: String
    let name: String
    let brand: String?
    let serving: String?
    let servingGrams: Double?
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double?
    let sugarG: Double?
    let saturatedFatG: Double?
    let monounsaturatedFatG: Double?
    let polyunsaturatedFatG: Double?
    let transFatG: Double?
    let omega3G: Double?
    let alaOmega3G: Double?
    let epaOmega3G: Double?
    let dpaOmega3G: Double?
    let dhaOmega3G: Double?
    let omega6G: Double?
    let linoleicAcidG: Double?
    let arachidonicAcidG: Double?
    let omega9G: Double?
    let sodiumMg: Double?
    let potassiumMg: Double?
    let calciumMg: Double?
    let ironMg: Double?
    let magnesiumMg: Double?
    let phosphorusMg: Double?
    let zincMg: Double?
    let seleniumMcg: Double?
    let copperMg: Double?
    let manganeseMg: Double?
    let iodineMcg: Double?
    let vitaminAMcg: Double?
    let vitaminCMg: Double?
    let vitaminDMcg: Double?
    let vitaminEMg: Double?
    let vitaminKMcg: Double?
    let thiaminMg: Double?
    let riboflavinMg: Double?
    let niacinMg: Double?
    let pantothenicAcidMg: Double?
    let vitaminB6Mg: Double?
    let biotinMcg: Double?
    let folateMcg: Double?
    let folicAcidMcg: Double?
    let vitaminB12Mcg: Double?
    let cholineMg: Double?
    let cholesterolMg: Double?

    var displayName: String {
        if let brand, !brand.isEmpty {
            return "\(brand) \(name)"
        }
        return name
    }
}

enum OpenFoodFactsError: LocalizedError {
    case invalidBarcode
    case productNotFound
    case missingNutrition

    var errorDescription: String? {
        switch self {
        case .invalidBarcode:
            return "Enter a valid barcode."
        case .productNotFound:
            return "No Open Food Facts product was found for that barcode."
        case .missingNutrition:
            return "The product exists, but it does not include usable macro data."
        }
    }
}

actor OpenFoodFactsService {
    static let shared = OpenFoodFactsService()

    private let decoder = JSONDecoder()
    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func lookupBarcode(_ barcode: String) async throws -> OpenFoodFactsFood {
        let normalized = barcode.filter(\.isNumber)
        guard !normalized.isEmpty else { throw OpenFoodFactsError.invalidBarcode }

        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(normalized).json")
        components?.queryItems = [
            URLQueryItem(name: "fields", value: requestedFields),
        ]
        guard let url = components?.url else { throw OpenFoodFactsError.invalidBarcode }

        let response: ProductResponse = try await fetch(url)
        guard response.status == 1, let product = response.product else {
            throw OpenFoodFactsError.productNotFound
        }
        guard let food = product.food(barcode: normalized) else {
            throw OpenFoodFactsError.missingNutrition
        }
        return food
    }

    func search(_ query: String) async throws -> [OpenFoodFactsFood] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: normalized),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "20"),
            URLQueryItem(name: "fields", value: requestedFields),
        ]
        guard let url = components?.url else { return [] }

        let response: SearchResponse = try await fetch(url)
        return response.products.compactMap { product in
            product.food(barcode: product.code ?? UUID().uuidString)
        }
    }

    private var requestedFields: String {
        [
            "code",
            "product_name",
            "generic_name",
            "brands",
            "serving_size",
            "serving_quantity",
            "nutriments",
        ].joined(separator: ",")
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Iron/0.1.0 (dev.highimpact.iron)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(T.self, from: data)
    }
}

private struct ProductResponse: Decodable {
    let status: Int
    let product: OpenFoodFactsProduct?
}

private struct SearchResponse: Decodable {
    let products: [OpenFoodFactsProduct]
}

private struct OpenFoodFactsProduct: Decodable {
    let code: String?
    let productName: String?
    let genericName: String?
    let brands: String?
    let servingSize: String?
    let servingQuantity: Double?
    let nutriments: Nutriments?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case genericName = "generic_name"
        case brands
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case nutriments
    }

    func food(barcode: String) -> OpenFoodFactsFood? {
        let name = [productName, genericName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Food"
        guard let nutriments else { return nil }

        let servingFactor = servingQuantity.map { max($0, 0) / 100 }
        guard let calories = nutriments.value(serving: \.energyKcalServing, hundredG: \.energyKcal100g, factor: servingFactor) else {
            return nil
        }

        return OpenFoodFactsFood(
            id: barcode,
            barcode: barcode,
            name: name,
            brand: brands?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines),
            serving: servingSize,
            servingGrams: servingQuantity,
            calories: calories,
            proteinG: nutriments.value(serving: \.proteinServing, hundredG: \.protein100g, factor: servingFactor) ?? 0,
            carbsG: nutriments.value(serving: \.carbsServing, hundredG: \.carbs100g, factor: servingFactor) ?? 0,
            fatG: nutriments.value(serving: \.fatServing, hundredG: \.fat100g, factor: servingFactor) ?? 0,
            fiberG: nutriments.value(serving: \.fiberServing, hundredG: \.fiber100g, factor: servingFactor),
            sugarG: nutriments.value(serving: \.sugarServing, hundredG: \.sugar100g, factor: servingFactor),
            saturatedFatG: nutriments.value(serving: \.saturatedFatServing, hundredG: \.saturatedFat100g, factor: servingFactor),
            monounsaturatedFatG: nutriments.value(serving: \.monoFatServing, hundredG: \.monoFat100g, factor: servingFactor),
            polyunsaturatedFatG: nutriments.value(serving: \.polyFatServing, hundredG: \.polyFat100g, factor: servingFactor),
            transFatG: nutriments.value(serving: \.transFatServing, hundredG: \.transFat100g, factor: servingFactor),
            omega3G: nutriments.value(serving: \.omega3Serving, hundredG: \.omega3100g, factor: servingFactor),
            alaOmega3G: nutriments.value(serving: \.alaServing, hundredG: \.ala100g, factor: servingFactor),
            epaOmega3G: nutriments.value(serving: \.epaServing, hundredG: \.epa100g, factor: servingFactor),
            dpaOmega3G: nutriments.value(serving: \.dpaServing, hundredG: \.dpa100g, factor: servingFactor),
            dhaOmega3G: nutriments.value(serving: \.dhaServing, hundredG: \.dha100g, factor: servingFactor),
            omega6G: nutriments.value(serving: \.omega6Serving, hundredG: \.omega6100g, factor: servingFactor),
            linoleicAcidG: nutriments.value(serving: \.linoleicServing, hundredG: \.linoleic100g, factor: servingFactor),
            arachidonicAcidG: nutriments.value(serving: \.arachidonicServing, hundredG: \.arachidonic100g, factor: servingFactor),
            omega9G: nutriments.value(serving: \.omega9Serving, hundredG: \.omega9100g, factor: servingFactor),
            sodiumMg: nutriments.value(serving: \.sodiumServing, hundredG: \.sodium100g, factor: servingFactor).map { $0 * 1000 },
            potassiumMg: nutriments.value(serving: \.potassiumServing, hundredG: \.potassium100g, factor: servingFactor).map { $0 * 1000 },
            calciumMg: nutriments.value(serving: \.calciumServing, hundredG: \.calcium100g, factor: servingFactor).map { $0 * 1000 },
            ironMg: nutriments.value(serving: \.ironServing, hundredG: \.iron100g, factor: servingFactor).map { $0 * 1000 },
            magnesiumMg: nutriments.value(serving: \.magnesiumServing, hundredG: \.magnesium100g, factor: servingFactor).map { $0 * 1000 },
            phosphorusMg: nutriments.value(serving: \.phosphorusServing, hundredG: \.phosphorus100g, factor: servingFactor).map { $0 * 1000 },
            zincMg: nutriments.value(serving: \.zincServing, hundredG: \.zinc100g, factor: servingFactor).map { $0 * 1000 },
            seleniumMcg: nutriments.value(serving: \.seleniumServing, hundredG: \.selenium100g, factor: servingFactor).map { $0 * 1_000_000 },
            copperMg: nutriments.value(serving: \.copperServing, hundredG: \.copper100g, factor: servingFactor).map { $0 * 1000 },
            manganeseMg: nutriments.value(serving: \.manganeseServing, hundredG: \.manganese100g, factor: servingFactor).map { $0 * 1000 },
            iodineMcg: nutriments.value(serving: \.iodineServing, hundredG: \.iodine100g, factor: servingFactor).map { $0 * 1_000_000 },
            vitaminAMcg: nutriments.value(serving: \.vitaminAServing, hundredG: \.vitaminA100g, factor: servingFactor).map { $0 * 1_000_000 },
            vitaminCMg: nutriments.value(serving: \.vitaminCServing, hundredG: \.vitaminC100g, factor: servingFactor).map { $0 * 1000 },
            vitaminDMcg: nutriments.value(serving: \.vitaminDServing, hundredG: \.vitaminD100g, factor: servingFactor).map { $0 * 1_000_000 },
            vitaminEMg: nutriments.value(serving: \.vitaminEServing, hundredG: \.vitaminE100g, factor: servingFactor).map { $0 * 1000 },
            vitaminKMcg: nutriments.value(serving: \.vitaminKServing, hundredG: \.vitaminK100g, factor: servingFactor).map { $0 * 1_000_000 },
            thiaminMg: nutriments.value(serving: \.thiaminServing, hundredG: \.thiamin100g, factor: servingFactor).map { $0 * 1000 },
            riboflavinMg: nutriments.value(serving: \.riboflavinServing, hundredG: \.riboflavin100g, factor: servingFactor).map { $0 * 1000 },
            niacinMg: nutriments.value(serving: \.niacinServing, hundredG: \.niacin100g, factor: servingFactor).map { $0 * 1000 },
            pantothenicAcidMg: nutriments.value(serving: \.pantothenicServing, hundredG: \.pantothenic100g, factor: servingFactor).map { $0 * 1000 },
            vitaminB6Mg: nutriments.value(serving: \.vitaminB6Serving, hundredG: \.vitaminB6100g, factor: servingFactor).map { $0 * 1000 },
            biotinMcg: nutriments.value(serving: \.biotinServing, hundredG: \.biotin100g, factor: servingFactor).map { $0 * 1_000_000 },
            folateMcg: nutriments.value(serving: \.folateServing, hundredG: \.folate100g, factor: servingFactor).map { $0 * 1_000_000 },
            folicAcidMcg: nutriments.value(serving: \.folicAcidServing, hundredG: \.folicAcid100g, factor: servingFactor).map { $0 * 1_000_000 },
            vitaminB12Mcg: nutriments.value(serving: \.vitaminB12Serving, hundredG: \.vitaminB12100g, factor: servingFactor).map { $0 * 1_000_000 },
            cholineMg: nutriments.value(serving: \.cholineServing, hundredG: \.choline100g, factor: servingFactor).map { $0 * 1000 },
            cholesterolMg: nutriments.value(serving: \.cholesterolServing, hundredG: \.cholesterol100g, factor: servingFactor).map { $0 * 1000 }
        )
    }
}

private struct Nutriments: Decodable {
    let energyKcalServing: Double?
    let energyKcal100g: Double?
    let proteinServing: Double?
    let protein100g: Double?
    let carbsServing: Double?
    let carbs100g: Double?
    let fatServing: Double?
    let fat100g: Double?
    let fiberServing: Double?
    let fiber100g: Double?
    let sugarServing: Double?
    let sugar100g: Double?
    let saturatedFatServing: Double?
    let saturatedFat100g: Double?
    let monoFatServing: Double?
    let monoFat100g: Double?
    let polyFatServing: Double?
    let polyFat100g: Double?
    let transFatServing: Double?
    let transFat100g: Double?
    let omega3Serving: Double?
    let omega3100g: Double?
    let alaServing: Double?
    let ala100g: Double?
    let epaServing: Double?
    let epa100g: Double?
    let dpaServing: Double?
    let dpa100g: Double?
    let dhaServing: Double?
    let dha100g: Double?
    let omega6Serving: Double?
    let omega6100g: Double?
    let linoleicServing: Double?
    let linoleic100g: Double?
    let arachidonicServing: Double?
    let arachidonic100g: Double?
    let omega9Serving: Double?
    let omega9100g: Double?
    let sodiumServing: Double?
    let sodium100g: Double?
    let potassiumServing: Double?
    let potassium100g: Double?
    let calciumServing: Double?
    let calcium100g: Double?
    let ironServing: Double?
    let iron100g: Double?
    let magnesiumServing: Double?
    let magnesium100g: Double?
    let phosphorusServing: Double?
    let phosphorus100g: Double?
    let zincServing: Double?
    let zinc100g: Double?
    let seleniumServing: Double?
    let selenium100g: Double?
    let copperServing: Double?
    let copper100g: Double?
    let manganeseServing: Double?
    let manganese100g: Double?
    let iodineServing: Double?
    let iodine100g: Double?
    let vitaminAServing: Double?
    let vitaminA100g: Double?
    let vitaminCServing: Double?
    let vitaminC100g: Double?
    let vitaminDServing: Double?
    let vitaminD100g: Double?
    let vitaminEServing: Double?
    let vitaminE100g: Double?
    let vitaminKServing: Double?
    let vitaminK100g: Double?
    let thiaminServing: Double?
    let thiamin100g: Double?
    let riboflavinServing: Double?
    let riboflavin100g: Double?
    let niacinServing: Double?
    let niacin100g: Double?
    let pantothenicServing: Double?
    let pantothenic100g: Double?
    let vitaminB6Serving: Double?
    let vitaminB6100g: Double?
    let biotinServing: Double?
    let biotin100g: Double?
    let folateServing: Double?
    let folate100g: Double?
    let folicAcidServing: Double?
    let folicAcid100g: Double?
    let vitaminB12Serving: Double?
    let vitaminB12100g: Double?
    let cholineServing: Double?
    let choline100g: Double?
    let cholesterolServing: Double?
    let cholesterol100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcalServing = "energy-kcal_serving"
        case energyKcal100g = "energy-kcal_100g"
        case proteinServing = "proteins_serving"
        case protein100g = "proteins_100g"
        case carbsServing = "carbohydrates_serving"
        case carbs100g = "carbohydrates_100g"
        case fatServing = "fat_serving"
        case fat100g = "fat_100g"
        case fiberServing = "fiber_serving"
        case fiber100g = "fiber_100g"
        case sugarServing = "sugars_serving"
        case sugar100g = "sugars_100g"
        case saturatedFatServing = "saturated-fat_serving"
        case saturatedFat100g = "saturated-fat_100g"
        case monoFatServing = "monounsaturated-fat_serving"
        case monoFat100g = "monounsaturated-fat_100g"
        case polyFatServing = "polyunsaturated-fat_serving"
        case polyFat100g = "polyunsaturated-fat_100g"
        case transFatServing = "trans-fat_serving"
        case transFat100g = "trans-fat_100g"
        case omega3Serving = "omega-3-fat_serving"
        case omega3100g = "omega-3-fat_100g"
        case alaServing = "alpha-linolenic-acid_serving"
        case ala100g = "alpha-linolenic-acid_100g"
        case epaServing = "eicosapentaenoic-acid_serving"
        case epa100g = "eicosapentaenoic-acid_100g"
        case dpaServing = "docosapentaenoic-acid_serving"
        case dpa100g = "docosapentaenoic-acid_100g"
        case dhaServing = "docosahexaenoic-acid_serving"
        case dha100g = "docosahexaenoic-acid_100g"
        case omega6Serving = "omega-6-fat_serving"
        case omega6100g = "omega-6-fat_100g"
        case linoleicServing = "linoleic-acid_serving"
        case linoleic100g = "linoleic-acid_100g"
        case arachidonicServing = "arachidonic-acid_serving"
        case arachidonic100g = "arachidonic-acid_100g"
        case omega9Serving = "omega-9-fat_serving"
        case omega9100g = "omega-9-fat_100g"
        case sodiumServing = "sodium_serving"
        case sodium100g = "sodium_100g"
        case potassiumServing = "potassium_serving"
        case potassium100g = "potassium_100g"
        case calciumServing = "calcium_serving"
        case calcium100g = "calcium_100g"
        case ironServing = "iron_serving"
        case iron100g = "iron_100g"
        case magnesiumServing = "magnesium_serving"
        case magnesium100g = "magnesium_100g"
        case phosphorusServing = "phosphorus_serving"
        case phosphorus100g = "phosphorus_100g"
        case zincServing = "zinc_serving"
        case zinc100g = "zinc_100g"
        case seleniumServing = "selenium_serving"
        case selenium100g = "selenium_100g"
        case copperServing = "copper_serving"
        case copper100g = "copper_100g"
        case manganeseServing = "manganese_serving"
        case manganese100g = "manganese_100g"
        case iodineServing = "iodine_serving"
        case iodine100g = "iodine_100g"
        case vitaminAServing = "vitamin-a_serving"
        case vitaminA100g = "vitamin-a_100g"
        case vitaminCServing = "vitamin-c_serving"
        case vitaminC100g = "vitamin-c_100g"
        case vitaminDServing = "vitamin-d_serving"
        case vitaminD100g = "vitamin-d_100g"
        case vitaminEServing = "vitamin-e_serving"
        case vitaminE100g = "vitamin-e_100g"
        case vitaminKServing = "vitamin-k_serving"
        case vitaminK100g = "vitamin-k_100g"
        case thiaminServing = "vitamin-b1_serving"
        case thiamin100g = "vitamin-b1_100g"
        case riboflavinServing = "vitamin-b2_serving"
        case riboflavin100g = "vitamin-b2_100g"
        case niacinServing = "vitamin-pp_serving"
        case niacin100g = "vitamin-pp_100g"
        case pantothenicServing = "pantothenic-acid_serving"
        case pantothenic100g = "pantothenic-acid_100g"
        case vitaminB6Serving = "vitamin-b6_serving"
        case vitaminB6100g = "vitamin-b6_100g"
        case biotinServing = "biotin_serving"
        case biotin100g = "biotin_100g"
        case folateServing = "folates_serving"
        case folate100g = "folates_100g"
        case folicAcidServing = "folic-acid_serving"
        case folicAcid100g = "folic-acid_100g"
        case vitaminB12Serving = "vitamin-b12_serving"
        case vitaminB12100g = "vitamin-b12_100g"
        case cholineServing = "choline_serving"
        case choline100g = "choline_100g"
        case cholesterolServing = "cholesterol_serving"
        case cholesterol100g = "cholesterol_100g"
    }

    func value(
        serving: KeyPath<Nutriments, Double?>,
        hundredG: KeyPath<Nutriments, Double?>,
        factor: Double?
    ) -> Double? {
        if let servingValue = self[keyPath: serving] {
            return servingValue
        }
        guard let hundredGValue = self[keyPath: hundredG] else { return nil }
        return factor.map { hundredGValue * $0 } ?? hundredGValue
    }
}
