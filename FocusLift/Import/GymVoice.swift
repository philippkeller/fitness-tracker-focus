import AVFoundation
import Foundation

/// Voice input for a new gym: say which machines it has, get a routine built from your exercises.
/// Audio → OpenAI transcription → a small model matches the machines against the exercise list.
/// Nothing is changed here; GymVoiceSheet shows the suggestions and creates the routine.
enum GymVoice {
    static let transcribeModel = "gpt-4o-transcribe"
    static let parseModel = "gpt-5.4-mini"

    struct Suggestion: Identifiable {
        let id = UUID()
        var name: String
        /// Same exercise as one you already have: reuse it (history and last weights carry over).
        var existingID: UUID?
        /// New exercise: copy number of sets and reps from this one, weights start at 0.
        var similarID: UUID?
        var isIncluded = true
    }

    struct Result {
        var transcript: String
        var routineName: String?
        var suggestions: [Suggestion]
    }

    static func suggestions(forAudio audio: Data, exercises: [Exercise]) async throws -> Result {
        let transcript = try await transcribe(audio, exercises: exercises)
        guard !transcript.isEmpty else { return Result(transcript: "", suggestions: []) }
        let parsed = try await parse(transcript, exercises: exercises)

        var seen = Set<String>()
        let suggestions: [Suggestion] = parsed.exercises.compactMap { item in
            let existing = item.match.flatMap { exercises.indices.contains($0) ? exercises[$0] : nil }
            let similar = item.similar.flatMap { exercises.indices.contains($0) ? exercises[$0] : nil }
            let name = existing?.name ?? item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return nil }
            return Suggestion(name: name, existingID: existing?.id, similarID: existing == nil ? similar?.id : nil)
        }
        let routineName = parsed.routineName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(
            transcript: transcript,
            routineName: routineName?.isEmpty == false ? routineName : nil,
            suggestions: suggestions)
    }

    // MARK: OpenAI

    private static func transcribe(_ audio: Data, exercises: [Exercise]) async throws -> String {
        let boundary = "FocusLift-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", transcribeModel)
        field("language", Prefs.language)
        // Exercise names help with spelling of machine names.
        let names = exercises.map(\.name).joined(separator: ", ")
        field("prompt", String("Geräte im Fitnessstudio, z.B.: \(names)".prefix(1500)))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.m4a\"\r\nContent-Type: audio/m4a\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = try makeRequest("audio/transcriptions")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        struct Response: Decodable { let text: String }
        let response: Response = try await send(request)
        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Parsed: Decodable {
        struct Item: Decodable {
            let match: Int?
            let similar: Int?
            let name: String
        }
        let routineName: String?
        let exercises: [Item]
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["routineName", "exercises"],
        "properties": [
            "routineName": [
                "type": ["string", "null"],
                "description": "Name of the gym if it was mentioned, else null",
            ] as [String: Any],
            "exercises": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["match", "similar", "name"],
                    "properties": [
                        "match": [
                            "type": ["integer", "null"],
                            "description": "Number of the existing exercise (E…) if it is the same exercise, else null",
                        ] as [String: Any],
                        "similar": [
                            "type": ["integer", "null"],
                            "description": "For new exercises: number of the most similar existing exercise (E…) to copy sets and reps from, else null",
                        ] as [String: Any],
                        "name": [
                            "type": "string",
                            "description": "Existing exercises: their name. New exercises: English name in the same style as the list, e.g. \"Leg Press (Machine)\"",
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ] as [String: Any],
    ]

    private static func parse(_ transcript: String, exercises: [Exercise]) async throws -> Parsed {
        let lines = exercises.enumerated().map { "E\($0.offset): \($0.element.name)" }
        let system = """
            Der Benutzer ist in einem neuen Fitnessstudio und sagt, welche Geräte es dort gibt. \
            Du bekommst die automatische Transkription (kann Fehler enthalten) und baust daraus eine Trainingsroutine.

            Übungen, die der Benutzer schon hat:
            \(lines.joined(separator: "\n"))

            Regeln:
            - Gib jedes genannte Gerät bzw. jede genannte Übung genau einmal zurück, in der genannten Reihenfolge.
            - Ist es dieselbe Übung wie eine bestehende (auch wenn anders gesagt, z.B. "Beinpresse" = "Leg Press (Machine)", "Latzug" = "Lat Pulldown (Cable)"), setze match auf deren Nummer (ohne "E") und similar auf null.
            - Sonst ist sie neu: match = null, name = englischer Übungsname im Stil der Liste, similar = Nummer der ähnlichsten bestehenden Übung (gleiche Muskelgruppe/Bewegung), oder null wenn keine passt.
            - Nennt der Benutzer nur eine Muskelgruppe oder ein Gerät ohne Übung (z.B. "Kabelzug"), wähle die naheliegende Übung, die er schon macht.
            - Füllwörter ignorieren. Wenn keine Geräte genannt wurden: leere Liste.
            """
        let payload: [String: Any] = [
            "model": parseModel,
            "reasoning_effort": "low",
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "gym", "strict": true, "schema": schema] as [String: Any],
            ] as [String: Any],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": transcript],
            ],
        ]
        var request = try makeRequest("chat/completions")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        let response: Response = try await send(request)
        guard let content = response.choices.first?.message.content else { throw VoiceError.api("OpenAI: empty answer") }
        return try JSONDecoder().decode(Parsed.self, from: Data(content.utf8))
    }

    private static func makeRequest(_ path: String) throws -> URLRequest {
        guard let key = Keychain.openAIKey, !key.isEmpty else {
            throw VoiceError.api("No OpenAI API key set (Settings → Voice input).")
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/\(path)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var message = String(decoding: data.prefix(300), as: UTF8.self)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let text = error["message"] as? String {
                message = text
            }
            throw VoiceError.api("OpenAI \(status): \(message)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Records a short voice memo as a small AAC (m4a) file for upload.
@MainActor
final class VoiceRecorder {
    enum RecorderError: LocalizedError {
        case noPermission

        var errorDescription: String? {
            "No access to the microphone. Allow it in iOS Settings → FocusLift."
        }
    }

    private var recorder: AVAudioRecorder?
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice.m4a")

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.noPermission }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.record(forDuration: 120)
        self.recorder = recorder
    }

    /// Stops and returns the recorded audio.
    func stop() -> Data? {
        let wasRecording = recorder != nil
        recorder?.stop()
        recorder = nil
        if wasRecording {
            // Back to playback, which the workout voice and music expect.
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(.playback, mode: .default)
        }
        return try? Data(contentsOf: url)
    }

    func cancel() {
        _ = stop()
        try? FileManager.default.removeItem(at: url)
    }
}
