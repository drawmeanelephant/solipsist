import SwiftUI

/// Height of the main window's floating glass toolbar band (#130).
///
/// The main window uses `.fullSizeContentView` + `.glassEffect()`, so the
/// toolbar floats *over* the content and is deliberately absent from the
/// SwiftUI safe area (a `GeometryReader` in the detail column reports
/// `top == 0`). AppKit still reserves the band in `contentLayoutRect`, so
/// `frame.height - contentLayoutRect.maxY` is the exact band. Mailbox lists
/// inset their scroll content by this measured value instead of a hardcoded
/// spacer.
private struct ToolbarBandKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var toolbarBand: CGFloat {
        get { self[ToolbarBandKey.self] }
        set { self[ToolbarBandKey.self] = newValue }
    }
}

/// Measures the band from the window the view lands in.
struct ToolbarBandReader: NSViewRepresentable {
    var onBand: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { measure(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { measure(nsView) }
    }

    private func measure(_ view: NSView) {
        guard let window = view.window else { return }
        onBand(max(0, window.frame.height - window.contentLayoutRect.maxY))
    }
}
