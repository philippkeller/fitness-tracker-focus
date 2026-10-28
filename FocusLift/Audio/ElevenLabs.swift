import CryptoKit
import Foundation
import Security

/// ElevenLabs voice settings. The JSON matches what tools/voice-lab.html shows under "Settings for FocusLift".
struct VoiceConfig: Codable, Equatable {
    var voiceId = "yUy9CCX9brt8aPVvIWy3"
    var voiceName: String? = "Ramona"
    var modelId = "eleven_v3"
    var stability = 0.5
    var similarityBoost: Double?
    var style: Double?
    var speed: Double?
    var useSpeakerBoost: Bool?
    var languageCode: String?

    static let models = ["eleven_v3", "eleven_multilingual_v2", "eleven_flash_v2_5", "eleven_turbo_v2_5"]

    /// Voices for the picker in Settings. Ramona is a library voice (paid plan only);
    /// the others are ElevenLabs' premade voices, which work on every plan and speak German with the multilingual models.
    static let presets: [VoicePreset] = [
        VoicePreset(id: "yUy9CCX9brt8aPVvIWy3", name: "Ramona", note: "German, calm · paid plan"),
        VoicePreset(id: "cgSgspJ2msm6clMCkdW9", name: "Jessica", note: "bright, upbeat"),
        VoicePreset(id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", note: "soft, confident"),
        VoicePreset(id: "FGY2WhTYpPnrIDTdsKH5", name: "Laura", note: "energetic"),
        VoicePreset(id: "Xb7hH8MSUJpSbSDYk0k2", name: "Alice", note: "clear, British"),
        VoicePreset(id: "XrExE9yKIg1WjnnlVkGX", name: "Matilda", note: "warm"),
        VoicePreset(id: "pFZP5JQG7iQjIQuC4Bku", name: "Lily", note: "calm, British"),
        VoicePreset(id: "nPczCjzI2devNBz1zQrb", name: "Brian", note: "deep, calm"),
        VoicePreset(id: "JBFqnCBsd6RJkjVDZRzb", name: "George", note: "warm, British"),
        VoicePreset(id: "onwK4e9ZLuTAKqWW03F9", name: "Daniel", note: "steady, British"),
        VoicePreset(id: "CwhRBWXzGAHq8TQ4Fs17", name: "Roger", note: "relaxed"),
        VoicePreset(id: "iP95p4xoKVk53GoZ742B", name: "Chris", note: "casual"),
        VoicePreset(id: "cjVigY5qzO86Huf0OWal", name: "Eric", note: "smooth"),
        VoicePreset(id: "bIHbv24MWmeRgasZH58o", name: "Will", note: "friendly"),
    ]

    private static let key = "elevenLabsConfig"
    static let enabledKey = "elevenLabsEnabled"

    static var current: VoiceConfig {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let config = try? JSONDecoder().decode(VoiceConfig.self, from: data) else { return VoiceConfig() }
            return config
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }

    /// The ElevenLabs voice is used when switched on and an API key is stored.
    static var isActive: Bool {
        (UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true) && !(Keychain.elevenLabsKey ?? "").isEmpty
    }

    /// Accepts the JSON copied from the voice lab.
    static func parse(_ text: String) -> VoiceConfig? {
        guard let data = text.data(using: .utf8),
              let config = try? JSONDecoder().decode(VoiceConfig.self, from: data),
              !config.voiceId.isEmpty else { return nil }
        return config
    }

    /// Part of the cache file name: changing any setting means new audio.
    var cacheKey: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var copy = self
        copy.voiceName = nil
        return (try? encoder.encode(copy)).map { String(decoding: $0, as: UTF8.self) } ?? voiceId
    }
}

struct VoicePreset: Identifiable {
    let id: String
    let name: String
    let note: String
}

enum Keychain {
    private static let service = "com.philippkeller.focuslift"

    static var elevenLabsKey: String? {
        get { read("elevenLabsAPIKey") }
        set { write(newValue, for: "elevenLabsAPIKey") }
    }

    /// For voice input (Whisper transcription + matching), see GymVoice.
    static var openAIKey: String? {
        get { read("openAIAPIKey") }
        set { write(newValue, for: "openAIAPIKey") }
    }

    private static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String?, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        // Readable while the phone is locked in the pocket.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}

enum VoiceError: LocalizedError {
    case noKey
    case api(String)

    var errorDescription: String? {
        switch self {
        case .noKey: "No ElevenLabs API key set."
        case .api(let message): message
        }
    }
}

/// Generated sentences stored as MP3 files, so each sentence costs credits only once.
actor VoiceCache {
    static let shared = VoiceCache()

    private let directory: URL
    private var inFlight: [String: Task<URL, Error>] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var directory = support.appendingPathComponent("Voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        self.directory = directory
    }

    nonisolated func fileURL(for text: String, config: VoiceConfig) -> URL {
        let hash = SHA256.hash(data: Data((config.cacheKey + "|" + text).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent(hash + ".mp3")
    }

    nonisolated func isCached(_ text: String, config: VoiceConfig) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: text, config: config).path)
    }

    /// Cached file, or generates it now.
    func audio(for text: String, config: VoiceConfig) async throws -> URL {
        let url = fileURL(for: text, config: config)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        if let running = inFlight[url.lastPathComponent] { return try await running.value }

        let task = Task { try await Self.generate(text, config: config, to: url) }
        inFlight[url.lastPathComponent] = task
        defer { inFlight[url.lastPathComponent] = nil }
        return try await task.value
    }

    func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    nonisolated func summary() -> (files: Int, bytes: Int) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return (files.count, bytes)
    }

    private static func generate(_ text: String, config: VoiceConfig, to url: URL) async throws -> URL {
        guard let key = Keychain.elevenLabsKey, !key.isEmpty else { throw VoiceError.noKey }
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/")!
        components.path += config.voiceId
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]

        var settings: [String: Any] = ["stability": config.stability]
        if config.modelId != "eleven_v3" {
            if let value = config.similarityBoost { settings["similarity_boost"] = value }
            if let value = config.style { settings["style"] = value }
            if let value = config.speed { settings["speed"] = value }
            if let value = config.useSpeakerBoost { settings["use_speaker_boost"] = value }
        }
        var body: [String: Any] = ["text": text, "model_id": config.modelId, "voice_settings": settings]
        if let language = config.languageCode { body["language_code"] = language }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VoiceError.api(Self.message(from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0))
        }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    private static func message(from data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? [String: Any],
           let message = detail["message"] as? String {
            return "ElevenLabs \(status): \(message)"
        }
        return "ElevenLabs \(status): " + String(decoding: data.prefix(200), as: UTF8.self)
    }
}
