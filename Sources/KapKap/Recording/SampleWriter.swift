import AVFoundation
import ScreenCaptureKit
import CaptureCore

/// All mutable state is confined to the capture queue, including pause and finish.
final class SampleWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "KapKap.capture", qos: .userInitiated)
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    /// System audio gets its own track so the microphone stays separable; exports mix the two.
    private let systemAudio: AVAssetWriterInput?
    private let frameDuration: CMTime
    private let clickHighlights: ClickHighlightRenderer?
    private var clickTimer: DispatchSourceTimer?
    private var timeline = RecordingTimeline()
    private var lastVideoTime: CMTime?
    private var lastVideoSample: CMSampleBuffer?
    private var failure: Error?
    /// ScreenCaptureKit ended the stream on its own (the user, the system, a lost display). The writer is
    /// still healthy, so what arrived so far is finished normally instead of being thrown away.
    private var interruption: Error?
    private var finishing = false
    private var finalFrameSubmitted = false
    private let onFailure: @Sendable (Error) -> Void

    init(url: URL, width: Int, height: Int, settings: RecordingSettings, clickScale: CGFloat = 1,
         onFailure: @escaping @Sendable (Error) -> Void) throws {
        self.onFailure = onFailure
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // Fragments keep the file readable if KapKap dies mid-recording; finishing rewrites a plain MP4.
        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
        let metadata = AVMutableMetadataItem()
        metadata.identifier = .commonIdentifierDescription
        metadata.value = "KapKap recording fps=\(settings.fps)" as NSString
        writer.metadata = [metadata]
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
        clickHighlights = settings.highlightClicks ? try ClickHighlightRenderer(width: width, height: height, scale: clickScale) : nil
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: min(80_000_000, max(2_000_000, width * height * settings.fps / 5)),
                AVVideoExpectedSourceFrameRateKey: settings.fps,
                AVVideoMaxKeyFrameIntervalKey: settings.fps * 2,
                // With B-frames, a fragmented file cannot take the held last frame at stop (-16341).
                AVVideoAllowFrameReorderingKey: false
            ]
        ])
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw CaptureError.message("Cannot configure the video encoder.") }
        writer.add(video)
        let writer = self.writer
        func audioInput(channels: Int, bitRate: Int) throws -> AVAssetWriterInput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: bitRate
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw CaptureError.message("Cannot configure the audio encoder.") }
            writer.add(input)
            return input
        }
        audio = settings.microphone ? try audioInput(channels: 1, bitRate: 128_000) : nil
        systemAudio = settings.systemAudio ? try audioInput(channels: 2, bitRate: 192_000) : nil
        super.init()
    }

    func setPaused(_ paused: Bool) async {
        await withCheckedContinuation { continuation in
            queue.async {
                let now = CMClockGetTime(CMClockGetHostTimeClock())
                if paused {
                    if self.clickTimer != nil {
                        self.clickHighlights?.clear()
                        self.appendHighlightFrame(at: now)
                        self.stopClickAnimation()
                    }
                    self.timeline.pause(at: now)
                } else {
                    self.timeline.resume(at: now)
                    if self.clickHighlights != nil, self.lastVideoSample != nil { self.startClickAnimation() }
                }
                continuation.resume()
            }
        }
    }

    func highlightClick(at point: CGPoint, time: CMTime) {
        queue.async {
            guard !self.finishing, self.failure == nil, self.interruption == nil, !self.timeline.isPaused,
                  self.timeline.presentationTime(for: time) != nil, let highlights = self.clickHighlights else { return }
            highlights.add(at: point, time: time)
            self.startClickAnimation()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.interrupt(error) }
    }

    /// Stops taking samples and reports the reason; `finish` still saves everything written before it.
    func interrupt(_ error: Error) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finishing, failure == nil, interruption == nil else { return }
        interruption = error
        stopClickAnimation()
        onFailure(error)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        consume(sample, type: type)
    }

    func consume(_ sample: CMSampleBuffer, type: SCStreamOutputType) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finishing, failure == nil, interruption == nil, sample.isValid, CMSampleBufferDataIsReady(sample), !timeline.isPaused else { return }
        let input: AVAssetWriterInput
        if type == .screen {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue else { return }
            input = video
        } else if type == .microphone, let audio { input = audio }
        else if type == .audio, let systemAudio { input = systemAudio } else { return }
        let timestamp = sample.presentationTimeStamp
        if timeline.origin == nil {
            guard type == .screen else { return }
            guard writer.startWriting() else { fail(writer.error ?? CaptureError.message("Cannot start writing the recording.")); return }
            writer.startSession(atSourceTime: .zero)
            timeline.begin(at: timestamp)
        }
        guard let adjusted = timeline.presentationTime(for: timestamp) else { return }
        if type == .screen {
            lastVideoSample = sample
            if let lastVideoTime, adjusted <= lastVideoTime { return }
        }
        guard input.isReadyForMoreMediaData else { return }
        do {
            let rendered = type == .screen ? try clickHighlights?.render(sample, at: timestamp) ?? sample : sample
            let retimed = try copy(rendered, subtracting: rendered.presentationTimeStamp - adjusted)
            guard input.append(retimed) else { throw writer.error ?? CaptureError.message("The encoder stopped accepting frames.") }
            if type == .screen { lastVideoTime = adjusted }
        } catch { fail(error) }
    }

    func finish(at stopTime: CMTime) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.finishing = true
                self.stopClickAnimation()
                self.clickHighlights?.clear()
                // A writer that failed has nothing more to finish; its file stays on disk for recovery.
                if self.writer.status == .failed {
                    continuation.resume(throwing: self.writer.error ?? self.failure ?? CaptureError.message("The encoder failed."))
                    return
                }
                guard let last = self.lastVideoTime else {
                    self.writer.cancelWriting()
                    continuation.resume(throwing: CaptureError.message("No video frames were received. Check Screen Recording permission and try again."))
                    return
                }
                // After an interruption or a failed frame the recording ends at the last frame that made it in.
                let endTime = self.interruption != nil || self.failure != nil
                    ? last + self.frameDuration
                    : CMTimeMaximum(last + self.frameDuration, self.timeline.duration(at: stopTime))
                // ScreenCaptureKit sends idle frames on a static desktop; hold the last image through the actual stop time.
                self.video.requestMediaDataWhenReady(on: self.queue) {
                    guard !self.finalFrameSubmitted else { return }
                    guard self.video.isReadyForMoreMediaData || self.writer.status != .writing else { return }
                    self.finalFrameSubmitted = true
                    do {
                        guard self.writer.status == .writing else {
                            throw self.writer.error ?? CaptureError.message("The encoder stopped before finalization.")
                        }
                        var sessionEnd = endTime
                        let terminalTime = endTime - self.frameDuration
                        if terminalTime > last, let sample = self.lastVideoSample {
                            if let terminal = try? self.copy(sample, subtracting: sample.presentationTimeStamp - terminalTime) {
                                guard self.video.append(terminal) else {
                                    throw self.writer.error ?? CaptureError.message("Could not append the final frame.")
                                }
                            } else { sessionEnd = last + self.frameDuration }
                        }
                        self.writer.endSession(atSourceTime: sessionEnd)
                        self.video.markAsFinished()
                        self.audio?.markAsFinished()
                        self.systemAudio?.markAsFinished()
                        self.lastVideoSample = nil
                        self.writer.finishWriting {
                            if self.writer.status == .completed { continuation.resume() }
                            else { continuation.resume(throwing: self.writer.error ?? CaptureError.message("Could not finish the recording.")) }
                        }
                    } catch {
                        // Never cancel here: cancelling deletes the file, and a fragmented one is still recoverable.
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func cancel() {
        queue.async { self.finishing = true; self.stopClickAnimation(); self.writer.cancelWriting() }
    }

    /// Idle desktop frames do not arrive at video cadence, so finish the pulse using the last clean image.
    private func appendHighlightFrame(at time: CMTime) {
        guard !finishing, failure == nil, interruption == nil, let sample = lastVideoSample, let highlights = clickHighlights,
              let adjusted = timeline.presentationTime(for: time), let lastVideoTime,
              adjusted - lastVideoTime >= frameDuration, video.isReadyForMoreMediaData else { return }
        do {
            let rendered = try highlights.render(sample, at: time)
            let retimed = try copy(rendered, subtracting: rendered.presentationTimeStamp - adjusted)
            guard video.append(retimed) else { throw writer.error ?? CaptureError.message("Cannot encode the click highlight.") }
            self.lastVideoTime = adjusted
            if !highlights.hasPulses { stopClickAnimation() }
        } catch { fail(error) }
    }

    private func startClickAnimation() {
        guard clickTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: frameDuration.seconds)
        timer.setEventHandler { [weak self] in
            self?.appendHighlightFrame(at: CMClockGetTime(CMClockGetHostTimeClock()))
        }
        clickTimer = timer
        timer.resume()
    }

    private func stopClickAnimation() {
        clickTimer?.cancel()
        clickTimer = nil
    }

    private func fail(_ error: Error) {
        guard failure == nil else { return }
        failure = error
        stopClickAnimation()
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
