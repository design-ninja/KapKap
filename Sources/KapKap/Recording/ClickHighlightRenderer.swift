import AVFoundation
import CaptureCore

/// Used only on SampleWriter's capture queue. Input frames remain untouched.
final class ClickHighlightRenderer {
    static let duration = 0.42
    private struct Pulse {
        let point: CGPoint
        let time: CMTime
    }
    private var pulses: [Pulse] = []
    private let pool: CVPixelBufferPool
    private let scale: CGFloat

    init(width: Int, height: Int, scale: CGFloat) throws {
        self.scale = scale
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else {
            throw CaptureError.message("Cannot prepare click highlights (\(status)).")
        }
        self.pool = pool
    }

    var hasPulses: Bool { !pulses.isEmpty }

    func add(at point: CGPoint, time: CMTime) {
        pulses.append(Pulse(point: point, time: time))
    }

    func clear() { pulses.removeAll() }

    func render(_ sample: CMSampleBuffer, at time: CMTime) throws -> CMSampleBuffer {
        pulses.removeAll { (time - $0.time).seconds >= Self.duration }
        let visible = pulses.filter { time >= $0.time }
        guard !visible.isEmpty else { return sample }
        guard let source = sample.imageBuffer else {
            throw CaptureError.message("Cannot read the frame for click highlights.")
        }
        var pixel: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixel)
        guard status == kCVReturnSuccess, let pixel else {
            throw CaptureError.message("Cannot draw click highlights (\(status)).")
        }
        CVBufferRemoveAllAttachments(pixel)
        CVBufferPropagateAttachments(source, pixel)
        if let attachments = CVBufferCopyAttachments(source, .shouldNotPropagate) {
            CVBufferSetAttachments(pixel, attachments, .shouldNotPropagate)
        }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        CVPixelBufferLockBaseAddress(pixel, [])
        defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
        guard let input = CVPixelBufferGetBaseAddress(source), let output = CVPixelBufferGetBaseAddress(pixel) else {
            throw CaptureError.message("Cannot access the frame for click highlights.")
        }
        let width = CVPixelBufferGetWidth(pixel)
        let height = CVPixelBufferGetHeight(pixel)
        guard CVPixelBufferGetWidth(source) == width, CVPixelBufferGetHeight(source) == height,
              CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA else {
            throw CaptureError.message("The captured frame does not match the click highlight canvas.")
        }
        let sourceStride = CVPixelBufferGetBytesPerRow(source)
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        for row in 0..<height {
            memcpy(output.advanced(by: row * stride), input.advanced(by: row * sourceStride), width * 4)
        }
        guard let context = CGContext(data: output, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: stride, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw CaptureError.message("Cannot create the click highlight canvas.")
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        for pulse in visible {
            let progress = min(1, (time - pulse.time).seconds / Self.duration)
            let eased = 1 - pow(1 - progress, 3)
            let opacity = CGFloat(pow(1 - progress, 2))
            let radius = (7 + 19 * eased) * scale
            let center = CGPoint(x: pulse.point.x * CGFloat(width), y: pulse.point.y * CGFloat(height))
            let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.setFillColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.12 * opacity))
            context.fillEllipse(in: circle)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.3 * opacity))
            context.setLineWidth(3 * scale)
            context.strokeEllipse(in: circle)
            context.setStrokeColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.85 * opacity))
            context.setLineWidth(1.5 * scale)
            context.strokeEllipse(in: circle)
        }
        // Captured buffers can have a different row stride and non-propagating color metadata.
        var format: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: pixel, formatDescriptionOut: &format)
        guard formatStatus == noErr, let format else {
            throw CaptureError.message("Cannot describe the click highlight frame (\(formatStatus)).")
        }
        var timing = CMSampleTimingInfo(duration: sample.duration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel,
            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &result)
        guard sampleStatus == noErr, let result else {
            throw CaptureError.message("Cannot encode click highlights (\(sampleStatus)).")
        }
        return result
    }
}
