import AVFoundation

final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    /// Used to lower the music while speaking.
    var onSpeakingChanged: ((Bool) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var voices: [String: AVSpeechSynthesisVoice] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ text: String, language: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Best installed voice for the language. Download "Enhanced"/"Premium" voices in
    /// iOS Settings → Accessibility → Spoken Content → Voices for a much nicer sound.
    private func voice(for language: String) -> AVSpeechSynthesisVoice? {
        if let cached = voices[language] { return cached }
        let preferred = language == "de" ? "de-DE" : "en-US"
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .max { a, b in
                (a.quality.rawValue, a.language == preferred ? 1 : 0) < (b.quality.rawValue, b.language == preferred ? 1 : 0)
            } ?? AVSpeechSynthesisVoice(language: preferred)
        voices[language] = best
        return best
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onSpeakingChanged?(true) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onSpeakingChanged?(false) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onSpeakingChanged?(false) }
    }
}
