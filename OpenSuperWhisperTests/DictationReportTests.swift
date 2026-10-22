import XCTest

@testable import OpenSuperWhisper

final class DictationReportTests: XCTestCase {

    private func draft(output: String = "Hello there.",
                       raw: String? = nil,
                       note: String = "",
                       language: String? = "fr",
                       translate: Bool = false) -> DictationReportDraft {
        DictationReportDraft(note: note, modelUsed: "Parakeet Ultra", languageSetting: language,
                             translateToEnglish: translate, durationSeconds: 4, output: output,
                             rawOutput: raw, appVersion: "0.14.0 (63)", osVersion: "26.2")
    }

    // MARK: - Message

    func testTheMessageCarriesTheSettingsAndTheOutput() {
        let message = DictationReport.message(for: draft(note: "spoke French, got English"),
                                              outputLimit: 2000, includeRaw: true)

        XCTAssertTrue(message.hasPrefix("Dictation reported as wrong.\nspoke French, got English\n"))
        XCTAssertTrue(message.contains("model: Parakeet Ultra"))
        XCTAssertTrue(message.contains("language: fr"))
        XCTAssertTrue(message.contains("duration: 4s"))
        XCTAssertTrue(message.contains("output: Hello there."))
    }

    func testAnEmptyNoteLeavesNoNoteLine() {
        let message = DictationReport.message(for: draft(note: "   "), outputLimit: 2000, includeRaw: true)

        XCTAssertEqual(message.split(separator: "\n").first, "Dictation reported as wrong.")
        XCTAssertTrue(message.contains("model:"))
    }

    func testTranslateToEnglishIsNamedOnlyWhenOn() {
        let on = DictationReport.message(for: draft(translate: true), outputLimit: 2000, includeRaw: true)
        let off = DictationReport.message(for: draft(translate: false), outputLimit: 2000, includeRaw: true)

        XCTAssertTrue(on.contains("translate to English: on"))
        XCTAssertFalse(off.contains("translate to English"))
    }

    func testTheRawTextIsSentOnlyWhenItDiffers() {
        let differs = DictationReport.message(for: draft(output: "cleaned", raw: "raw text"),
                                              outputLimit: 2000, includeRaw: true)
        let same = DictationReport.message(for: draft(output: "same", raw: "same"),
                                           outputLimit: 2000, includeRaw: true)

        XCTAssertTrue(differs.contains("raw: raw text"))
        XCTAssertFalse(same.contains("raw:"))
    }

    // MARK: - Submission

    func testAnOrdinaryReportSendsAsABugWithNoEmail() {
        let submission = DictationReport.submission(for: draft(output: "bonjour", raw: "Bonjour."))

        XCTAssertEqual(submission.kind, .bug)
        XCTAssertEqual(submission.email, "")
        XCTAssertEqual(submission.details, "OpenSuperWhisper 0.14.0 (63) · macOS 26.2")
        XCTAssertTrue(submission.message.contains("output: bonjour"))
        XCTAssertTrue(submission.message.contains("raw: Bonjour."))
        XCTAssertTrue(FeedbackSender.fitsLimits(submission))
    }

    /// Output and raw text that together pass the byte limit drop the raw text first, so the
    /// output, the part the person is reporting, always sends.
    func testOversizedTextDropsTheRawFirstAndStillFits() {
        let submission = DictationReport.submission(for: draft(output: String(repeating: "あ", count: 2000),
                                                               raw: String(repeating: "い", count: 2000)))

        XCTAssertTrue(FeedbackSender.fitsLimits(submission))
        XCTAssertTrue(submission.message.contains("output: ああ"))
        XCTAssertFalse(submission.message.contains("raw:"))
    }

    /// Even an output that alone would pass the limit (emoji count double toward it) sends rather
    /// than nothing, shortened until it fits.
    func testAnEnormousOutputIsShortenedToFit() {
        let submission = DictationReport.submission(for: draft(output: String(repeating: "😀", count: 5000)))

        XCTAssertTrue(FeedbackSender.fitsLimits(submission))
        XCTAssertTrue(submission.message.contains("output: 😀"))
    }
}
