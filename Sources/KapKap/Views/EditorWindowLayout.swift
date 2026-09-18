import SwiftUI

struct EditorWindowLayout: NSViewRepresentable {
    let title: String
    let aspectRatio: Double?

    func makeNSView(context: Context) -> LayoutView { LayoutView() }
    func updateNSView(_ view: LayoutView, context: Context) {
        view.editorTitle = title
        view.aspectRatio = aspectRatio
        view.applyLayout()
    }

    final class LayoutView: NSView {
        var editorTitle = ""
        var aspectRatio: Double?
        private var didSize = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyLayout() }
        func applyLayout() {
            guard let window else { return }
            window.title = editorTitle
            guard !didSize, let aspectRatio, aspectRatio > 0 else { return }
            didSize = true
            let screen = window.screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
            let maxHeight = max(330, screen.height - 100)
            let width = min(1000, max(760, (maxHeight - 48) * aspectRatio))
            let height = min(maxHeight, max(330, width / aspectRatio + 48))
            window.setContentSize(NSSize(width: width, height: height))
            window.center()
        }
    }
}
