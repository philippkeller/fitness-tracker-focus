import AVFoundation
import AudioToolbox

/// One always-running audio engine for the ElevenLabs voice and the press click.
///
/// The voice goes through Apple's peak limiter with a pre-gain, so it can be much louder than
/// the generated files without clipping. The click node is already running, so a click starts
/// as soon as the press arrives instead of waiting for a player to spin up.
final class AudioOutput {
    static let shared = AudioOutput()

    static let boostKey = "voiceBoost"
    /// Extra voice loudness in dB (Settings → Voice).
    static var boost: Double {
        UserDefaults.standard.object(forKey: boostKey) as? Double ?? 10
    }

    private let engine = AVAudioEngine()
    private let voiceNode = AVAudioPlayerNode()
    private let clickNode = AVAudioPlayerNode()
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0))
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private lazy var clickBuffer = makeClick()
    /// Bumped on every new announcement, so callbacks from stopped audio are ignored.
    private var token = 0

    private init() {
        engine.attach(voiceNode)
        engine.attach(limiter)
        engine.attach(clickNode)
        engine.connect(voiceNode, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        engine.connect(clickNode, to: engine.mainMixerNode, format: format)
        // Route changes (AirPods connecting, a call) stop the engine.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.start()
        }
    }

    /// Call after the audio session is active.
    func start() {
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                print("Audio engine error: \(error)")
                return
            }
        }
        if !clickNode.isPlaying { clickNode.play() }
    }

    // MARK: Click

    func playClick() {
        start()
        guard engine.isRunning, let clickBuffer else { return }
        clickNode.scheduleBuffer(clickBuffer, at: nil, options: .interrupts)
        if !clickNode.isPlaying { clickNode.play() }
    }

    /// 50 ms tick: a 1.8 kHz tone that fades out quickly.
    private func makeClick() -> AVAudioPCMBuffer? {
        let count = AVAudioFrameCount(format.sampleRate * 0.05)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = count
        for index in 0..<Int(count) {
            let time = Double(index) / format.sampleRate
            let value = Float(sin(2 * Double.pi * 1800 * time) * exp(-time * 100) * 0.9)
            for channel in 0..<Int(format.channelCount) { channels[channel][index] = value }
        }
        return buffer
    }

    // MARK: Voice

    /// Plays the files one after another. Returns false if none could be played.
    /// `onFinish` runs on the main thread after the last one, unless playback was stopped.
    func playVoice(_ urls: [URL], onFinish: @escaping () -> Void) -> Bool {
        stopVoice()
        let buffers = urls.compactMap { url -> AVAudioPCMBuffer? in
            guard let buffer = buffer(from: url) else {
                // A broken file would otherwise fail forever; the next call generates it again.
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return buffer
        }
        start()
        guard !buffers.isEmpty, engine.isRunning else { return false }

        AudioUnitSetParameter(
            limiter.audioUnit, AudioUnitParameterID(kLimiterParam_PreGain), kAudioUnitScope_Global, 0,
            AudioUnitParameterValue(Self.boost), 0)

        let current = token
        for (index, buffer) in buffers.enumerated() {
            let isLast = index == buffers.count - 1
            voiceNode.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard isLast else { return }
                DispatchQueue.main.async {
                    guard let self, current == self.token else { return }
                    onFinish()
                }
            }
        }
        voiceNode.play()
        return true
    }

    func stopVoice() {
        token += 1
        voiceNode.stop()
    }

    /// Decodes an MP3 into the engine's format.
    private func buffer(from url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        do {
            try file.read(into: source)
        } catch {
            return nil
        }
        if source.format == format { return source }

        guard let converter = AVAudioConverter(from: source.format, to: format) else { return nil }
        let ratio = format.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return source
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}
