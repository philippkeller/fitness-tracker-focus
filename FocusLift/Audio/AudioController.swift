import AVFoundation
import MediaPlayer

/// Keeps the app alive in the background and makes it the "Now Playing" app,
/// so AirPods presses arrive here as remote commands.
///
/// iOS only routes presses to the app that is actively playing non-mixable audio.
/// While no music plays we loop a silent track to keep that role.
final class AudioController {
    var onPrimary: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onInterruptionEnded: (() -> Void)?

    private var silence: AVAudioPlayer?
    private var isActive = false
    private var lastPrimary = Date.distantPast
    private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        }
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            // Small buffers, so the click follows a press as fast as possible.
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        if silence == nil { silence = Self.makeSilencePlayer() }
        silence?.play()
        AudioOutput.shared.start()
        installCommands()
        isActive = true
    }

    func stop() {
        isActive = false
        silence?.stop()
        removeCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Lock screen / Control Center display. With a duration, iOS animates a progress bar.
    func setNowPlaying(title: String, subtitle: String, album: String?, duration: TimeInterval? = nil, elapsed: TimeInterval? = nil) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        if let album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let duration, let elapsed {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsed)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: Remote commands (AirPods presses)

    private func installCommands() {
        guard !isActive else { return }
        let center = MPRemoteCommandCenter.shared()

        // A single press arrives as play, pause or toggle depending on what iOS thinks the state is.
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand] {
            command.isEnabled = true
            command.addTarget { [weak self] _ in
                self?.primaryPressed()
                return .success
            }
        }
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playClick()
            self?.onNext?()
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.playClick()
            self?.onPrevious?()
            return .success
        }
        let unused: [MPRemoteCommand] = [center.skipForwardCommand, center.skipBackwardCommand, center.seekForwardCommand,
                                         center.seekBackwardCommand, center.changePlaybackPositionCommand]
        for command in unused {
            command.isEnabled = false
        }
    }

    private func removeCommands() {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                        center.nextTrackCommand, center.previousTrackCommand] {
            command.removeTarget(nil)
        }
    }

    private func primaryPressed() {
        // Guard against iOS delivering one press as two commands.
        guard Date().timeIntervalSince(lastPrimary) > 0.6 else { return }
        lastPrimary = Date()
        playClick()
        onPrimary?()
    }

    /// Short tick the moment a press arrives, before the voice (which can take a moment to load).
    private func playClick() {
        AudioOutput.shared.playClick()
    }

    // MARK: Interruptions (calls, Siri, alarms)

    private func handleInterruption(_ note: Notification) {
        guard isActive,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        silence?.play()
        AudioOutput.shared.start()
        onInterruptionEnded?()
    }

    // MARK: Silent loop

    private static func makeSilencePlayer() -> AVAudioPlayer? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("silence.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? silentWAV(seconds: 2).write(to: url)
        }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.prepareToPlay()
        return player
    }

    /// 16-bit mono PCM WAV containing only zeros.
    private static func silentWAV(seconds: Int, sampleRate: Int = 22_050) -> Data {
        wav(samples: [Int16](repeating: 0, count: seconds * sampleRate), sampleRate: sampleRate)
    }

    private static func wav(samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = samples.count * 2
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF"); append32(UInt32(36 + dataSize)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 2)); append16(2); append16(16)
        append("data"); append32(UInt32(dataSize))
        for sample in samples { append16(UInt16(bitPattern: sample)) }
        return data
    }
}
