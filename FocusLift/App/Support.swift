import SwiftUI
import UIKit

/// Settings shared between views (@AppStorage) and non-view code.
enum Prefs {
    static let languageKey = "voiceLanguage"
    static let serverKey = "subsonicServer"
    static let userKey = "subsonicUser"
    static let passwordKey = "subsonicPassword"
    static let shuffleKey = "musicShuffle"
    static let defaultServer = "https://music.backl.io"

    /// "de" or "en".
    static var language: String {
        UserDefaults.standard.string(forKey: languageKey) ?? "de"
    }

    static var subsonicClient: SubsonicClient? {
        let defaults = UserDefaults.standard
        let server = defaults.string(forKey: serverKey) ?? defaultServer
        let user = defaults.string(forKey: userKey) ?? ""
        guard !server.isEmpty, !user.isEmpty else { return nil }
        return SubsonicClient(server: server, user: user, password: defaults.string(forKey: passwordKey) ?? "")
    }
}

enum Fmt {
    static let restOptions = [0, 30, 45, 60, 75, 90, 105, 120, 150, 180, 240, 300]

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func kg(_ value: Double) -> String {
        "\(number(value)) kg"
    }

    static func load(weight: Double, reps: Int) -> String {
        weight > 0 ? "\(kg(weight)) × \(reps)" : "\(reps) reps"
    }

    static func set(_ set: WorkSet) -> String {
        load(weight: set.weight, reps: set.reps)
    }

    static func rest(_ seconds: Int) -> String {
        seconds == 0 ? "off" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension View {
    /// Number pads have no return key; this adds a "Done" button above the keyboard.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}
