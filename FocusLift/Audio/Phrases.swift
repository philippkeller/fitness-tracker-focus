import Foundation
import NaturalLanguage

/// A sentence and its pronunciation language travel together through caching and playback.
struct SpeechPart: Hashable {
    let text: String
    let language: String
    var voice: Voice = .workout

    enum Voice: Hashable {
        case workout
        case ramona
    }
}

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

    var started: SpeechPart { cue(german ? "Training gestartet." : "Workout started.") }
    /// Keep every variant available for pre-generation; choose only at playback time.
    static let startCues: [SpeechPart] = [
        "Chewbacca",
        "Lölihund",
        "Schnabeltasse",
        "Gigeligugeli",
        "Rinderspaziergang",
        "Über de Tisch übereblaase",
        "Sapperlott",
        "Populär!",
        "ze zeffen singging sdeps",
        "oh, jetzt, ja!",
        "Hammertime!",
    ].map { SpeechPart(text: $0, language: "de", voice: .ramona) }

    var go: SpeechPart { Self.startCues.randomElement()! }
    var tenSeconds: SpeechPart { cue(german ? "Noch 10 Sekunden." : "10 seconds.") }
    var skipped: SpeechPart { cue(german ? "Übung übersprungen." : "Exercise skipped.") }
    var next: SpeechPart { cue(german ? "Danach:" : "Next:") }
    var complete: SpeechPart {
        cue(german ? "Alle Sätze geschafft. Stark! Beende das Training in der App." : "All sets done. Nice work! Finish the workout in the app.")
    }

    func set(_ info: SetInfo, withName: Bool, withNote: Bool) -> [SpeechPart] {
        var parts: [SpeechPart] = []
        if withName { parts += exerciseName(info.exercise) }
        if withNote, !info.note.isEmpty { parts.append(cue(sentence(info.note))) }
        parts.append(setNumber(info.number, of: info.count))
        if let load = load(weight: info.weight, reps: info.reps) { parts.append(load) }
        return parts
    }

    func load(weight: Double, reps: Int) -> SpeechPart? {
        var load: [String] = []
        if weight > 0 { load.append(german ? (weight == 1 ? "ein Kilo" : "\(number(weight)) Kilo") : "\(number(weight)) kilos") }
        if reps > 0 { load.append(german ? (reps == 1 ? "eine Wiederholung" : "\(reps) Wiederholungen") : "\(reps) reps") }
        return load.isEmpty ? nil : cue(load.joined(separator: ", ") + ".")
    }

    func rest(_ seconds: Int) -> SpeechPart {
        cue(german ? "Pause, \(duration(seconds))." : "Rest, \(duration(seconds)).")
    }

    func remaining(_ seconds: Int) -> SpeechPart {
        cue(german ? "Noch \(duration(seconds)) Pause." : "\(duration(seconds)) of rest left.")
    }

    func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60, rest = seconds % 60
        if seconds < 60 || (rest != 0 && seconds < 180) {
            return german ? (seconds == 1 ? "eine Sekunde" : "\(seconds) Sekunden") : "\(seconds) seconds"
        }
        let minuteText = german
            ? (minutes == 1 ? "eine Minute" : "\(minutes) Minuten")
            : (minutes == 1 ? "1 minute" : "\(minutes) minutes")
        guard rest != 0 else { return minuteText }
        return minuteText + (german ? (rest == 1 ? " eine Sekunde" : " \(rest) Sekunden") : " \(rest) seconds")
    }

    /// Every sentence a workout with these exercises can say (except "time left", which depends on the moment).
    func allSentences(for entries: [ExerciseEntry], store: AppStore) -> [SpeechPart] {
        var result = [started, tenSeconds, skipped, next, complete] + Self.startCues
        for entry in entries {
            let exercise = store.exercise(entry.exerciseID)
            result += exerciseName(exercise?.name ?? "Exercise")
            if let note = exercise?.note, !note.isEmpty { result.append(cue(sentence(note))) }
            for (index, set) in entry.sets.enumerated() {
                result.append(setNumber(index + 1, of: entry.sets.count))
                if let load = load(weight: set.weight, reps: set.reps) { result.append(load) }
                if set.rest > 0 { result.append(rest(set.rest)) }
            }
        }
        var seen = Set<SpeechPart>()
        return result.filter { seen.insert($0).inserted }
    }

    private func cue(_ text: String) -> SpeechPart {
        let text = german ? text.replacingOccurrences(
            of: #"(?i)\b(?:kg|kilogram|kilograms|kilos)\b"#, with: "Kilo", options: .regularExpression) : text
        return SpeechPart(text: german ? Self.germanNumbers(in: text) : text, language: german ? "de" : "en")
    }

    private func setNumber(_ number: Int, of count: Int) -> SpeechPart {
        cue(german ? "Satz \(number) von \(count)." : "Set \(number) of \(count).")
    }

    private func exerciseName(_ text: String) -> [SpeechPart] {
        // Names from Strong are usually English. Restrict detection to our two languages
        // so short names such as “Pull Down” cannot select an unrelated voice.
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english]
        recognizer.processString(text)
        let language = recognizer.dominantLanguage == .german ? "de" : "en"
        let text = sentence(text)
        guard german else { return [SpeechPart(text: text, language: language)] }
        // Even a number inside an English exercise name is spoken in German.
        let expression = try! NSRegularExpression(pattern: #"[0-9]+(?:[.,][0-9]+)?"#)
        var parts: [SpeechPart] = []
        var start = text.startIndex
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            if start < range.lowerBound {
                parts.append(SpeechPart(text: String(text[start..<range.lowerBound]), language: language))
            }
            parts.append(cue(String(text[range])))
            start = range.upperBound
        }
        if start < text.endIndex {
            let tail = String(text[start...])
            if tail == ".", let last = parts.popLast() {
                parts.append(SpeechPart(text: last.text + tail, language: last.language))
            } else {
                parts.append(SpeechPart(text: tail, language: language))
            }
        }
        return parts
    }

    /// Spell digits before synthesis: the model must not guess a number or its language.
    /// Decimal digits are read individually, preserving e.g. 20,05 as “zwanzig Komma null fünf”.
    static func germanNumbers(in text: String) -> String {
        let expression = try! NSRegularExpression(pattern: #"[0-9]+(?:[.,][0-9]+)?"#)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .spellOut
        var result = text
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let components = result[range].split(whereSeparator: { $0 == "," || $0 == "." })
            guard let integer = Int64(components[0]),
                  var spoken = formatter.string(from: NSNumber(value: integer)) else { continue }
            if components.count == 2 {
                let digits = components[1].compactMap { $0.wholeNumberValue }
                    .compactMap { formatter.string(from: NSNumber(value: $0)) }
                spoken += " Komma " + digits.joined(separator: " ")
            }
            result.replaceSubrange(range, with: spoken)
        }
        return result
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
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
