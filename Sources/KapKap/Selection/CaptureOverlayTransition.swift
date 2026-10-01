import AppKit
import QuartzCore

@MainActor
enum CaptureOverlayTransition {
    static func show(_ panel: NSPanel) {
        panel.animationBehavior = .none
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        fade(panel, to: 1)
    }

    static func close(_ panel: NSPanel) {
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        fade(panel, to: 0) { panel.close() }
    }

    private static func fade(_ panel: NSPanel, to alpha: CGFloat, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }
}
