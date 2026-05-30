import Foundation

enum FitProfileGoal: String, Codable, Sendable {
    case fatLoss
    case maintenance
    case muscleGain
}

struct FitProfileNutritionSuggestion: Codable, Sendable {
    var goal: FitProfileGoal
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
}

struct FitProfileReport: Identifiable, Codable, Sendable {
    static let pasteboardType = "dev.highimpact.iron.fitprofile.report"
    static let mediaPasteboardType = "dev.highimpact.iron.fitprofile.media"
    static let importURL = URL(string: "iron://fitprofile-import")!

    var id: String {
        let timestamp: TimeInterval = measuredAt.map { $0.timeIntervalSince1970 } ?? 0
        return "\(timestamp)-\(weightLb ?? 0)"
    }



    var measuredAt: Date?
    var weightLb: Double?
    var bodyFatPercent: Double?
    var fatFreeMassLb: Double?
    var bmrKcal: Double?
    var normalWeightLb: Double?
    var weightControlLb: Double?
    var fatMassControlLb: Double?
    var sourceText: String

    var suggestedNutrition: FitProfileNutritionSuggestion {
        let goal: FitProfileGoal
        if let fatMassControlLb, fatMassControlLb < 0 {
            goal = .fatLoss
        } else if let weightControlLb, weightControlLb > 0 {
            goal = .muscleGain
        } else {
            goal = .maintenance
        }

        let leanMassLb = fatFreeMassLb ?? weightLb ?? 180
        let proteinG = round(leanMassLb)
        let carbsG: Double = 20

        let baseBMR = bmrKcal ?? 1800
        let targetCalories: Double

        switch goal {
        case .fatLoss:
            targetCalories = max(1500, baseBMR - 500)
        case .maintenance:
            targetCalories = max(1500, baseBMR)
        case .muscleGain:
            targetCalories = max(1500, baseBMR + 250)
        }

        let proteinCalories = proteinG * 4
        let carbCalories = carbsG * 4
        let remainingCalories = max(0, targetCalories - proteinCalories - carbCalories)
        let fatG = round(remainingCalories / 9)

        return FitProfileNutritionSuggestion(
            goal: goal,
            calories: roundToNearest25(targetCalories),
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG
        )
    }


    init(
        measuredAt: Date? = nil,
        weightLb: Double? = nil,
        bodyFatPercent: Double? = nil,
        fatFreeMassLb: Double? = nil,
        bmrKcal: Double? = nil,
        normalWeightLb: Double? = nil,
        weightControlLb: Double? = nil,
        fatMassControlLb: Double? = nil,
        sourceText: String = ""
    ) {
        self.measuredAt = measuredAt
        self.weightLb = weightLb
        self.bodyFatPercent = bodyFatPercent
        self.fatFreeMassLb = fatFreeMassLb
        self.bmrKcal = bmrKcal
        self.normalWeightLb = normalWeightLb
        self.weightControlLb = weightControlLb
        self.fatMassControlLb = fatMassControlLb
        self.sourceText = sourceText
    }


    init?(url: URL) {
        guard url.scheme == "iron", url.host == "fitprofile",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        guard let measuredAt = values["measuredAt"].flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) else {
            return nil
        }
        self.init(
            measuredAt: measuredAt,
            weightLb: values["weightLb"].flatMap(Double.init),
            bodyFatPercent: values["bodyFatPercent"].flatMap(Double.init),
            fatFreeMassLb: values["fatFreeMassLb"].flatMap(Double.init),
            bmrKcal: values["bmrKcal"].flatMap(Double.init),
            normalWeightLb: values["normalWeightLb"].flatMap(Double.init),
            weightControlLb: values["weightControlLb"].flatMap(Double.init),
            fatMassControlLb: values["fatMassControlLb"].flatMap(Double.init),
            sourceText: values["sourceText"] ?? ""
        )
    }

    var deepLinkURL: URL? {
        var components = URLComponents()
        components.scheme = "iron"
        components.host = "fitprofile"

        let timestamp: TimeInterval = measuredAt.map { $0.timeIntervalSince1970 } ?? 0

        components.queryItems = [
            URLQueryItem(name: "measuredAt", value: "\(timestamp)"),
            URLQueryItem(name: "weightLb", value: "\(weightLb ?? 0)"),
            URLQueryItem(name: "bodyFatPercent", value: "\(bodyFatPercent ?? 0)"),
            URLQueryItem(name: "fatFreeMassLb", value: "\(fatFreeMassLb ?? 0)"),
            URLQueryItem(name: "bmrKcal", value: "\(bmrKcal ?? 0)"),
            URLQueryItem(name: "normalWeightLb", value: "\(normalWeightLb ?? 0)"),
            URLQueryItem(name: "weightControlLb", value: "\(weightControlLb ?? 0)"),
            URLQueryItem(name: "fatMassControlLb", value: "\(fatMassControlLb ?? 0)"),
            URLQueryItem(name: "sourceText", value: sourceText),
        ].compactMap { $0 }

        return components.url
    }


    static func parse(text rawText: String, now: Date = Date()) -> FitProfileReport? {
        let text = normalizedOCRText(rawText)
        let weightControlValues = weightControlTableValues(in: text)
        let date = parseDate(from: text) ?? now
        let report = FitProfileReport(
            measuredAt: date,
            weightLb: parsedBodyWeight(in: text),
            bodyFatPercent: parsedBodyFatPercent(in: text),
            fatFreeMassLb: lineValue(after: #"Fat[- ]?free Body Weight|Fat Free Mass|LBM"#, in: text),
            bmrKcal: lineValue(after: #"BMR"#, in: text),
            normalWeightLb: lineValue(after: #"Normal weight"#, in: text) ?? weightControlValues[safe: 0],
            weightControlLb: lineValue(after: #"Weight Control"#, in: text, excludingLinePrefix: "Normal") ?? weightControlValues[safe: 1],
            fatMassControlLb: lineValue(after: #"Fat mass control"#, in: text) ?? weightControlValues[safe: 2],
            sourceText: rawText
        )
        guard report.weightLb != nil || report.bmrKcal != nil || report.weightControlLb != nil else {
            return nil
        }
        return report
    }
}

struct FitProfileImportMedia: Codable, Sendable {
    var mimeType: String
    var data: Data

    init(mimeType: String, data: Data) {
        self.mimeType = mimeType
        self.data = data
    }
}

private func queryItem(_ name: String, _ value: Double?) -> URLQueryItem? {
    value.map { URLQueryItem(name: name, value: String(format: "%.4f", $0)) }
}

private func roundToNearest25(_ value: Double) -> Double {
    (value / 25).rounded() * 25
}

private func normalizedOCRText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .replacingOccurrences(of: "−", with: "-")
}

private func parsedBodyWeight(in text: String) -> Double? {
    lineValue(after: #"Weight"#, in: text, excludingLinePrefix: "Normal")
        ?? value(matching: #"(?i)\bWeight\s+\#(numberPattern)\s*(?:lb|[iI1]b)?\b"#, in: text)
}

private func parsedBodyFatPercent(in text: String) -> Double? {
    value(matching: #"(?im)^\s*(?:PBF|Body Fat|Fat Mass)\s+\#(numberPattern)\s*%"#, in: text)
        ?? value(matching: #"(?i)\b(?:PBF|Body Fat Percentage)\b[^\d+\-Oo]{0,40}\#(numberPattern)\s*%?"#, in: text)
}

private let numberPattern = #"([+\-]?[0-9]+(?:\.[0-9]+)?)"#

private func lineValue(after labelPattern: String, in text: String, excludingLinePrefix: String? = nil) -> Double? {
    let lines = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)

    guard let labelRegex = try? NSRegularExpression(pattern: #"^\s*(\#(labelPattern))\b"#, options: [.caseInsensitive]) else {
        return nil
    }

    for index in lines.indices {
        let line = lines[index]
        if let excludingLinePrefix,
           line.range(of: #"^\s*\#(NSRegularExpression.escapedPattern(for: excludingLinePrefix))\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            continue
        }

        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        guard labelRegex.firstMatch(in: line, range: range) != nil else { continue }

        let inlineText = String(line.dropFirstLabelMatch(labelRegex))
        if let value = firstNumber(in: inlineText) {
            return value
        }

        if lines.indices.contains(index + 1),
           let value = firstNumber(in: lines[index + 1]) {
            return value
        }
    }

    return value(matching: #"(?i)\b(?:\#(labelPattern))\b[^\d+\-Oo]{0,60}\#(numberPattern)"#, in: text)
}

private func weightControlTableValues(in text: String) -> [Double] {
    guard let start = text.range(of: "Weight Control", options: [.caseInsensitive]) else {
        return []
    }
    let tail = text[start.lowerBound...]
    let end = tail.range(of: "Muscle balance", options: [.caseInsensitive])?.lowerBound
        ?? tail.range(of: "Other Measurements", options: [.caseInsensitive])?.lowerBound
        ?? tail.endIndex
    let block = String(tail[..<end])
    return values(matching: #"\#(numberPattern)\s*(?:lb|[iI1]b)"#, in: block)
}

private func firstNumber(in text: String) -> Double? {
    value(matching: numberPattern, in: text)
}

private func value(matching pattern: String, in text: String) -> Double? {
    values(matching: pattern, in: text).first
}

private func values(matching pattern: String, in text: String) -> [Double] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return []
    }
    let range = NSRange(text.startIndex ..< text.endIndex, in: text)
    return regex.matches(in: text, range: range).compactMap { match in
        guard let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return parseOCRNumber(String(text[valueRange]))
    }
}

private func parseOCRNumber(_ value: String) -> Double? {
    let normalized = value
        .replacingOccurrences(of: "O", with: "0")
        .replacingOccurrences(of: "o", with: "0")
        .replacingOccurrences(of: ",", with: "")
    return Double(normalized)
}

private extension String {
    func dropFirstLabelMatch(_ regex: NSRegularExpression) -> Substring {
        let range = NSRange(startIndex ..< endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              let labelRange = Range(match.range(at: 1), in: self) else {
            return self[...]
        }
        return self[labelRange.upperBound...]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func parseDate(from text: String) -> Date? {
    if let date = parseDate(from: text, pattern: #"(\d{1,2}/\d{1,2}/\d{4})\s+(\d{1,2}:\d{2})"#, format: "MM/dd/yyyy HH:mm") {
        return date
    }
    return parseDate(from: text, pattern: #"(\d{1,2}/\d{1,2}/\d{4})"#, format: "MM/dd/yyyy")
}

private func parseDate(from text: String, pattern: String, format: String) -> Date? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return nil
    }
    let range = NSRange(text.startIndex ..< text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range) else {
        return nil
    }
    let parts = (1 ..< match.numberOfRanges).compactMap { index -> String? in
        guard let partRange = Range(match.range(at: index), in: text) else { return nil }
        return String(text[partRange])
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = format
    return formatter.date(from: parts.joined(separator: " "))
}
