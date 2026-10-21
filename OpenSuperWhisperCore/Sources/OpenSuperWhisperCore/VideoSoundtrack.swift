import AVFoundation
import UniformTypeIdentifiers

/// The sound of an imported video, written out as a WAV the engines can read.
///
/// Every engine opens its input with AVAudioFile, which reads audio containers only: an .mp4
/// or .mov with a picture in it throws. The queue turns an imported video into audio first, at
/// the rate the local engines want, so the recordings folder keeps about 115 MB per hour of
/// sound instead of a copy of the video.
public enum VideoSoundtrack {
    public enum Failure: LocalizedError, Equatable {
        case noSound
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .noSound: return "This video has no sound"
            case .unreadable(let reason): return "Could not read the video's sound: \(reason)"
            }
        }
    }

    static let sampleRate: Double = 16000

    private static let pcmSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    public static func isVideo(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        return type?.conforms(to: .movie) ?? false
    }

    /// Writes the first sound track of `video` to `destination` as 16 kHz mono WAV, replacing
    /// any file already there.
    public static func extract(from video: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: video)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw Failure.noSound
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: pcmSettings)
        reader.add(output)

        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .wav)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: pcmSettings)
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        guard reader.startReading() else {
            throw Failure.unreadable(reader.error?.localizedDescription ?? "unknown error")
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        while let buffer = output.copyNextSampleBuffer() {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard input.append(buffer) else { break }
        }
        input.markAsFinished()
        await writer.finishWriting()

        if reader.status == .failed || writer.status != .completed {
            reader.cancelReading()
            try? FileManager.default.removeItem(at: destination)
            let error = reader.error ?? writer.error
            throw Failure.unreadable(error?.localizedDescription ?? "unknown error")
        }
    }
}
