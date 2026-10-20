import Foundation

/// Notices a take that hears nothing at all: a microphone still plugged in but switched off or
/// muted on the device, which macOS keeps listing as a working input. Its samples are zeros, or
/// close to it, well under what any working microphone picks up in a quiet room. Pure, so the
/// rule is tested without a microphone.
struct NoSoundWatch {
    /// A working microphone in a quiet room peaks above -75 dBFS; a switched-off one sends digital
    /// silence, around -120 or lower.
    static let silenceDBFS: Float = -80
    /// Long enough not to flash on the instant a take starts, short enough to catch it before the
    /// user has said much into nothing.
    static let delay: TimeInterval = 2

    private var quietSince: TimeInterval?

    /// Whether to warn, after one more peak reading. Any sound clears the warning at once.
    mutating func update(peakDBFS: Float, at time: TimeInterval) -> Bool {
        guard peakDBFS < Self.silenceDBFS else {
            quietSince = nil
            return false
        }
        let since = quietSince ?? time
        quietSince = since
        return time - since >= Self.delay
    }
}
