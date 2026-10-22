import Foundation

/// A dictation the person flagged as wrong, reduced to what diagnoses it without the audio.
///
/// Plain fields, not a `Recording`, so building the message and keeping it under the endpoint's
/// limit can be tested on their own. The audio stays on this Mac; only what the person chose to
/// send when they tapped "report" goes out, and never where they were dictating.
struct DictationReportDraft: Equatable {
    /// What the person typed about what went wrong, if anything (e.g. "spoke French, got English").
    var note: String
    var modelUsed: String?
    /// The language the engine was set to: "auto", "en", "fr"… The whole point for the case where
    /// French audio comes back in English.
    var languageSetting: String?
    var translateToEnglish: Bool
    var durationSeconds: Int
    /// The text the dictation produced, after cleanup and style.
    var output: String
    /// The raw engine output, sent only when it differs from `output`, so a cleanup bug and an
    /// engine bug can be told apart.
    var rawOutput: String?
    var appVersion: String
    var osVersion: String
}

/// Builds the message and the submission a reported dictation sends to the feedback endpoint.
enum DictationReport {

    /// How much of the output text a report may carry. The rest is dropped before the raw text, so
    /// a very long dictation still sends its settings and the start of what it produced.
    static let maxTextLength = 2000

    static func message(for draft: DictationReportDraft, outputLimit: Int, includeRaw: Bool) -> String {
        var lines = ["Dictation reported as wrong."]
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { lines.append(note) }
        lines.append("model: \(draft.modelUsed ?? "unknown")")
        lines.append("language: \(draft.languageSetting ?? "auto")"
            + (draft.translateToEnglish ? " · translate to English: on" : ""))
        lines.append("duration: \(draft.durationSeconds)s")
        lines.append("output: \(String(draft.output.prefix(max(0, outputLimit))))")
        if includeRaw, let raw = draft.rawOutput, raw != draft.output {
            lines.append("raw: \(String(raw.prefix(max(0, outputLimit))))")
        }
        return lines.joined(separator: "\n")
    }

    /// A submission carrying the dictation's settings and text. The person's email is left blank:
    /// they can add one in the card, but a one-tap report does not ask for it. Trimmed to fit the
    /// endpoint, dropping the raw text first, then shortening the output.
    static func submission(for draft: DictationReportDraft, email: String = "") -> FeedbackSubmission {
        let details = "OpenSuperWhisper \(draft.appVersion) · macOS \(draft.osVersion)"
        func make(outputLimit: Int, includeRaw: Bool) -> FeedbackSubmission {
            FeedbackSubmission(kind: .bug,
                               message: message(for: draft, outputLimit: outputLimit, includeRaw: includeRaw),
                               email: email,
                               details: details)
        }

        let full = make(outputLimit: maxTextLength, includeRaw: true)
        if FeedbackSender.fitsLimits(full) { return full }

        let withoutRaw = make(outputLimit: maxTextLength, includeRaw: false)
        if FeedbackSender.fitsLimits(withoutRaw) { return withoutRaw }

        var outputLimit = maxTextLength
        while outputLimit > 0 {
            outputLimit /= 2
            let shorter = make(outputLimit: outputLimit, includeRaw: false)
            if FeedbackSender.fitsLimits(shorter) { return shorter }
        }
        return make(outputLimit: 0, includeRaw: false)
    }
}
