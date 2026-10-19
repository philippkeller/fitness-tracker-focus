import SwiftUI
import UIKit

/// Observe taps without swallowing buttons or the list's scrolling gestures.
struct OutsideTapKeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> TapObserver { TapObserver() }
    func updateUIView(_ uiView: TapObserver, context: Context) {}

    static func dismantleUIView(_ uiView: TapObserver, coordinator: ()) {
        uiView.detach()
    }

    final class TapObserver: UIView, UIGestureRecognizerDelegate {
        private weak var observedWindow: UIWindow?
        private lazy var tap: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            return tap
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            if let window {
                observedWindow = window
                window.addGestureRecognizer(tap)
            }
        }

        func detach() {
            observedWindow?.removeGestureRecognizer(tap)
            observedWindow = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard window != nil, bounds.contains(touch.location(in: self)) else { return false }
            // A tap within any editor must retain normal cursor/selection behaviour.
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func tapped() {
            // Let a button finish its action before dismissing focus-dependent controls.
            DispatchQueue.main.async { [weak self] in
                self?.window?.endEditing(true)
            }
        }
    }
}
