import CoreMedia

public struct RecordingTimeline {
    public private(set) var origin: CMTime?
    public private(set) var isPaused = false
    public private(set) var removedTime = CMTime.zero
    private var pauseStart: CMTime?
    private var resumeBoundary: CMTime?

    public init() {}

    public mutating func begin(at time: CMTime) {
        if origin == nil { origin = time }
    }

    public mutating func pause(at time: CMTime) {
        guard !isPaused else { return }
        isPaused = true
        pauseStart = time
    }

    public mutating func resume(at time: CMTime) {
        guard isPaused, let pauseStart else { return }
        if let origin {
            let start = CMTimeMaximum(pauseStart, origin)
            removedTime = removedTime + CMTimeMaximum(.zero, time - start)
        }
        resumeBoundary = time
        self.pauseStart = nil
        isPaused = false
    }

    public func presentationTime(for time: CMTime) -> CMTime? {
        guard !isPaused, let origin, time >= origin else { return nil }
        if let resumeBoundary, time < resumeBoundary { return nil }
        let adjusted = time - origin - removedTime
        return adjusted >= .zero ? adjusted : nil
    }

    public func duration(at time: CMTime) -> CMTime {
        guard let origin else { return .zero }
        return CMTimeMaximum(.zero, (pauseStart ?? time) - origin - removedTime)
    }
}
