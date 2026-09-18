import AVFoundation
import ScreenCaptureKit
import CaptureCore

/// All mutable state is confined to the capture queue, including pause and finish.
final class SampleWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "KapKap.capture", qos: .userInitiated)
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    private let frameDuration: CMTime
    private var timeline = RecordingTimeline()
    private var lastVideoTime: CMTime?
    private var lastVideoSample: CMSampleBuffer?
    private var failure: Error?
    private var finishing = false
    private var finalFrameSubmitted = false
    private let onFailure: @Sendable (Error) -> Void

    init(url: URL, width: Int, height: Int, settings: RecordingSettings,
         onFailure: @escaping @Sendable (Error) -> Void) throws {
        self.onFailure = onFailure
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let metadata = AVMutableMetadataItem()
        metadata.identifier = .commonIdentifierDescription
        metadata.value = "KapKap recording fps=\(settings.fps)" as NSString
        writer.metadata = [metadata]
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: min(80_000_000, max(2_000_000, width * height * settings.fps / 5)),
                AVVideoExpectedSourceFrameRateKey: settings.fps,
                AVVideoMaxKeyFrameIntervalKey: settings.fps * 2
            ]
        ])
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw CaptureError.message("Cannot configure the video encoder.") }
        writer.add(video)
        if settings.microphone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw CaptureError.message("Cannot configure the audio encoder.") }
            writer.add(input)
            audio = input
        } else { audio = nil }
        super.init()
    }

    func setPaused(_ paused: Bool) async {
        await withCheckedContinuation { continuation in
            queue.async {
                let now = CMClockGetTime(CMClockGetHostTimeClock())
                if paused { self.timeline.pause(at: now) } else { self.timeline.resume(at: now) }
                continuation.resume()
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { if !self.finishing { self.fail(error) } }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        consume(sample, type: type)
    }

    func consume(_ sample: CMSampleBuffer, type: SCStreamOutputType) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finishing, failure == nil, sample.isValid, CMSampleBufferDataIsReady(sample), !timeline.isPaused else { return }
        let input: AVAssetWriterInput
        if type == .screen {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue else { return }
            input = video
        } else if type == .microphone, let audio { input = audio } else { return }
        let timestamp = sample.presentationTimeStamp
        if timeline.origin == nil {
            guard type == .screen else { return }
            guard writer.startWriting() else { fail(writer.error ?? CaptureError.message("Cannot start writing the recording.")); return }
            writer.startSession(atSourceTime: .zero)
            timeline.begin(at: timestamp)
        }
        guard let adjusted = timeline.presentationTime(for: timestamp), input.isReadyForMoreMediaData else { return }
        do {
            let retimed = try copy(sample, subtracting: timestamp - adjusted)
            guard input.append(retimed) else { throw writer.error ?? CaptureError.message("The encoder stopped accepting frames.") }
            if type == .screen { lastVideoTime = adjusted; lastVideoSample = sample }
        } catch { fail(error) }
    }

    func finish(at stopTime: CMTime) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.finishing = true
                if let failure = self.failure { self.writer.cancelWriting(); continuation.resume(throwing: failure); return }
                guard let last = self.lastVideoTime else {
                    self.writer.cancelWriting()
                    continuation.resume(throwing: CaptureError.message("No video frames were received. Check Screen Recording permission and try again."))
                    return
                }
                let endTime = CMTimeMaximum(last + self.frameDuration, self.timeline.duration(at: stopTime))
                // ScreenCaptureKit sends idle frames on a static desktop; hold the last image through the actual stop time.
                self.video.requestMediaDataWhenReady(on: self.queue) {
                    guard !self.finalFrameSubmitted else { return }
                    guard self.video.isReadyForMoreMediaData || self.writer.status != .writing else { return }
                    self.finalFrameSubmitted = true
                    do {
                        guard self.writer.status == .writing else {
                            throw self.writer.error ?? CaptureError.message("The encoder stopped before finalization.")
                        }
                        let terminalTime = endTime - self.frameDuration
                        if terminalTime > last, let sample = self.lastVideoSample, self.writer.status == .writing {
                            let terminal = try self.copy(sample, subtracting: sample.presentationTimeStamp - terminalTime)
                            guard self.video.append(terminal) else {
                                throw self.writer.error ?? CaptureError.message("Could not append the final frame.")
                            }
                        }
                        self.writer.endSession(atSourceTime: endTime)
                        self.video.markAsFinished()
                        self.audio?.markAsFinished()
                        self.lastVideoSample = nil
                        self.writer.finishWriting {
                            if self.writer.status == .completed { continuation.resume() }
                            else { continuation.resume(throwing: self.writer.error ?? CaptureError.message("Could not finish the recording.")) }
                        }
                    } catch { self.writer.cancelWriting(); continuation.resume(throwing: error) }
                }
            }
        }
    }

    func cancel() {
        queue.async { self.finishing = true; self.writer.cancelWriting() }
    }

    private func fail(_ error: Error) {
        guard failure == nil else { return }
        failure = error
        onFailure(error)
    }

    private func copy(_ sample: CMSampleBuffer, subtracting offset: CMTime) throws -> CMSampleBuffer {
        var count = 0
        var status = CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard status == noErr else { throw CaptureError.message("Cannot read sample timing (\(status)).") }
        var entries = Array(repeating: CMSampleTimingInfo(), count: count)
        status = CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &entries, entriesNeededOut: nil)
        guard status == noErr else { throw CaptureError.message("Cannot read sample timing (\(status)).") }
        for index in entries.indices {
            entries[index].presentationTimeStamp = entries[index].presentationTimeStamp - offset
            if entries[index].decodeTimeStamp.isValid { entries[index].decodeTimeStamp = entries[index].decodeTimeStamp - offset }
        }
        var result: CMSampleBuffer?
        status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
            sampleTimingEntryCount: count, sampleTimingArray: &entries, sampleBufferOut: &result)
        guard status == noErr, let result else { throw CaptureError.message("Cannot retime sample (\(status)).") }
        return result
    }
}
