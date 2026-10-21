import AVFoundation
import Observation

/// An artist marked with a heart, for shuffling just their songs.
struct FavoriteArtist: Codable, Hashable, Identifiable {
    let id: String
    let name: String
}

/// Streams songs from the Subsonic server inside this app, so the app stays the
/// "Now Playing" app and keeps receiving the AirPods presses.
///
/// The queue, the song and the position are saved on the phone, so the next workout
/// continues where the music stopped.
@Observable
final class MusicPlayer {
    var playlists: [SubsonicPlaylist] = []
    var artists: [SubsonicArtist] = []
    var queue: [SubsonicSong] = []
    var index = 0
    var isPlaying = false
    var errorMessage: String?
    private(set) var favoriteArtists: [FavoriteArtist] = []

    var currentSong: SubsonicSong? { queue[safe: index] }

    @ObservationIgnored var onTrackChange: (() -> Void)?
    private let player = AVPlayer()
    @ObservationIgnored private var wantsToPlay = false
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var rateObserver: NSKeyValueObservation?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    /// Where to continue the current song when it's next loaded (seconds).
    @ObservationIgnored private var resumeAt: Double = 0

    private static let queueKey = "musicQueue"
    private static let positionKey = "musicPosition"
    private static let favoritesKey = "favoriteArtists"

    private struct SavedQueue: Codable {
        var songs: [SubsonicSong]
        var index: Int
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.queueKey),
           let saved = try? JSONDecoder().decode(SavedQueue.self, from: data),
           saved.songs.indices.contains(saved.index) {
            queue = saved.songs
            index = saved.index
            resumeAt = defaults.double(forKey: Self.positionKey)
        }
        if let data = defaults.data(forKey: Self.favoritesKey),
           let favorites = try? JSONDecoder().decode([FavoriteArtist].self, from: data) {
            favoriteArtists = favorites
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main
        ) { [weak self] time in
            guard let self, self.player.currentItem != nil, time.seconds.isFinite else { return }
            UserDefaults.standard.set(time.seconds, forKey: Self.positionKey)
        }

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

    func loadArtists() async {
        guard let client = Prefs.subsonicClient else {
            await MainActor.run { self.errorMessage = "Set up your music server in Settings." }
            return
        }
        do {
            let list = try await client.artists()
            await MainActor.run {
                self.artists = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

    /// Plays `songs` starting at `start`, then continues with the following ones.
    func play(songs: [SubsonicSong], startAt start: Int) {
        guard songs.indices.contains(start) else { return }
        queue = songs
        index = start
        resumeAt = 0
        errorMessage = nil
        playCurrent()
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
                self.resumeAt = 0
                self.errorMessage = songs.isEmpty ? "No songs found." : nil
                self.playCurrent()
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

    /// Shuffles all songs of one artist.
    func shuffle(artistID: String) async {
        guard let client = Prefs.subsonicClient else {
            await MainActor.run { self.errorMessage = "Set up your music server in Settings." }
            return
        }
        do {
            let songs = try await client.songs(byArtist: artistID).shuffled()
            await MainActor.run {
                self.queue = songs
                self.index = 0
                self.resumeAt = 0
                self.errorMessage = songs.isEmpty ? "No songs found." : nil
                self.playCurrent()
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

    /// Continues the saved song at the saved position, if nothing is playing yet.
    func resumeIfIdle() {
        guard player.currentItem == nil, !queue.isEmpty else { return }
        playCurrent()
    }

    // MARK: Favorite artists

    func isFavorite(_ artistID: String) -> Bool {
        favoriteArtists.contains { $0.id == artistID }
    }

    func toggleFavorite(id: String, name: String) {
        if isFavorite(id) {
            favoriteArtists.removeAll { $0.id == id }
        } else {
            favoriteArtists.append(FavoriteArtist(id: id, name: name))
            favoriteArtists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        if let data = try? JSONEncoder().encode(favoriteArtists) {
            UserDefaults.standard.set(data, forKey: Self.favoritesKey)
        }
    }

    // MARK: Playback

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
        resumeAt = 0
        playCurrent()
    }

    func stop() {
        wantsToPlay = false
        player.pause()
        if player.currentItem != nil {
            // Continue here next time.
            let seconds = player.currentTime().seconds
            resumeAt = seconds.isFinite ? seconds : 0
            UserDefaults.standard.set(resumeAt, forKey: Self.positionKey)
        }
        statusObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    func setDucked(_ ducked: Bool) {
        player.volume = ducked ? 0.15 : 1.0
    }

    func resumeAfterInterruption() {
        if wantsToPlay { player.play() }
    }

    private func playCurrent() {
        guard let song = currentSong,
              let url = try? Prefs.subsonicClient?.streamURL(songID: song.id) else { return }
        let item = AVPlayerItem(url: url)
        let start = resumeAt
        resumeAt = 0
        statusObserver = nil
        player.replaceCurrentItem(with: item)
        wantsToPlay = true
        saveQueue(position: start)

        if start > 1 {
            // Seek once the stream is ready, then play, so the song doesn't start from the top first.
            statusObserver = item.observe(\.status) { [weak self] item, _ in
                guard item.status != .unknown else { return }
                DispatchQueue.main.async {
                    guard let self, self.player.currentItem === item else { return }
                    self.statusObserver = nil
                    self.player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) { _ in
                        DispatchQueue.main.async {
                            if self.wantsToPlay && self.player.currentItem === item { self.player.play() }
                        }
                    }
                }
            }
        } else {
            player.play()
        }
        onTrackChange?()
    }

    private func saveQueue(position: Double) {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(SavedQueue(songs: queue, index: index)) {
            defaults.set(data, forKey: Self.queueKey)
        }
        defaults.set(position, forKey: Self.positionKey)
    }
}
