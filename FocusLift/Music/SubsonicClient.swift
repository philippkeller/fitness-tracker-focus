import CryptoKit
import Foundation

struct SubsonicSong: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    /// Seconds.
    let duration: Int?

    private enum CodingKeys: String, CodingKey { case id, title, artist, album, duration }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleID(forKey: .id)
        title = (try? container.decode(String.self, forKey: .title)) ?? "Unknown"
        artist = try? container.decode(String.self, forKey: .artist)
        album = try? container.decode(String.self, forKey: .album)
        duration = try? container.decode(Int.self, forKey: .duration)
    }

    /// For saving the queue on the phone.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

struct SubsonicArtist: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let albumCount: Int?

    private enum CodingKeys: String, CodingKey { case id, name, albumCount }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleID(forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? "Unknown"
        albumCount = try? container.decode(Int.self, forKey: .albumCount)
    }
}

struct SubsonicPlaylist: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let songCount: Int?

    private enum CodingKeys: String, CodingKey { case id, name, songCount }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleID(forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? "Playlist"
        songCount = try? container.decode(Int.self, forKey: .songCount)
    }
}

enum SubsonicError: LocalizedError {
    case badURL
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badURL: "The server URL is invalid."
        case .server(let message): message
        }
    }
}

/// Minimal Subsonic API client (works with Navidrome, the server behind Amperfy).
struct SubsonicClient {
    let server: String
    let user: String
    let password: String

    func ping() async throws {
        let _: Status = try await fetch("ping")
    }

    func playlists() async throws -> [SubsonicPlaylist] {
        let body: PlaylistsBody = try await fetch("getPlaylists")
        return body.playlists?.playlist ?? []
    }

    func songs(inPlaylist id: String) async throws -> [SubsonicSong] {
        let body: PlaylistBody = try await fetch("getPlaylist", ["id": id])
        return body.playlist.entry ?? []
    }

    func artists() async throws -> [SubsonicArtist] {
        let body: ArtistsBody = try await fetch("getArtists")
        return (body.artists?.index ?? []).flatMap { $0.artist ?? [] }
    }

    /// All songs of an artist, album by album.
    func songs(byArtist id: String) async throws -> [SubsonicSong] {
        let body: ArtistBody = try await fetch("getArtist", ["id": id])
        var songs: [SubsonicSong] = []
        for album in body.artist.album ?? [] {
            let albumBody: AlbumBody = try await fetch("getAlbum", ["id": album.id])
            songs += albumBody.album.song ?? []
        }
        return songs
    }

    func randomSongs(count: Int) async throws -> [SubsonicSong] {
        let body: RandomBody = try await fetch("getRandomSongs", ["size": "\(count)"])
        return body.randomSongs?.song ?? []
    }

    func streamURL(songID: String) throws -> URL {
        try url("stream", ["id": songID])
    }

    // MARK: Plumbing

    private func url(_ endpoint: String, _ params: [String: String] = [:]) throws -> URL {
        var base = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.lowercased().hasPrefix("http") { base = "https://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + "/rest/" + endpoint + ".view") else {
            throw SubsonicError.badURL
        }
        // Token auth: md5(password + salt), so the password itself is never sent.
        let salt = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
        let token = Insecure.MD5.hash(data: Data((password + salt).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        var items = [
            URLQueryItem(name: "u", value: user),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "FocusLift"),
            URLQueryItem(name: "f", value: "json"),
        ]
        items += params.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        guard let url = components.url else { throw SubsonicError.badURL }
        return url
    }

    private func fetch<T: Decodable>(_ endpoint: String, _ params: [String: String] = [:]) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: url(endpoint, params))
        let status = try JSONDecoder().decode(Envelope<Status>.self, from: data).response
        guard status.status == "ok" else {
            throw SubsonicError.server(status.error?.message ?? "Server returned an error.")
        }
        return try JSONDecoder().decode(Envelope<T>.self, from: data).response
    }
}

private struct Envelope<T: Decodable>: Decodable {
    let response: T
    private enum CodingKeys: String, CodingKey { case response = "subsonic-response" }
}

private struct Status: Decodable {
    struct APIError: Decodable { let message: String? }
    let status: String
    let error: APIError?
}

private struct PlaylistsBody: Decodable {
    struct List: Decodable { let playlist: [SubsonicPlaylist]? }
    let playlists: List?
}

private struct PlaylistBody: Decodable {
    struct Playlist: Decodable { let entry: [SubsonicSong]? }
    let playlist: Playlist
}

private struct RandomBody: Decodable {
    struct Songs: Decodable { let song: [SubsonicSong]? }
    let randomSongs: Songs?
}

private struct ArtistsBody: Decodable {
    struct Index: Decodable { let artist: [SubsonicArtist]? }
    struct Artists: Decodable { let index: [Index]? }
    let artists: Artists?
}

private struct ArtistBody: Decodable {
    struct Album: Decodable {
        let id: String
        private enum CodingKeys: String, CodingKey { case id }
        init(from decoder: Decoder) throws {
            id = try decoder.container(keyedBy: CodingKeys.self).decodeFlexibleID(forKey: .id)
        }
    }
    struct Artist: Decodable { let album: [Album]? }
    let artist: Artist
}

private struct AlbumBody: Decodable {
    struct Album: Decodable { let song: [SubsonicSong]? }
    let album: Album
}

private extension KeyedDecodingContainer {
    /// Navidrome sends string IDs, original Subsonic sometimes numbers.
    func decodeFlexibleID(forKey key: Key) throws -> String {
        if let string = try? decode(String.self, forKey: key) { return string }
        return String(try decode(Int.self, forKey: key))
    }
}
