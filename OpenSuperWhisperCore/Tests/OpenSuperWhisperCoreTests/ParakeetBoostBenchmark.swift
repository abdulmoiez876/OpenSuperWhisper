import Foundation
import XCTest
@testable import OpenSuperWhisperCore

/// Local benchmark for Parakeet with boost terms (#235): latency, word error rate and false
/// replacements, with and without terms. Needs downloaded models and labelled clips, so it only
/// runs when `OSW_PARAKEET_BENCH` points at a folder of WAVs with a `_refs.json`
/// (`[{ "file", "ref" }]`); the report goes to `OSW_PARAKEET_BENCH_OUT`.
final class ParakeetBoostBenchmark: CoreTestCase {

    /// Names that are in the clips, which the model tends to spell its own way.
    static let spokenTerms = ["Sintra", "Marianas", "Dunlap", "Bennet", "Nyiragongo"]
    /// Short words nobody says in the clips: any of them in an output is a false replacement.
    static let baitTerms = ["Rsets", "Kai", "Ola", "Zed", "Tam", "Nix", "Obo", "Vex"]

    private struct Clip: Decodable { let file: String; let ref: String }

    func testBenchmark() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let folder = environment["OSW_PARAKEET_BENCH"] else {
            throw XCTSkip("Set OSW_PARAKEET_BENCH to a folder of labelled clips to run it.")
        }
        let directory = URL(fileURLWithPath: folder)
        let clips = try JSONDecoder().decode([Clip].self,
                                             from: Data(contentsOf: directory.appendingPathComponent("_refs.json")))
        let engine = FluidAudioEngine(versionOverride: "v3")
        try await engine.initialize()

        var report: [String: Any] = [:]
        for (name, terms) in [("none", [String]()), ("terms", Self.spokenTerms + Self.baitTerms)] {
            var settings = Fixtures.pinnedSettings()
            settings.snippetTriggers = terms
            var rows: [[String: Any]] = []
            var errors = 0, words = 0, baits = 0, totalMs = 0.0
            // The first dictation pays any one-off load, so it is timed apart.
            for clip in clips {
                let start = Date()
                let text = try await engine.transcribeAudio(url: directory.appendingPathComponent(clip.file),
                                                            settings: settings)
                let ms = Date().timeIntervalSince(start) * 1000
                let hyp = Self.words(text), ref = Self.words(clip.ref)
                let distance = Self.editDistance(ref, hyp)
                let found = Self.baitTerms.filter { bait in hyp.contains(bait.lowercased()) }
                errors += distance; words += ref.count; baits += found.count; totalMs += ms
                rows.append(["file": clip.file, "ms": Int(ms), "text": text, "bait": found])
            }
            report[name] = ["wer": Double(errors) / Double(max(words, 1)), "baits": baits,
                            "totalMs": Int(totalMs), "firstMs": rows.first?["ms"] ?? 0, "clips": rows]
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if let out = environment["OSW_PARAKEET_BENCH_OUT"] {
            try data.write(to: URL(fileURLWithPath: out))
        }
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
    }

    static func editDistance(_ a: [String], _ b: [String]) -> Int {
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in stride(from: 1, through: b.count, by: 1) {
                let current = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                previous = current
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }
}
