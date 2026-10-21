import AVFoundation

/// Speaks announcements with the ElevenLabs voice (cached per sentence), or with the
/// built-in iOS voice when ElevenLabs is off or a sentence can't be generated (no signal, no credits).
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    /// Used to lower the music while speaking.
    var onSpeakingChanged: ((Bool) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var voices: [String: AVSpeechSynthesisVoice] = [:]
    /// ElevenLabs audio is playing (through AudioOutput, which makes it louder).
    private var playing = false
    /// Bumped on every new announcement, so a slow download can't talk over a newer one.
    private var generation = 0

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ parts: [String], language: String) {
        Task { await say(parts, language: language) }
    }

    /// Speaks and returns why the ElevenLabs voice wasn't used, or nil if it was.
    @discardableResult
    func say(_ parts: [String], language: String) async -> String? {
        let parts = parts.filter { !$0.isEmpty }
        let current = await MainActor.run { () -> Int in
            stop()
            generation += 1
            return generation
        }
        guard !parts.isEmpty else { return nil }

        var fallbackReason: String? = "ElevenLabs voice is off."
        if VoiceConfig.isActive {
            let config = VoiceConfig.current
            do {
                var files: [URL] = []
                for part in parts {
                    files.append(try await VoiceCache.shared.audio(for: part, config: config))
                }
                let ready = files
                let played = await MainActor.run { () -> Bool in
                    guard current == generation else { return true }
                    return playFiles(ready)
                }
                if played { return nil }
                fallbackReason = "Could not play the generated audio."
            } catch {
                fallbackReason = error.localizedDescription
            }
        }
        await MainActor.run {
            guard current == generation else { return }
            speakWithSystemVoice(parts.joined(separator: " "), language: language)
        }
        return fallbackReason
    }

    /// Always the iPhone voice, e.g. for the time, which changes too often to cache.
    func speakWithIPhoneVoice(_ text: String, language: String) {
        stop()
        generation += 1
        speakWithSystemVoice(text, language: language)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        if playing {
            AudioOutput.shared.stopVoice()
            playing = false
            onSpeakingChanged?(false)
        }
    }

    // MARK: ElevenLabs audio

    private func playFiles(_ files: [URL]) -> Bool {
        let started = AudioOutput.shared.playVoice(files) { [weak self] in
            self?.playing = false
            self?.onSpeakingChanged?(false)
        }
        guard started else { return false }
        playing = true
        onSpeakingChanged?(true)
        return true
    }

    // MARK: iOS voice

    private func speakWithSystemVoice(_ text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    /// Best installed voice for the language.
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
