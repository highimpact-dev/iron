import Foundation

enum GeminiFitProfileError: LocalizedError {
    case missingAPIKey
    case invalidResponse(String)
    case requestFailed(String)
    case serverStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Gemini API key in Settings before importing FitProfile reports."
        case .invalidResponse(let reason):
            return "Gemini returned unreadable FitProfile data. \(reason)"
        case .requestFailed(let message):
            return "Gemini FitProfile import failed: \(message)"
        case .serverStatus(let status, let body):
            return "Gemini returned status \(status): \(body)"
        }
    }
}

actor GeminiFitProfileService {
    static let shared = GeminiFitProfileService()

    private let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent")!
    private let requestTimeout: TimeInterval = 90
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func parse(media: FitProfileImportMedia, apiKey: String? = nil, now: Date = Date()) async throws -> FitProfileReport {
        let resolvedKey = try resolvedAPIKey(apiKey)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue(resolvedKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            FitProfileGenerateContentRequest(
                contents: [
                    FitProfileContent(
                        parts: [
                            FitProfilePart(text: Self.prompt),
                            FitProfilePart(inlineData: FitProfileInlineData(
                                mimeType: media.mimeType,
                                data: media.data.base64EncodedString()
                            )),
                        ]
                    ),
                ],
                generationConfig: .fitProfile
            )
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw GeminiFitProfileError.requestFailed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GeminiFitProfileError.serverStatus(http.statusCode, body)
        }

        let responseBody: FitProfileGenerateContentResponse
        do {
            responseBody = try JSONDecoder().decode(FitProfileGenerateContentResponse.self, from: data)
        } catch {
            throw GeminiFitProfileError.invalidResponse("Unexpected API response.")
        }

        if let apiMessage = responseBody.error?.message?.nilIfBlank {
            throw GeminiFitProfileError.invalidResponse(apiMessage)
        }

        let text = (responseBody.candidates ?? [])
            .flatMap { $0.content?.parts ?? [] }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = Self.jsonData(from: text),
              let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw GeminiFitProfileError.invalidResponse("No JSON object was returned.")
        }
        
        // Ensure Gemini returned all expected keys, even if some values are null.
        let expectedKeys = [
            "measuredAt",
            "weightLb",
            "bodyFatPercent",
            "fatFreeMassLb",
            "bmrKcal",
            "normalWeightLb",
            "weightControlLb",
            "fatMassControlLb"
        ]

        for key in expectedKeys where !object.keys.contains(key) {
            throw GeminiFitProfileError.invalidResponse("Missing key: \(key)")
        }


        let report = FitProfileReport(
            measuredAt: Self.dateValue(object["measuredAt"]) ?? Self.dateValue(object["date"]),
            weightLb: Self.doubleValue(object["weightLb"]),
            bodyFatPercent: Self.doubleValue(object["bodyFatPercent"]),
            fatFreeMassLb: Self.doubleValue(object["fatFreeMassLb"]),
            bmrKcal: Self.doubleValue(object["bmrKcal"]),
            normalWeightLb: Self.doubleValue(object["normalWeightLb"]),
            weightControlLb: Self.doubleValue(object["weightControlLb"]),
            fatMassControlLb: Self.doubleValue(object["fatMassControlLb"]),
            sourceText: text
        )

        
        return report
    }

    private func resolvedAPIKey(_ apiKey: String?) throws -> String {
        let explicit = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit, !explicit.isEmpty { return explicit }

        let stored = UserDefaults.standard
            .string(forKey: GeminiNutritionPreferenceKeys.apiKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }

        throw GeminiFitProfileError.missingAPIKey
    }

    private static let prompt = """
    Extract values from this FitProfile or InBody-style body composition report image.

    Return exactly one JSON object that matches the provided response schema.

    Rules:
    - Read values only from the report image. If another screenshot is present, use it only for the date if the report date is missing.
    - Never guess or infer missing values.
    - If a value is unreadable or absent, return null for that field.
    - Preserve negative signs and decimals.
    - weightLb is total body weight, not body water, protein, bone mass, or normal weight.
    - bodyFatPercent is the body fat percentage, not body fat mass in pounds.
    - fatFreeMassLb may appear as Fat-free Body Weight, Fat Free Mass, or LBM.
    - normalWeightLb, weightControlLb, and fatMassControlLb must come from the Weight Control table.
    - measuredAt must be ISO 8601 format: YYYY-MM-DDTHH:mm:ss.
    - If only a date is visible, use 00:00:00 for the time.
    - Return raw JSON only.
    """


    private static func jsonData(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), trimmed.hasPrefix("{") {
            return data
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return nil
        }
        return String(trimmed[start ... end]).data(using: .utf8)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double where value.isFinite:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue.isFinite ? value.doubleValue : nil
        case let value as String:
            let cleaned = value
                .replacingOccurrences(of: "lb", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "kcal", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(cleaned)
        default:
            return nil
        }
    }

    private static func dateValue(_ value: Any?) -> Date? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: text) {
            return date
        }

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "MM/dd/yyyy HH:mm", "MM/dd/yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }
}

private struct FitProfileGenerateContentRequest: Encodable {
    let contents: [FitProfileContent]
    let generationConfig: FitProfileGenerationConfig
}

private struct FitProfileContent: Encodable {
    let parts: [FitProfilePart]
}

private struct FitProfilePart: Encodable {
    var text: String?
    var inlineData: FitProfileInlineData?
}

private struct FitProfileInlineData: Encodable {
    let mimeType: String
    let data: String
}

private struct FitProfileGenerationConfig: Encodable {
    let responseMimeType: String
    let responseSchema: FitProfileJSONSchema
    let thinkingConfig: FitProfileThinkingConfig
    let maxOutputTokens: Int

    static var fitProfile: FitProfileGenerationConfig {
        FitProfileGenerationConfig(
            responseMimeType: "application/json",
            responseSchema: .fitProfile,
            thinkingConfig: FitProfileThinkingConfig(thinkingLevel: "low"),
            maxOutputTokens: 1024
        )
    }
}


private struct FitProfileThinkingConfig: Encodable {
    let thinkingLevel: String
}

private final class FitProfileJSONSchema: Encodable {
    let type: String
    let properties: [String: FitProfileJSONSchema]?
    let required: [String]?
    let nullable: Bool?

    init(
        type: String,
        properties: [String: FitProfileJSONSchema]? = nil,
        required: [String]? = nil,
        nullable: Bool? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.nullable = nullable
    }

    static var fitProfile: FitProfileJSONSchema {
        let keys = [
            "measuredAt",
            "weightLb",
            "bodyFatPercent",
            "fatFreeMassLb",
            "bmrKcal",
            "normalWeightLb",
            "weightControlLb",
            "fatMassControlLb"
        ]

        return FitProfileJSONSchema(
            type: "object",
            properties: [
                "measuredAt": FitProfileJSONSchema(type: "string", nullable: true),
                "weightLb": FitProfileJSONSchema(type: "number", nullable: true),
                "bodyFatPercent": FitProfileJSONSchema(type: "number", nullable: true),
                "fatFreeMassLb": FitProfileJSONSchema(type: "number", nullable: true),
                "bmrKcal": FitProfileJSONSchema(type: "number", nullable: true),
                "normalWeightLb": FitProfileJSONSchema(type: "number", nullable: true),
                "weightControlLb": FitProfileJSONSchema(type: "number", nullable: true),
                "fatMassControlLb": FitProfileJSONSchema(type: "number", nullable: true),
            ],
            required: keys
        )
    }
}



private struct FitProfileGenerateContentResponse: Decodable {
    let candidates: [FitProfileCandidate]?
    let error: FitProfileAPIError?
}

private struct FitProfileCandidate: Decodable {
    let content: FitProfileModelContent?
}

private struct FitProfileModelContent: Decodable {
    let parts: [FitProfileModelPart]
}

private struct FitProfileModelPart: Decodable {
    let text: String?
}

private struct FitProfileAPIError: Decodable {
    let message: String?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
