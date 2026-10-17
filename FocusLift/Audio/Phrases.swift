import Foundation

struct SetInfo {
    var exercise: String
    var note: String
    var number: Int
    var count: Int
    var weight: Double
    var reps: Int
}

/// Everything the app says, in German or English.
struct Phrases {
    let german: Bool

    init(language: String = Prefs.language) {
        german = language == "de"
    }

    var started: String { german ? "Training gestartet." : "Workout started." }
    var go: String { german ? "Los!" : "Go!" }
    var tenSeconds: String { german ? "Noch 10 Sekunden." : "10 seconds." }
    var skipped: String { german ? "Übung übersprungen." : "Exercise skipped." }
    var complete: String {
        german ? "Alle Sätze geschafft. Stark! Beende das Training in der App." : "All sets done. Nice work! Finish the workout in the app."
    }

    func set(_ info: SetInfo, withName: Bool, withNote: Bool) -> String {
        var parts: [String] = []
        if withName { parts.append(info.exercise + ".") }
        if withNote, !info.note.isEmpty {
            parts.append(info.note.hasSuffix(".") ? info.note : info.note + ".")
        }
        parts.append(german ? "Satz \(info.number) von \(info.count)." : "Set \(info.number) of \(info.count).")
        var load: [String] = []
        if info.weight > 0 { load.append(german ? "\(number(info.weight)) Kilo" : "\(number(info.weight)) kilos") }
        if info.reps > 0 { load.append(german ? "\(info.reps) Wiederholungen" : "\(info.reps) reps") }
        if !load.isEmpty { parts.append(load.joined(separator: ", ") + ".") }
        return parts.joined(separator: " ")
    }

    func rest(_ seconds: Int) -> String {
        german ? "Pause, \(duration(seconds))." : "Rest, \(duration(seconds))."
    }

    func upNext(_ text: String) -> String {
        (german ? "Danach: " : "Next: ") + text
    }

    func remaining(_ seconds: Int) -> String {
        german ? "Noch \(duration(seconds)) Pause." : "\(duration(seconds)) of rest left."
    }

    func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60, rest = seconds % 60
        if seconds < 60 || (rest != 0 && seconds < 180) {
            return german ? "\(seconds) Sekunden" : "\(seconds) seconds"
        }
        let minuteText = german
            ? (minutes == 1 ? "1 Minute" : "\(minutes) Minuten")
            : (minutes == 1 ? "1 minute" : "\(minutes) minutes")
        guard rest != 0 else { return minuteText }
        return minuteText + (german ? " \(rest) Sekunden" : " \(rest) seconds")
    }

    /// "17,5" in German so the voice says "Komma", "17.5" in English.
    private func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: german ? "de_DE" : "en_US")
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
