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
/// Announcements are lists of short sentences ("Bulgarian Split Squat.", "Satz zwei von drei.", "siebzehn Komma fünf Kilo, zehn Wiederholungen.").
/// Numbers are written out as words: with digits the voice guessed the language per sentence and sometimes said
/// "twenty four" or made up numbers. Exercise names and notes are read as typed.
/// The ElevenLabs voice caches each sentence on its own, so most announcements reuse audio that was already paid for.
struct Phrases {
    let german: Bool

    init(language: String = Prefs.language) {
        german = language == "de"
    }

    var started: String { german ? "Training gestartet." : "Workout started." }
    var go: String { german ? "Los!" : "Go!" }
    var tenSeconds: String { german ? "Noch zehn Sekunden." : "Ten seconds." }
    var skipped: String { german ? "Übung übersprungen." : "Exercise skipped." }
    var next: String { german ? "Danach:" : "Next:" }
    var complete: String {
        german ? "Alle Sätze geschafft. Stark! Beende das Training in der App." : "All sets done. Nice work! Finish the workout in the app."
    }

    func set(_ info: SetInfo, withName: Bool, withNote: Bool) -> [String] {
        var parts: [String] = []
        if withName { parts.append(sentence(info.exercise)) }
        if withNote, !info.note.isEmpty { parts.append(sentence(info.note)) }
        parts.append(setNumber(info.number, of: info.count))
        if let load = load(weight: info.weight, reps: info.reps) { parts.append(load) }
        return parts
    }

    func setNumber(_ number: Int, of count: Int) -> String {
        german ? "Satz \(spoken(number)) von \(spoken(count))." : "Set \(spoken(number)) of \(spoken(count))."
    }

    func load(weight: Double, reps: Int) -> String? {
        var load: [String] = []
        if weight > 0 {
            load.append(german
                ? (weight == 1 ? "ein Kilo" : "\(spoken(weight)) Kilo")
                : (weight == 1 ? "one kilo" : "\(spoken(weight)) kilos"))
        }
        if reps > 0 {
            load.append(german ? counted(reps, "Wiederholung", "Wiederholungen", one: "eine") : counted(reps, "rep", "reps", one: "one"))
        }
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
            return secondsText(seconds)
        }
        let minuteText = german ? counted(minutes, "Minute", "Minuten", one: "eine") : counted(minutes, "minute", "minutes", one: "one")
        guard rest != 0 else { return minuteText }
        return minuteText + " " + secondsText(rest)
    }

    private func secondsText(_ seconds: Int) -> String {
        german ? counted(seconds, "Sekunde", "Sekunden", one: "eine") : counted(seconds, "second", "seconds", one: "one")
    }

    /// Every sentence a workout with these exercises can say (except "time left", which depends on the moment).
    func allSentences(for entries: [ExerciseEntry], store: AppStore) -> [String] {
        var result = [started, go, tenSeconds, skipped, next, complete]
        for entry in entries {
            let exercise = store.exercise(entry.exerciseID)
            result.append(sentence(exercise?.name ?? "Exercise"))
            if let note = exercise?.note, !note.isEmpty { result.append(sentence(note)) }
            for (index, set) in entry.sets.enumerated() {
                result.append(setNumber(index + 1, of: entry.sets.count))
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

    /// "eine Wiederholung", "zehn Wiederholungen".
    private func counted(_ value: Int, _ singular: String, _ plural: String, one: String) -> String {
        value == 1 ? "\(one) \(singular)" : "\(spoken(value)) \(plural)"
    }

    private func spoken(_ value: Int) -> String {
        spoken(Double(value))
    }

    /// The number as words: "vierundzwanzig", "siebzehn Komma fünf" in German, "twenty-four" in English.
    private func spoken(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: german ? "de_DE" : "en_US")
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    }
}
