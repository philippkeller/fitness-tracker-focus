import Foundation

// Minimal app dependencies for running the production speech code without SwiftUI.
enum Prefs { static let language = "de" }
final class AppStore {
    var exercises: [Exercise] = []
    func exercise(_ id: UUID) -> Exercise? { exercises.first { $0.id == id } }
}

@main
struct VoiceRegression {
    static func main() {
        let de = Phrases(language: "de")
        func expect(_ actual: String?, _ expected: String) {
            precondition(actual == expected, "Expected \(expected), got \(actual ?? "nil")")
        }
        expect(de.load(weight: 24, reps: 26)?.text, "vierundzwanzig Kilo, sechsundzwanzig Wiederholungen.")
        expect(de.load(weight: 17.5, reps: 10)?.text, "siebzehn Komma fünf Kilo, zehn Wiederholungen.")
        expect(de.load(weight: 20.05, reps: 1)?.text, "zwanzig Komma null fünf Kilo, eine Wiederholung.")
        expect(de.load(weight: 1024, reps: 12)?.text, "eintausendvierundzwanzig Kilo, zwölf Wiederholungen.")
        expect(de.load(weight: 0, reps: 26)?.text, "sechsundzwanzig Wiederholungen.")
        precondition(de.load(weight: 0, reps: 0) == nil)
        expect(de.load(weight: 1, reps: 1)?.text, "ein Kilo, eine Wiederholung.")
        expect(de.rest(1).text, "Pause, eine Sekunde.")
        expect(de.tenSeconds.text, "Noch zehn Sekunden.")
        expect(de.rest(60).text, "Pause, eine Minute.")
        expect(de.rest(90).text, "Pause, neunzig Sekunden.")
        expect(de.remaining(185).text, "Noch drei Minuten fünf Sekunden Pause.")
        expect(Phrases.germanNumbers(in: "Sitz 6, 24 kg. 26."), "Sitz sechs, vierundzwanzig kg. sechsundzwanzig.")

        let store = AppStore()
        for name in ["Push Up", "Pull Down", "Bulgarian Split Squat", "Kniebeugen"] {
            let exercise = Exercise(name: name, note: "Sitz 6, 24 kg")
            store.exercises = [exercise]
            let entry = ExerciseEntry(exerciseID: exercise.id, sets: [WorkSet(weight: 24, reps: 26)])
            let live = de.set(SetInfo(exercise: name, note: exercise.note, number: 1, count: 1, weight: 24, reps: 26), withName: true, withNote: true)
            precondition(live[0].language == (name == "Kniebeugen" ? "de" : "en"))
            precondition(live.dropFirst().allSatisfy { $0.language == "de" })
            expect(live[1].text, "Sitz sechs, vierundzwanzig Kilo.")
            expect(live[2].text, "Satz eins von eins.")
            let prepared = de.allSentences(for: [entry], store: store)
            precondition(live.allSatisfy { prepared.contains($0) }, "Prepared and live speech must match")
        }
        let numbered = de.set(SetInfo(exercise: "24 Push Ups", note: "", number: 1, count: 3, weight: 0, reps: 26), withName: true, withNote: false)
        precondition(numbered[0] == SpeechPart(text: "vierundzwanzig", language: "de"))
        precondition(numbered[1].language == "en")

        let en = Phrases(language: "en")
        expect(en.load(weight: 24, reps: 26)?.text, "24 kilos, 26 reps.")
        precondition(en.tenSeconds.language == "en")
        var config = VoiceConfig()
        config.languageCode = "en" // Legacy imported override cannot change German cues.
        let part = de.load(weight: 24, reps: 26)!
        for model in VoiceConfig.models {
            config.modelId = model
            let body = config.requestBody(for: part)
            expect(body["text"] as? String, part.text)
            if model == "eleven_multilingual_v2" {
                precondition(body["language_code"] == nil)
            } else {
                expect(body["language_code"] as? String, "de")
                expect(config.requestBody(for: SpeechPart(text: "Push Up.", language: "en"))["language_code"] as? String, "en")
            }
        }
        let cache = VoiceCache.shared
        precondition(cache.fileURL(for: part, config: config) != cache.fileURL(for: SpeechPart(text: part.text, language: "en"), config: config))
        let expectedCues = [
            "Chewbacca", "Lölihund", "Schnabeltasse", "Gigeligugeli", "Rinderspaziergang",
            "Über de Tisch übereblaase", "Sapperlott", "Populär!", "ze zeffen singging sdeps",
            "oh, jetzt, ja!", "Hammertime!",
        ]
        precondition(Phrases.startCues.map(\.text) == expectedCues)
        let prepared = de.allSentences(for: [], store: store)
        precondition(Set(Phrases.startCues).count == 11)
        precondition(Phrases.startCues.allSatisfy { prepared.contains($0) })
        precondition(!prepared.contains { $0.text == "Los!" })
        for _ in 0..<100 {
            precondition(Phrases.startCues.contains(de.go))
            precondition(Phrases.startCues.contains(en.go))
        }
        for cue in Phrases.startCues {
            precondition(cue.voice == .ramona && cue.language == "de")
            let resolved = config.resolved(for: cue)
            expect(resolved.voiceId, "yUy9CCX9brt8aPVvIWy3")
            precondition(resolved.modelId == "eleven_v3" && resolved.stability == 1)
            expect(resolved.requestBody(for: cue)["text"] as? String, cue.text)
            var differentWorkoutVoice = config
            differentWorkoutVoice.voiceId = "another-voice"
            precondition(cache.fileURL(for: cue, config: config) == cache.fileURL(for: cue, config: differentWorkoutVoice))
            let ordinary = SpeechPart(text: cue.text, language: cue.language)
            precondition(cache.fileURL(for: cue, config: config) != cache.fileURL(for: ordinary, config: config))
        }
        precondition(config.resolved(for: de.tenSeconds) == config)
        print("Voice regression checks passed")
    }
}
