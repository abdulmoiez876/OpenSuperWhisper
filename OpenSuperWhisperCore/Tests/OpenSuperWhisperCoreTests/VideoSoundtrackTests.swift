import AVFoundation
import XCTest
@testable import OpenSuperWhisperCore

/// Importing a video: its sound becomes a WAV the engines can open, since AVAudioFile reads
/// audio containers only.
final class VideoSoundtrackTests: CoreTestCase {
    private var tempFiles: [URL] = []

    override func tearDown() {
        tempFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        tempFiles = []
        super.tearDown()
    }

    func testVideoSoundBecomesMonoWavAtTheEngineRate() async throws {
        let video = try await writeMovie(seconds: 1, withSound: true)
        let wav = tempURL("wav")

        try await VideoSoundtrack.extract(from: video, to: wav)

        let file = try AVAudioFile(forReading: wav)
        XCTAssertEqual(file.processingFormat.sampleRate, VideoSoundtrack.sampleRate)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length) / VideoSoundtrack.sampleRate, 1, accuracy: 0.05)
    }

    func testTheEnginesReadTheExtractedSound() async throws {
        let video = try await writeMovie(seconds: 1, withSound: true)
        let wav = tempURL("wav")

        try await VideoSoundtrack.extract(from: video, to: wav)
        let samples = try await AudioPCMConverter.convertAudioToPCM(fileURL: wav)

        XCTAssertGreaterThan(samples?.map(abs).max() ?? 0, 0.1, "the tone survived")
    }

    func testSilentFilmSaysItHasNoSound() async throws {
        let video = try await writeMovie(seconds: 1, withSound: false)

        do {
            try await VideoSoundtrack.extract(from: video, to: tempURL("wav"))
            XCTFail("a video without a sound track has nothing to transcribe")
        } catch let failure as VideoSoundtrack.Failure {
            XCTAssertEqual(failure, .noSound)
        }
    }

    func testOnlyVideosAreExtracted() {
        XCTAssertTrue(VideoSoundtrack.isVideo(URL(fileURLWithPath: "/tmp/talk.mov")))
        XCTAssertTrue(VideoSoundtrack.isVideo(URL(fileURLWithPath: "/tmp/talk.mp4")))
        XCTAssertFalse(VideoSoundtrack.isVideo(URL(fileURLWithPath: "/tmp/talk.m4a")))
        XCTAssertFalse(VideoSoundtrack.isVideo(URL(fileURLWithPath: "/tmp/talk.wav")))
    }

    // MARK: - Fixtures

    private func tempURL(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-video-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        tempFiles.append(url)
        return url
    }

    /// A tiny MPEG-4 movie like a phone or a screen recorder makes: grey 64×64 H.264 frames and,
    /// optionally, a 440 Hz stereo tone in AAC.
    private func writeMovie(seconds: Int, withSound: Bool) async throws -> URL {
        let url = tempURL("mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let frameRate: Int32 = 10
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(video)

        let rate = 44100.0
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ])
        if withSound { writer.add(audio) }

        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<(Int(frameRate) * seconds) {
            while !video.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            let buffer = try XCTUnwrap(Self.greyFrame(pool: pixels.pixelBufferPool))
            pixels.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: frameRate))
        }
        video.markAsFinished()

        if withSound {
            while !audio.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            audio.append(try Self.tone(seconds: seconds, rate: rate))
            audio.markAsFinished()
        }

        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        return url
    }

    private static func greyFrame(pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0x80, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private static func tone(seconds: Int, rate: Double) throws -> CMSampleBuffer {
        let frames = Int(rate) * seconds
        var samples = [Int16](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            let value = Int16(sin(2 * .pi * 440 * Double(i) / rate) * 16000)
            samples[2 * i] = value
            samples[2 * i + 1] = value
        }
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 2, interleaved: true))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        pcm.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBufferPointer { source in
            pcm.int16ChannelData![0].update(from: source.baseAddress!, count: source.count)
        }

        var description: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: format.streamDescription, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &description)
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(rate)),
                                        presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
                             refcon: nil, formatDescription: description, sampleCount: frames,
                             sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                             sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
        let result = try XCTUnwrap(sampleBuffer)
        CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: nil,
                                                       blockBufferMemoryAllocator: nil, flags: 0,
                                                       bufferList: pcm.audioBufferList)
        return result
    }
}
