import Foundation

struct GeminiNutritionPreferenceKeys {
    static let apiKey = "geminiNutrition.apiKey"
}

enum GeminiNutritionError: LocalizedError {
    case missingAPIKey
    case emptyAudio
    case invalidResponse(String)
    case emptyDraft
    case requestTimedOut
    case networkUnavailable(String)
    case modelBlocked(String)
    case serverStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Gemini API key in Settings."
        case .emptyAudio:
            return "No meal audio was recorded."
        case .invalidResponse(let reason):
            return "Gemini returned an unreadable meal draft. \(reason)"
        case .emptyDraft:
            return "Gemini did not find any foods to log."
        case .requestTimedOut:
            return "Gemini timed out. Try a shorter recording or check your connection."
        case .networkUnavailable(let message):
            return "Gemini request failed: \(message)"
        case .modelBlocked(let reason):
            return "Gemini blocked the meal draft. \(reason)"
        case .serverStatus(let status, let body):
            return "Gemini returned status \(status): \(body)"
        }
    }
}

actor GeminiNutritionService {
    static let shared = GeminiNutritionService()

    private let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent")!
    private let requestTimeout: TimeInterval = 180
    private let decoder = JSONDecoder()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func draftMeal(from audioURL: URL, selectedDate: Date, apiKey: String? = nil) async throws -> MealDraft {
        let resolvedKey = try resolvedAPIKey(apiKey)
        let audio = try Data(contentsOf: audioURL)
        guard !audio.isEmpty else { throw GeminiNutritionError.emptyAudio }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue(resolvedKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GenerateContentRequest(
                contents: [
                    Content(
                        parts: [
                            Part(text: prompt(for: selectedDate)),
                            Part(inlineData: InlineData(mimeType: "audio/wav", data: audio.base64EncodedString())),
                        ]
                    ),
                ],
                generationConfig: GenerationConfig.mealDraft
            )
        )

        let (data, response) = try await data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GeminiNutritionError.serverStatus(http.statusCode, body)
        }

        let responseBody: GenerateContentResponse
        do {
            responseBody = try decoder.decode(GenerateContentResponse.self, from: data)
        } catch {
            let preview = Self.preview(data)
            throw GeminiNutritionError.invalidResponse("Unexpected API response: \(preview)")
        }

        if let apiMessage = responseBody.error?.message?.nilIfBlank {
            throw GeminiNutritionError.invalidResponse(apiMessage)
        }

        if let promptFeedback = responseBody.promptFeedback,
           let blockReason = promptFeedback.blockReason?.nilIfBlank {
            let message = promptFeedback.blockReasonMessage?.nilIfBlank ?? blockReason
            throw GeminiNutritionError.modelBlocked(message)
        }

        let text = (responseBody.candidates ?? [])
            .flatMap { $0.content?.parts ?? [] }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = Self.jsonData(from: text) else {
            let finishReason = responseBody.candidates?
                .compactMap(\.finishReason)
                .first?
                .nilIfBlank
            let reason = finishReason.map { "Finish reason: \($0)." } ?? "No JSON text was returned."
            throw GeminiNutritionError.invalidResponse(reason)
        }

        let draft: MealDraft
        do {
            draft = try Self.decodeDraft(from: jsonData, decoder: decoder)
        } catch {
            throw GeminiNutritionError.invalidResponse("Draft JSON did not match the meal format.")
        }
        guard !draft.nutritionEntries(loggedAt: selectedDate).isEmpty else {
            throw GeminiNutritionError.emptyDraft
        }
        return draft
    }

    static func decodeDraft(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> MealDraft {
        if let draft = try? decoder.decode(MealDraft.self, from: data),
           !draft.items.isEmpty {
            return draft
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let draft = draft(fromJSONObject: object) else {
            throw GeminiNutritionError.invalidResponse("Draft JSON did not include food items.")
        }
        return draft
    }

    private static func draft(fromJSONObject object: Any) -> MealDraft? {
        if let items = object as? [[String: Any]] {
            return MealDraft(items: items.compactMap(item(fromJSONObject:)))
        }

        guard let dictionary = object as? [String: Any] else { return nil }
        if let nested = dictionary["draft"] ?? dictionary["mealDraft"],
           let draft = draft(fromJSONObject: nested) {
            return draft
        }

        let itemObject = dictionary["items"]
            ?? dictionary["foods"]
            ?? dictionary["foodItems"]
            ?? dictionary["entries"]
        let items = (itemObject as? [[String: Any]])?.compactMap(item(fromJSONObject:)) ?? []
        return MealDraft(
            transcript: stringValue(dictionary["transcript"]) ?? stringValue(dictionary["text"]) ?? "",
            mealName: stringValue(dictionary["mealName"]) ?? stringValue(dictionary["meal_name"]),
            items: items
        )
    }

    private static func item(fromJSONObject dictionary: [String: Any]) -> MealDraftItem? {
        MealDraftItem(
            foodName: stringValue(dictionary["foodName"]) ?? stringValue(dictionary["name"]),
            quantity: doubleValue(dictionary["quantity"]),
            unit: stringValue(dictionary["unit"]) ?? stringValue(dictionary["quantityUnit"]),
            servingDescription: stringValue(dictionary["servingDescription"]) ?? stringValue(dictionary["serving"]),
            calories: doubleValue(dictionary["calories"]),
            proteinG: doubleValue(dictionary["proteinG"]) ?? doubleValue(dictionary["protein_g"]),
            carbsG: doubleValue(dictionary["carbsG"]) ?? doubleValue(dictionary["carbs_g"]),
            fatG: doubleValue(dictionary["fatG"]) ?? doubleValue(dictionary["fat_g"]),
            fiberG: doubleValue(dictionary["fiberG"]) ?? doubleValue(dictionary["fiber_g"]),
            sugarG: doubleValue(dictionary["sugarG"]) ?? doubleValue(dictionary["sugar_g"]),
            sodiumMg: doubleValue(dictionary["sodiumMg"]) ?? doubleValue(dictionary["sodium_mg"]),
            potassiumMg: doubleValue(dictionary["potassiumMg"]) ?? doubleValue(dictionary["potassium_mg"]),
            calciumMg: doubleValue(dictionary["calciumMg"]) ?? doubleValue(dictionary["calcium_mg"]),
            ironMg: doubleValue(dictionary["ironMg"]) ?? doubleValue(dictionary["iron_mg"]),
            vitaminDMcg: doubleValue(dictionary["vitaminDMcg"]) ?? doubleValue(dictionary["vitamin_d_mcg"]),
            cholesterolMg: doubleValue(dictionary["cholesterolMg"]) ?? doubleValue(dictionary["cholesterol_mg"]),
            confidence: clampedConfidence(dictionary["confidence"]),
            notes: stringValue(dictionary["notes"])
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value.nilIfBlank
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double where value.isFinite:
            return max(0, value)
        case let value as Int:
            return Double(max(0, value))
        case let value as NSNumber:
            return max(0, value.doubleValue)
        case let value as String:
            guard let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  parsed.isFinite else {
                return nil
            }
            return max(0, parsed)
        default:
            return nil
        }
    }

    private static func clampedConfidence(_ value: Any?) -> Double? {
        guard let value = doubleValue(value) else { return nil }
        return min(max(value, 0), 1)
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                return try await session.data(for: request)
            } catch let retryError as URLError where retryError.code == .timedOut {
                throw GeminiNutritionError.requestTimedOut
            } catch let retryError as URLError {
                throw GeminiNutritionError.networkUnavailable(retryError.localizedDescription)
            }
        } catch let error as URLError {
            throw GeminiNutritionError.networkUnavailable(error.localizedDescription)
        }
    }

    private func resolvedAPIKey(_ apiKey: String?) throws -> String {
        let explicit = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit, !explicit.isEmpty { return explicit }

        let stored = UserDefaults.standard
            .string(forKey: GeminiNutritionPreferenceKeys.apiKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }

        throw GeminiNutritionError.missingAPIKey
    }

    private func prompt(for selectedDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        let mealName = MealDraft.defaultMealName(for: selectedDate)
        return """
        Parse the spoken meal into a nutrition log draft for Iron.
        Selected log date: \(formatter.string(from: selectedDate)).
        If the speaker does not name a meal, use "\(mealName)".
        Estimate final practical nutrition values directly from the description; do not leave fields blank for database lookup.
        Return only JSON matching this shape:
        {
          "transcript": "full transcript",
          "mealName": "Breakfast|Lunch|Dinner|Snack",
          "items": [
            {
              "foodName": "food name",
              "quantity": 1,
              "unit": "serving",
              "servingDescription": "plain serving text",
              "calories": 0,
              "proteinG": 0,
              "carbsG": 0,
              "fatG": 0,
              "fiberG": 0,
              "sugarG": 0,
              "sodiumMg": 0,
              "potassiumMg": 0,
              "calciumMg": 0,
              "ironMg": 0,
              "vitaminDMcg": 0,
              "cholesterolMg": 0,
              "confidence": 0.8,
              "notes": "brief uncertainty or source note"
            }
          ]
        }
        Use numbers only for nutrient fields. Split distinct foods into separate items.
        """
    }

    private static func jsonData(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) {
            return data
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return nil
        }
        let json = String(trimmed[start ... end])
        return json.data(using: .utf8)
    }

    private static func preview(_ data: Data, limit: Int = 300) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "..."
    }
}

private struct GenerateContentRequest: Encodable {
    let contents: [Content]
    let generationConfig: GenerationConfig
}

private struct Content: Encodable {
    let parts: [Part]
}

private struct Part: Encodable {
    var text: String?
    var inlineData: InlineData?
}

private struct InlineData: Encodable {
    let mimeType: String
    let data: String
}

private struct GenerationConfig: Encodable {
    let responseMimeType: String
    let responseSchema: GeminiJSONSchema
    let thinkingConfig: ThinkingConfig
    let maxOutputTokens: Int

    static var mealDraft: GenerationConfig {
        GenerationConfig(
            responseMimeType: "application/json",
            responseSchema: .mealDraft,
            thinkingConfig: ThinkingConfig(thinkingLevel: "low"),
            maxOutputTokens: 2048
        )
    }
}

private struct ThinkingConfig: Encodable {
    let thinkingLevel: String
}

private final class GeminiJSONSchema: Encodable {
    let type: String
    let description: String?
    let properties: [String: GeminiJSONSchema]?
    let items: GeminiJSONSchema?
    let required: [String]?

    init(
        type: String,
        description: String? = nil,
        properties: [String: GeminiJSONSchema]? = nil,
        items: GeminiJSONSchema? = nil,
        required: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.items = items
        self.required = required
    }

    static var mealDraft: GeminiJSONSchema {
        GeminiJSONSchema(
            type: "object",
            properties: [
                "transcript": GeminiJSONSchema(type: "string"),
                "mealName": GeminiJSONSchema(type: "string"),
                "items": GeminiJSONSchema(
                    type: "array",
                    items: GeminiJSONSchema(
                        type: "object",
                        properties: [
                            "foodName": GeminiJSONSchema(type: "string"),
                            "quantity": GeminiJSONSchema(type: "number"),
                            "unit": GeminiJSONSchema(type: "string"),
                            "servingDescription": GeminiJSONSchema(type: "string"),
                            "calories": GeminiJSONSchema(type: "number"),
                            "proteinG": GeminiJSONSchema(type: "number"),
                            "carbsG": GeminiJSONSchema(type: "number"),
                            "fatG": GeminiJSONSchema(type: "number"),
                            "fiberG": GeminiJSONSchema(type: "number"),
                            "sugarG": GeminiJSONSchema(type: "number"),
                            "sodiumMg": GeminiJSONSchema(type: "number"),
                            "potassiumMg": GeminiJSONSchema(type: "number"),
                            "calciumMg": GeminiJSONSchema(type: "number"),
                            "ironMg": GeminiJSONSchema(type: "number"),
                            "vitaminDMcg": GeminiJSONSchema(type: "number"),
                            "cholesterolMg": GeminiJSONSchema(type: "number"),
                            "confidence": GeminiJSONSchema(type: "number"),
                            "notes": GeminiJSONSchema(type: "string"),
                        ],
                        required: ["foodName", "quantity", "unit", "calories", "proteinG", "carbsG", "fatG"]
                    )
                ),
            ],
            required: ["transcript", "mealName", "items"]
        )
    }
}

private struct GenerateContentResponse: Decodable {
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
    let error: GeminiAPIError?
}

private struct Candidate: Decodable {
    let content: ModelContent?
    let finishReason: String?
}

private struct ModelContent: Decodable {
    let parts: [ModelPart]
}

private struct ModelPart: Decodable {
    let text: String?
}

private struct PromptFeedback: Decodable {
    let blockReason: String?
    let blockReasonMessage: String?
}

private struct GeminiAPIError: Decodable {
    let message: String?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
