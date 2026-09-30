import XCTest
import AVFoundation
import ScreenCaptureKit

/// A 160×120 frame, flat grey or, with `noise`, random pixels that no encoder can compress.
func testCaptureFrame(at time: CMTime, nonPropagatingGamma: Double? = nil, noise: Bool = false) throws -> CMSampleBuffer {
    var pixel: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 160, 120, kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel), kCVReturnSuccess)
    let image = try XCTUnwrap(pixel)
    CVPixelBufferLockBaseAddress(image, [])
    let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(image)).assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(image)
    for y in 0..<120 {
        for x in 0..<160 {
            let offset = y * stride + x * 4
            bytes[offset] = noise ? .random(in: 0...255) : 127
            bytes[offset + 1] = noise ? .random(in: 0...255) : 127
            bytes[offset + 2] = noise ? .random(in: 0...255) : 127
            bytes[offset + 3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(image, [])
    if let nonPropagatingGamma {
        CVBufferSetAttachment(image, kCVImageBufferGammaLevelKey, NSNumber(value: nonPropagatingGamma), .shouldNotPropagate)
    }
    var format: CMVideoFormatDescription?
    XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescriptionOut: &format), noErr)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: time, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
        formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample), noErr)
    let result = try XCTUnwrap(sample)
    let attachments = try XCTUnwrap(CMSampleBufferGetSampleAttachmentsArray(result, createIfNecessary: true))
    let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
    let key = SCStreamFrameInfo.status.rawValue as NSString
    let value = NSNumber(value: SCFrameStatus.complete.rawValue)
    CFDictionarySetValue(dictionary, Unmanaged.passUnretained(key).toOpaque(), Unmanaged.passUnretained(value).toOpaque())
    return result
}
