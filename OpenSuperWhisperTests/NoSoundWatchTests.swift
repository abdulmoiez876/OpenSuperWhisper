import XCTest

@testable import OpenSuperWhisper

/// The warning for a microphone that hears nothing: a switched-off device still plugged in.
final class NoSoundWatchTests: XCTestCase {

    func testDigitalSilenceWarnsAfterTheDelay() {
        var watch = NoSoundWatch()
        XCTAssertFalse(watch.update(peakDBFS: -120, at: 0))
        XCTAssertFalse(watch.update(peakDBFS: -120, at: 1.5))
        XCTAssertTrue(watch.update(peakDBFS: -120, at: NoSoundWatch.delay))
    }

    /// A working microphone in a quiet room is never mistaken for a dead one.
    func testAQuietRoomNeverWarns() {
        var watch = NoSoundWatch()
        for step in 0..<40 {
            XCTAssertFalse(watch.update(peakDBFS: -68, at: Double(step) * 0.25))
        }
    }

    func testSoundClearsTheWarningAtOnce() {
        var watch = NoSoundWatch()
        _ = watch.update(peakDBFS: -140, at: 0)
        XCTAssertTrue(watch.update(peakDBFS: -140, at: 3))
        XCTAssertFalse(watch.update(peakDBFS: -30, at: 3.25))
        XCTAssertFalse(watch.update(peakDBFS: -140, at: 3.5), "the delay starts over")
    }
}
