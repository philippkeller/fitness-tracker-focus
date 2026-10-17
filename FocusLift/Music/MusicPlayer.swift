import AVFoundation
import Observation

/// Streams songs from the Subsonic server inside this app, so the app stays the
/// "Now Playing" app and keeps receiving the AirPods presses.
@Observable
final class MusicPlayer {
    var playlists: [SubsonicPlaylist] = []
    var queue: [SubsonicSong] = []
    var index = 0
    var isPlaying = false
    var errorMessage: String?

    var currentSong: SubsonicSong? { queue[safe: index] }

    @ObservationIgnored var onTrackChange: (() -> Void)?
    private let player = AVPlayer()
    @ObservationIgnored private var wantsToPlay = false
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var rateObserver: NSKeyValueObservation?

    init() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
            self.next()
        }
        rateObserver = player.observe(\.rate) { [weak self] player, _ in
            DispatchQueue.main.async { self?.isPlaying = player.rate > 0 }
        }
    }

    func loadPlaylists() async {
        guard let client = Prefs.subsonicClient else {
            await MainActor.run { self.errorMessage = "Set up your music server in Settings." }
            return
        }
        do {
            let lists = try await client.playlists()
            await MainActor.run {
                self.playlists = lists
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

    /// Plays a playlist, or a random mix when `playlistID` is nil.
    func play(playlistID: String?, shuffle: Bool) async {
        guard let client = Prefs.subsonicClient else { return }
        do {
            var songs: [SubsonicSong]
            if let playlistID {
                songs = try await client.songs(inPlaylist: playlistID)
            } else {
                songs = try await client.randomSongs(count: 100)
            }
            if shuffle { songs.shuffle() }
            await MainActor.run {
                self.queue = songs
                self.index = 0
                self.errorMessage = songs.isEmpty ? "No songs found." : nil
                self.playCurrent()
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

    func togglePause() {
        if isPlaying {
            wantsToPlay = false
            player.pause()
        } else if player.currentItem == nil {
            playCurrent()
        } else {
            wantsToPlay = true
            player.play()
        }
        onTrackChange?()
    }

    func next() {
        guard !queue.isEmpty else { return }
        index = (index + 1) % queue.count
        playCurrent()
    }

    func stop() {
        wantsToPlay = false
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    func setDucked(_ ducked: Bool) {
        player.volume = ducked ? 0.25 : 1.0
    }

    func resumeAfterInterruption() {
        if wantsToPlay { player.play() }
    }

    private func playCurrent() {
        guard let song = currentSong,
              let url = try? Prefs.subsonicClient?.streamURL(songID: song.id) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        wantsToPlay = true
        player.play()
        onTrackChange?()
    }
}
