import Foundation

struct VoiceMealSessionConfiguration {
    var model = "gemini-3.1-flash-live-preview"
    var responseModalities = ["AUDIO"]
}

@MainActor
final class VoiceMealSessionService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func makeWebSocketTask(
        apiKey: String,
        configuration: VoiceMealSessionConfiguration = VoiceMealSessionConfiguration()
    ) throws -> URLSessionWebSocketTask {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent"
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let task = session.webSocketTask(with: request)
        task.resume()
        let setup = LiveSetupMessage(
            setup: LiveSetup(
                model: configuration.model,
                generationConfig: LiveGenerationConfig(responseModalities: configuration.responseModalities),
                tools: [
                    LiveTool(
                        functionDeclarations: [
                            LiveFunctionDeclaration.mealDraftLogger,
                        ]
                    ),
                ]
            )
        )
        if let payload = try? JSONEncoder().encode(setup),
           let text = String(data: payload, encoding: .utf8) {
            task.send(.string(text)) { _ in }
        }
        return task
    }
}

private struct LiveSetupMessage: Encodable {
    let setup: LiveSetup
}

private struct LiveSetup: Encodable {
    let model: String
    let generationConfig: LiveGenerationConfig
    let tools: [LiveTool]
}

private struct LiveGenerationConfig: Encodable {
    let responseModalities: [String]
}

private struct LiveTool: Encodable {
    let functionDeclarations: [LiveFunctionDeclaration]
}

private struct LiveFunctionDeclaration: Encodable {
    let name: String
    let description: String
    let parameters: LiveFunctionParameters

    static var mealDraftLogger: LiveFunctionDeclaration {
        LiveFunctionDeclaration(
            name: "emit_meal_draft",
            description: "Emit the reviewed meal draft contract for Iron nutrition logging.",
            parameters: LiveFunctionParameters.mealDraft
        )
    }
}

private final class LiveFunctionParameters: Encodable {
    let type: String
    let properties: [String: LiveFunctionParameters]?
    let items: LiveFunctionParameters?
    let required: [String]?

    init(
        type: String,
        properties: [String: LiveFunctionParameters]? = nil,
        items: LiveFunctionParameters? = nil,
        required: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.items = items
        self.required = required
    }

    static var mealDraft: LiveFunctionParameters {
        LiveFunctionParameters(
            type: "object",
            properties: [
                "transcript": LiveFunctionParameters(type: "string"),
                "mealName": LiveFunctionParameters(type: "string"),
                "items": LiveFunctionParameters(
                    type: "array",
                    items: LiveFunctionParameters(
                        type: "object",
                        properties: [
                            "foodName": LiveFunctionParameters(type: "string"),
                            "quantity": LiveFunctionParameters(type: "number"),
                            "unit": LiveFunctionParameters(type: "string"),
                            "servingDescription": LiveFunctionParameters(type: "string"),
                            "calories": LiveFunctionParameters(type: "number"),
                            "proteinG": LiveFunctionParameters(type: "number"),
                            "carbsG": LiveFunctionParameters(type: "number"),
                            "fatG": LiveFunctionParameters(type: "number"),
                            "confidence": LiveFunctionParameters(type: "number"),
                            "notes": LiveFunctionParameters(type: "string"),
                        ],
                        required: ["foodName", "quantity", "unit", "calories", "proteinG", "carbsG", "fatG"]
                    )
                ),
            ],
            required: ["transcript", "mealName", "items"]
        )
    }
}
