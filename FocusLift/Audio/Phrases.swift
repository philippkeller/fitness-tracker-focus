import Foundation

struct SetInfo {
    var exercise: String
    var note: String
    var number: Int
    var count: Int
    var weight: Double
    var reps: Int

    /// No weight and no reps, e.g. a warm-up on the cross trainer: the app only waits for "done".
    var isUntracked: Bool { weight == 0 && reps == 0 }
}

/// Everything the app says, in German or English.
///
/// Announcements are lists of short sentences ("Bulgarian Split Squat.", "Satz zwei von drei.", "Zehn Wiederholungen mit siebzehn Komma fünf Kilo.").
/// Numbers are written out as words: with digits the voice guessed the language per sentence and sometimes said
/// "twenty four" or made up numbers. Exercise names and notes are read as typed.
/// The ElevenLabs voice caches each sentence on its own, so most announcements reuse audio that was already paid for.
struct Phrases {
    let german: Bool

    init(language: String = Prefs.language) {
        german = language == "de"
    }

    var started: String { german ? "Training gestartet." : "Workout started." }
    /// Said when the next set starts, picked at random each time.
    static let goShouts = [
        "Chewbacca!", "Lölihund!", "Schnabeltasse!", "Gigeligugeli!", "Rinderspaziergang!",
        "Über de Tisch übereblaase!", "Sapperlott!", "Populär!", "ze zeffen singging sdeps!", "oh, jetzt, ja!", "Hammertime!",
    ]
    var go: String { Self.goShouts.randomElement() ?? "Los!" }
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
        if !(info.isUntracked && info.count == 1) { parts.append(setNumber(info.number, of: info.count)) }
        if let load = load(weight: info.weight, reps: info.reps) { parts.append(load) }
        return parts
    }

    func setNumber(_ number: Int, of count: Int) -> String {
        german ? "Satz \(spoken(number)) von \(spoken(count))." : "Set \(spoken(number)) of \(spoken(count))."
    }

    /// "Zehn Wiederholungen mit siebzehn Komma fünf Kilo." A whole statement: the list form
    /// "siebzehn Komma fünf Kilo, zehn Wiederholungen." made the voice go up at the end like a question.
    func load(weight: Double, reps: Int) -> String? {
        let kilos = german
            ? (weight == 1 ? "einem Kilo" : "\(spoken(weight)) Kilo")
            : (weight == 1 ? "one kilo" : "\(spoken(weight)) kilos")
        let repsText = german ? counted(reps, "Wiederholung", "Wiederholungen", one: "eine") : counted(reps, "rep", "reps", one: "one")
        switch (weight > 0, reps > 0) {
        case (true, true): return capitalized(german ? "\(repsText) mit \(kilos)." : "\(repsText) at \(kilos).")
        case (false, true): return capitalized(repsText + ".")
        case (true, false):
            let alone = german ? (weight == 1 ? "ein Kilo" : kilos) : kilos
            return capitalized(alone + ".")
        case (false, false): return nil
        }
    }

    private func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
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
        var result = [started, tenSeconds, skipped, next, complete] + Self.goShouts
        for entry in entries {
            let exercise = store.exercise(entry.exerciseID)
            result.append(sentence(exercise?.name ?? "Exercise"))
            if let note = exercise?.note, !note.isEmpty { result.append(sentence(note)) }
            for (index, set) in entry.sets.enumerated() {
                if !(set.weight == 0 && set.reps == 0 && entry.sets.count == 1) {
                    result.append(setNumber(index + 1, of: entry.sets.count))
                }
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
