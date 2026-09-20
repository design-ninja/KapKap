import Foundation

/// One set of frame rates for the whole app, so recording and export never disagree.
public enum FrameRate {
    public static let choices = [60, 30, 24, 15]
    public static let standard = 30
    public static let maximum = 60

    public static func clamp(_ value: Int) -> Int { min(maximum, max(1, value)) }

    /// Export can thin frames out but cannot invent them, so a source caps its own choices.
    public static func choices(upTo source: Int) -> [Int] {
        Array(Set(choices + [source])).filter { $0 <= source }.sorted(by: >)
    }
}
