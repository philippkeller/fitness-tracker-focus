import SwiftUI
import UIKit

/// Settings → Voice: language, ElevenLabs key and voice, pre-generating audio, test.
struct VoiceSettingsSection: View {
    @Environment(AppStore.self) private var store
    @Environment(WorkoutEngine.self) private var engine

    @AppStorage(Prefs.languageKey) private var language = "de"
    @AppStorage(VoiceConfig.enabledKey) private var useElevenLabs = true
    @AppStorage(AudioOutput.boostKey) private var boost = 10.0
    @State private var apiKey = ""
    @State private var config = VoiceConfig.current
    @State private var status: String?
    @State private var busy = false
    @State private var pending: [String] = []
    @State private var cache = (files: 0, bytes: 0)

    var body: some View {
        Section {
            Picker("Language", selection: $language) {
                Text("Deutsch").tag("de")
                Text("English").tag("en")
            }
            Toggle("ElevenLabs voice", isOn: $useElevenLabs)
            if useElevenLabs {
                SecureField("API key (sk_…)", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                LabeledContent("Voice ID") {
                    TextField("Voice ID", text: $config.voiceId)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Picker("Model", selection: $config.modelId) {
                    ForEach(VoiceConfig.models, id: \.self) { Text($0).tag($0) }
                }
                VStack(alignment: .leading) {
                    LabeledContent("Stability", value: String(format: "%.2f", config.stability))
                    Slider(value: $config.stability, in: 0...1, step: config.modelId == "eleven_v3" ? 0.5 : 0.05)
                }
                VStack(alignment: .leading) {
                    LabeledContent("Louder", value: "+\(Int(boost)) dB")
                    Slider(value: $boost, in: 0...20, step: 1)
                }
                Button("Paste settings from Voice Lab") { paste() }
                Button(pending.isEmpty ? "Routines ready ✓" : "Prepare voice for routines (~\(credits) credits)") {
                    prepare()
                }
                .disabled(busy || pending.isEmpty || apiKey.isEmpty)
                LabeledContent(
                    "Saved audio",
                    value: "\(cache.files) sentences, \(ByteCountFormatter.string(fromByteCount: Int64(cache.bytes), countStyle: .file))")
                Button("Delete saved audio", role: .destructive) {
                    Task {
                        await VoiceCache.shared.clear()
                        refresh()
                    }
                }
                .disabled(cache.files == 0)
            }
            Button("Test voice") { test() }
                .disabled(busy)
            if let status {
                Text(status).font(.caption)
            }
        } header: {
            Text("Voice")
        } footer: {
            Text(useElevenLabs
                ? "Each sentence is generated once and saved on the phone, so repeated announcements cost no credits and work without signal. Prepare the voice on Wi-Fi after changing a routine. When a sentence can't be generated, the iPhone voice reads the announcement."
                : "Uses the iPhone voice. For a nicer one, download an “Enhanced” or “Premium” voice in iOS Settings → Accessibility → Spoken Content → Voices.")
        }
        .onAppear {
            apiKey = Keychain.elevenLabsKey ?? ""
            config = VoiceConfig.current
            refresh()
        }
        .onChange(of: apiKey) { _, value in
            Keychain.elevenLabsKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .onChange(of: config) { _, value in
            VoiceConfig.current = value
            refresh()
        }
        .onChange(of: language) { _, _ in refresh() }
    }

    private var credits: Int {
        pending.reduce(0) { $0 + $1.count }
    }

    /// Sentences of all routines that have no saved audio yet.
    private func refresh() {
        let phrases = Phrases(language: language)
        var seen = Set<String>()
        let all = store.routines
            .flatMap { phrases.allSentences(for: $0.entries, store: store) }
            .filter { seen.insert($0).inserted }
        let config = config
        pending = all.filter { !VoiceCache.shared.isCached($0, config: config) }
        let summary = VoiceCache.shared.summary()
        cache = (summary.files, summary.bytes)
    }

    private func paste() {
        guard let text = UIPasteboard.general.string, let pasted = VoiceConfig.parse(text) else {
            status = "The clipboard has no Voice Lab settings. Tap “Copy” in the Voice Lab first."
            return
        }
        config = pasted
        status = "Using \(pasted.voiceName ?? pasted.voiceId) with \(pasted.modelId)."
    }

    private func prepare() {
        busy = true
        status = "Generating \(pending.count) sentences…"
        let sentences = pending
        Task {
            let result = await WorkoutEngine.prepareVoice(sentences)
            if let error = result.error {
                status = "Generated \(result.generated), then failed: \(error)"
            } else {
                status = "Generated \(result.generated) sentences ✓"
            }
            busy = false
            refresh()
        }
    }

    private func test() {
        busy = true
        status = nil
        Task {
            let reason = await engine.testVoice()
            status = reason.map { "iPhone voice used: \($0)" } ?? "ElevenLabs voice ✓"
            busy = false
            refresh()
        }
    }
}
