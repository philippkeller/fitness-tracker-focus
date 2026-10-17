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
///
/// Announcements are lists of short sentences ("Bulgarian Split Squat.", "Satz 2 von 3.", "17,5 Kilo, 10 Wiederholungen.").
/// The ElevenLabs voice caches each sentence on its own, so most announcements reuse audio that was already paid for.
struct Phrases {
    let german: Bool

    init(language: String = Prefs.language) {
        german = language == "de"
    }

    var started: String { german ? "Training gestartet." : "Workout started." }
    var go: String { german ? "Los!" : "Go!" }
    var tenSeconds: String { german ? "Noch 10 Sekunden." : "10 seconds." }
    var skipped: String { german ? "Übung übersprungen." : "Exercise skipped." }
    var next: String { german ? "Danach:" : "Next:" }
    var complete: String {
        german ? "Alle Sätze geschafft. Stark! Beende das Training in der App." : "All sets done. Nice work! Finish the workout in the app."
    }

    func set(_ info: SetInfo, withName: Bool, withNote: Bool) -> [String] {
        var parts: [String] = []
        if withName { parts.append(sentence(info.exercise)) }
        if withNote, !info.note.isEmpty { parts.append(sentence(info.note)) }
        parts.append(german ? "Satz \(info.number) von \(info.count)." : "Set \(info.number) of \(info.count).")
        if let load = load(weight: info.weight, reps: info.reps) { parts.append(load) }
        return parts
    }

    func load(weight: Double, reps: Int) -> String? {
        var load: [String] = []
        if weight > 0 { load.append(german ? "\(number(weight)) Kilo" : "\(number(weight)) kilos") }
        if reps > 0 { load.append(german ? "\(reps) Wiederholungen" : "\(reps) reps") }
        return load.isEmpty ? nil : load.joined(separator: ", ") + "."
    }

    func rest(_ seconds: Int) -> String {
        german ? "Pause, \(duration(seconds))." : "Rest, \(duration(seconds))."
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

    /// Every sentence a workout with these exercises can say (except "time left", which depends on the moment).
    func allSentences(for entries: [ExerciseEntry], store: AppStore) -> [String] {
        var result = [started, go, tenSeconds, skipped, next, complete]
        for entry in entries {
            let exercise = store.exercise(entry.exerciseID)
            result.append(sentence(exercise?.name ?? "Exercise"))
            if let note = exercise?.note, !note.isEmpty { result.append(sentence(note)) }
            for (index, set) in entry.sets.enumerated() {
                result.append(german ? "Satz \(index + 1) von \(entry.sets.count)." : "Set \(index + 1) of \(entry.sets.count).")
                if let load = load(weight: set.weight, reps: set.reps) { result.append(load) }
                if set.rest > 0 { result.append(rest(set.rest)) }
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    private func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }

    /// "17,5" in German so the voice says "Komma", "17.5" in English.
    private func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: german ? "de_DE" : "en_US")
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
