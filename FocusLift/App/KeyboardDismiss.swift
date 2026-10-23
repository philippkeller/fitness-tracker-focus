import SwiftUI
import UIKit

/// Tapping anywhere outside a text field closes the keyboard, in every screen of the window.
///
/// A tap recognizer on the window that doesn't swallow touches, so buttons and rows still get their tap.
/// Taps on text fields are ignored (so switching fields keeps the keyboard), and so are taps on views
/// marked with `.keepsKeyboard()`, like the reps +/− buttons.
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()

    /// Areas in window coordinates where a tap keeps the keyboard open.
    fileprivate var keepAreas: [UUID: CGRect] = [:]
    private weak var window: UIWindow?

    fileprivate func install(in window: UIWindow) {
        guard self.window !== window else { return }
        self.window = window
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func tapped() {
        window?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        let point = touch.location(in: nil)
        return !keepAreas.values.contains { $0.contains(point) }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

/// Invisible view that hands its window to the dismisser.
private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { KeyboardDismisser.shared.install(in: window) }
        }
    }
}

private struct KeepsKeyboard: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { KeyboardDismisser.shared.keepAreas[id] = frame }
                        .onChange(of: frame) { _, frame in KeyboardDismisser.shared.keepAreas[id] = frame }
                }
            }
            .onDisappear { KeyboardDismisser.shared.keepAreas[id] = nil }
    }
}

extension View {
    /// Put once at the root: taps outside text fields close the keyboard.
    func dismissesKeyboardOnTap() -> some View {
        background(KeyboardDismissInstaller().allowsHitTesting(false))
    }

    /// Tapping this view doesn't close the keyboard (e.g. +/− buttons next to a field).
    func keepsKeyboard() -> some View {
        modifier(KeepsKeyboard())
    }
}
