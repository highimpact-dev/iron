import XCTest
@testable import Iron

final class FitProfileImportTests: XCTestCase {
    func testParsesFitProfileReportTextAndSuggestsFatLossTarget() throws {
        let text = """
        Body Composition Analysis ID:DougMarzean Height:5'9'' Age:54 Gender:Male 05/20/2026 11:54
        Weight 176
        PBF 18.5
        BMR Basal Metabolic Rate 1776kcal
        LBM Fat-free Body Weight 143.8lb
        Normal weight 168.8lb
        Weight Control -7.2lb
        Fat mass control -7.2lb
        """

        let report = try XCTUnwrap(FitProfileReport.parse(text: text))
        XCTAssertEqual(report.weightLb, 176)
        XCTAssertEqual(report.bodyFatPercent, 18.5)
        XCTAssertEqual(report.bmrKcal, 1776)
        XCTAssertEqual(report.weightControlLb, -7.2)
        XCTAssertEqual(report.suggestedNutrition.goal, .fatLoss)
        XCTAssertEqual(report.suggestedNutrition.calories, 2075)
    }

    func testRoundTripsDeepLinkPayload() throws {
        let report = FitProfileReport(
            measuredAt: Date(timeIntervalSince1970: 1_780_000_000),
            weightLb: 176,
            bodyFatPercent: 18.5,
            fatFreeMassLb: 143.8,
            bmrKcal: 1776,
            normalWeightLb: 168.8,
            weightControlLb: -7.2,
            fatMassControlLb: -7.2,
            sourceText: "FitProfile"
        )

        let url = try XCTUnwrap(report.deepLinkURL)
        let decoded = try XCTUnwrap(FitProfileReport(url: url))

        XCTAssertEqual(decoded.weightLb, 176)
        XCTAssertEqual(decoded.bodyFatPercent, 18.5)
        XCTAssertEqual(decoded.fatMassControlLb, -7.2)
    }

    func testRoundTripsPasteboardPayload() throws {
        let report = FitProfileReport(
            measuredAt: Date(timeIntervalSince1970: 1_780_000_000),
            weightLb: 176,
            bodyFatPercent: 18.5,
            fatFreeMassLb: 143.8,
            bmrKcal: 1776,
            normalWeightLb: 168.8,
            weightControlLb: -7.2,
            fatMassControlLb: -7.2,
            sourceText: "FitProfile"
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(FitProfileReport.self, from: data)

        XCTAssertEqual(FitProfileReport.importURL.absoluteString, "iron://fitprofile-import")
        XCTAssertEqual(FitProfileReport.pasteboardType, "dev.highimpact.iron.fitprofile.report")
        XCTAssertEqual(decoded.weightLb, 176)
        XCTAssertEqual(decoded.bodyFatPercent, 18.5)
        XCTAssertEqual(decoded.fatMassControlLb, -7.2)
    }
}
