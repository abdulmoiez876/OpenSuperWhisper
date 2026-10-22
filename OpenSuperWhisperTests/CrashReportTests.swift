import XCTest

@testable import OpenSuperWhisper

final class CrashReportModeTests: XCTestCase {

    func testRawValuesAreStable() {
        XCTAssertEqual(CrashReportMode.ask.rawValue, "ask")
        XCTAssertEqual(CrashReportMode.auto.rawValue, "auto")
        XCTAssertEqual(CrashReportMode.off.rawValue, "off")
    }

    func testAFreshInstallAsks() {
        XCTAssertEqual(CrashReportMode.default, .ask)
    }

    /// An absent or unreadable value reads as the default rather than failing, so a key written by
    /// a newer build never leaves the setting in no state at all.
    func testResolveFallsBackToTheDefault() {
        XCTAssertEqual(CrashReportMode.resolve("auto"), .auto)
        XCTAssertEqual(CrashReportMode.resolve(nil), .ask)
        XCTAssertEqual(CrashReportMode.resolve("something-newer"), .ask)
    }

    func testTheModeDecidesWhatHappensToABatch() {
        XCTAssertEqual(CrashReporter.action(for: .off), .discard)
        XCTAssertEqual(CrashReporter.action(for: .auto), .send)
        XCTAssertEqual(CrashReporter.action(for: .ask), .ask)
    }
}

final class CrashReportTests: XCTestCase {

    private func draft(frames: [String], cause: String = "EXC_BAD_ACCESS (SIGSEGV)") -> CrashReportDraft {
        CrashReportDraft(kind: .crash, cause: cause, frames: frames,
                         appVersion: "0.14.0 (63)", osVersion: "26.2")
    }

    // MARK: - Message

    func testTheMessageLeadsWithTheCauseThenNumbersTheFrames() {
        let message = CrashReport.message(for: draft(frames: ["A 0x01", "B 0x02", "C 0x03"]),
                                          frameLimit: 3)

        XCTAssertEqual(message, "crash: EXC_BAD_ACCESS (SIGSEGV)\n#0 A 0x01\n#1 B 0x02\n#2 C 0x03")
    }

    /// The deepest frames go first: the fault is at the top of the stack.
    func testTheFrameLimitKeepsTheTopOfTheStack() {
        let message = CrashReport.message(for: draft(frames: ["top 0x01", "mid 0x02", "deep 0x03"]),
                                          frameLimit: 1)

        XCTAssertEqual(message, "crash: EXC_BAD_ACCESS (SIGSEGV)\n#0 top 0x01")
    }

    // MARK: - Submission

    func testAnOrdinaryStackSendsEveryFrameAnonymously() {
        let frames = (0..<20).map { "OpenSuperWhisper 0x\($0)" }
        let submission = CrashReport.submission(for: draft(frames: frames))

        XCTAssertEqual(submission.kind, .crash)
        XCTAssertEqual(submission.email, "")
        XCTAssertEqual(submission.details, "OpenSuperWhisper 0.14.0 (63) · macOS 26.2")
        XCTAssertEqual(submission.context, "app · crash · OpenSuperWhisper 0.14.0 (63) · macOS 26.2")
        XCTAssertTrue(submission.message.contains("#19 OpenSuperWhisper 0x19"))
        XCTAssertTrue(FeedbackSender.fitsLimits(submission))
    }

    /// A stack far past the endpoint's byte limit still sends: frames are dropped from the bottom
    /// until it fits, and the top frame, where the fault is, always survives.
    func testAnOversizedStackIsTrimmedToFitAndKeepsItsTop() {
        let frames = (0..<400).map { "VeryLongBinaryNameThatPadsEachFrameNicely_\($0) 0x000000010abcdef0" }
        let submission = CrashReport.submission(for: draft(frames: frames))

        XCTAssertTrue(FeedbackSender.fitsLimits(submission))
        XCTAssertTrue(submission.message.contains("#0 VeryLongBinaryNameThatPadsEachFrameNicely_0 "))
        XCTAssertFalse(submission.message.contains("#399 "))
    }

    func testAnOverlongCauseIsTruncated() {
        let message = CrashReport.message(for: draft(frames: [], cause: String(repeating: "x", count: 500)),
                                          frameLimit: 0)

        XCTAssertTrue(message.hasPrefix("crash: "))
        XCTAssertLessThanOrEqual(message.count, "crash: ".count + 200)
    }
}
