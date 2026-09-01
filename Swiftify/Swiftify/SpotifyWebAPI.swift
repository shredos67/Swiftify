import Foundation

struct SpotifyWebAPI {
    func profile(accessToken: String) async throws -> SpotifyProfile {
        let profile: User = try await request(
            url: spotifyURL(path: "/v1/me"),
            accessToken: accessToken
        )
        return SpotifyProfile(
            id: profile.id,
            displayName: profile.displayName?.nilIfEmpty ?? "Spotify User",
            artworkURL: preferredArtworkURL(from: profile.images, preferredWidth: 192)
        )
    }

    func playlists(accessToken: String) async throws -> [SpotifyPlaylist] {
        var nextURL: URL? = spotifyURL(
            path: "/v1/me/playlists",
            queryItems: [URLQueryItem(name: "limit", value: "50")]
        )
        var playlists: [SpotifyPlaylist] = []

        while let url = nextURL {
            try Task.checkCancellation()
            let page: PlaylistPage = try await request(url: url, accessToken: accessToken)
            playlists.append(contentsOf: page.items.compactMap { $0.map(makePlaylist) })
            nextURL = page.next.flatMap(URL.init(string:))
        }

        return playlists
    }

    func songs(playlistID: String, accessToken: String) async throws -> [SpotifySong] {
        var nextURL: URL? = spotifyURL(
            path: "/v1/playlists/\(playlistID)/items",
            queryItems: [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "additional_types", value: "track"),
            ]
        )
        var songs: [SpotifySong] = []

        while let url = nextURL {
            try Task.checkCancellation()
            let page: PlaylistItemPage = try await request(url: url, accessToken: accessToken)
            songs.append(contentsOf: page.items.compactMap { item in
                (item.item ?? item.track).flatMap { makeSong($0) }
            })
            nextURL = page.next.flatMap(URL.init(string:))
        }

        return songs
    }

    func savedSongs(accessToken: String) async throws -> [SpotifySong] {
        var nextURL: URL? = spotifyURL(
            path: "/v1/me/tracks",
            queryItems: [URLQueryItem(name: "limit", value: "50")]
        )
        var songs: [SpotifySong] = []

        while let url = nextURL {
            try Task.checkCancellation()
            let page: SavedTrackPage = try await request(url: url, accessToken: accessToken)
            songs.append(contentsOf: page.items.compactMap { item in
                (item.item ?? item.track).flatMap { makeSong($0) }
            })
            nextURL = page.next.flatMap(URL.init(string:))
        }

        return songs
    }

    func recentlyPlayed(accessToken: String) async throws -> [SpotifySong] {
        let page: RecentlyPlayedPage = try await request(
            url: spotifyURL(
                path: "/v1/me/player/recently-played",
                queryItems: [URLQueryItem(name: "limit", value: "20")]
            ),
            accessToken: accessToken
        )
        return page.items.compactMap { item in
            (item.item ?? item.track).flatMap { makeSong($0) }
        }
    }

    func search(query: String, accessToken: String) async throws -> SpotifySearchResults {
        let response: SearchResponse = try await request(
            url: spotifyURL(
                path: "/v1/search",
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "type", value: "track,album,artist,playlist"),
                    URLQueryItem(name: "limit", value: "10"),
                ]
            ),
            accessToken: accessToken
        )

        return SpotifySearchResults(
            songs: response.tracks?.items.compactMap { makeSong($0) } ?? [],
            albums: response.albums?.items.compactMap(makeAlbum) ?? [],
            artists: response.artists?.items.compactMap(makeArtist) ?? [],
            playlists: response.playlists?.items.compactMap { $0.map(makePlaylist) } ?? []
        )
    }

    func song(trackID: String, accessToken: String) async throws -> SpotifySong {
        let track: Track = try await request(
            url: spotifyURL(path: "/v1/tracks/\(trackID)"),
            accessToken: accessToken
        )
        guard let song = makeSong(track) else {
            throw SpotifyWebAPIError.invalidData("Spotify returned an unsupported track.")
        }
        return song
    }

    func albumSongs(_ album: SpotifyAlbum, accessToken: String) async throws -> [SpotifySong] {
        var nextURL: URL? = spotifyURL(
            path: "/v1/albums/\(album.id)/tracks",
            queryItems: [URLQueryItem(name: "limit", value: "50")]
        )
        var songs: [SpotifySong] = []

        while let url = nextURL {
            try Task.checkCancellation()
            let page: TrackPage = try await request(url: url, accessToken: accessToken)
            songs.append(contentsOf: page.items.compactMap { track in
                makeSong(
                    track,
                    fallbackAlbum: album
                )
            })
            nextURL = page.next.flatMap(URL.init(string:))
        }
        return songs
    }

    func artistAlbums(_ artist: SpotifyArtist, accessToken: String) async throws -> [SpotifyAlbum] {
        var nextURL: URL? = spotifyURL(
            path: "/v1/artists/\(artist.id)/albums",
            queryItems: [
                URLQueryItem(name: "include_groups", value: "album,single"),
                URLQueryItem(name: "limit", value: "10"),
            ]
        )
        var albums: [SpotifyAlbum] = []

        while let url = nextURL {
            try Task.checkCancellation()
            let page: AlbumPage = try await request(url: url, accessToken: accessToken)
            albums.append(contentsOf: page.items.compactMap(makeAlbum))
            nextURL = page.next.flatMap(URL.init(string:))
        }

        var seenIDs: Set<String> = []
        return albums.filter { seenIDs.insert($0.id).inserted }
    }

    func createPlaylist(
        name: String,
        description: String,
        isPublic: Bool,
        accessToken: String
    ) async throws -> SpotifyPlaylist {
        let playlist: Playlist = try await request(
            url: spotifyURL(path: "/v1/me/playlists"),
            method: "POST",
            accessToken: accessToken,
            jsonBody: [
                "name": name,
                "description": description,
                "public": isPublic,
            ]
        )
        return makePlaylist(playlist)
    }

    func updatePlaylist(
        id: String,
        name: String,
        description: String,
        isPublic: Bool,
        accessToken: String
    ) async throws {
        _ = try await requestData(
            url: spotifyURL(path: "/v1/playlists/\(id)"),
            method: "PUT",
            accessToken: accessToken,
            jsonBody: [
                "name": name,
                "description": description,
                "public": isPublic,
            ]
        )
    }

    func add(_ song: SpotifySong, to playlistID: String, accessToken: String) async throws {
        _ = try await requestData(
            url: spotifyURL(path: "/v1/playlists/\(playlistID)/items"),
            method: "POST",
            accessToken: accessToken,
            jsonBody: ["uris": [song.uri]]
        )
    }

    func remove(_ song: SpotifySong, from playlistID: String, accessToken: String) async throws {
        _ = try await requestData(
            url: spotifyURL(path: "/v1/playlists/\(playlistID)/items"),
            method: "DELETE",
            accessToken: accessToken,
            jsonBody: ["items": [["uri": song.uri]]]
        )
    }

    func setSaved(_ isSaved: Bool, song: SpotifySong, accessToken: String) async throws {
        _ = try await requestData(
            url: spotifyURL(
                path: "/v1/me/library",
                queryItems: [URLQueryItem(name: "uris", value: song.uri)]
            ),
            method: isSaved ? "PUT" : "DELETE",
            accessToken: accessToken
        )
    }

    func savedStatuses(for songs: [SpotifySong], accessToken: String) async throws -> [String: Bool] {
        let uris = Array(Set(songs.map(\.uri))).prefix(40)
        guard !uris.isEmpty else {
            return [:]
        }

        let statuses: [Bool] = try await request(
            url: spotifyURL(
                path: "/v1/me/library/contains",
                queryItems: [URLQueryItem(name: "uris", value: uris.joined(separator: ","))]
            ),
            accessToken: accessToken
        )
        return Dictionary(uniqueKeysWithValues: zip(uris, statuses))
    }

    private func request<Response: Decodable>(
        url: URL,
        method: String = "GET",
        accessToken: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> Response {
        let data = try await requestData(
            url: url,
            method: method,
            accessToken: accessToken,
            jsonBody: jsonBody
        )
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SpotifyWebAPIError.invalidData(error.localizedDescription)
        }
    }

    private func requestData(
        url: URL,
        method: String = "GET",
        accessToken: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> Data {
        guard url.scheme == "https", url.host == "api.spotify.com" else {
            throw SpotifyWebAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SpotifyWebAPIError.invalidResponse
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?
                .error.message ?? "HTTP \(response.statusCode)"

            if response.statusCode == 401 {
                throw SpotifyWebAPIError.unauthorized(message)
            }

            if response.statusCode == 429 {
                let retryAfter = response
                    .value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Int.init)
                throw SpotifyWebAPIError.rateLimited(retryAfter)
            }

            throw SpotifyWebAPIError.requestFailed(message)
        }
        return data
    }

    private func spotifyURL(path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    private func makePlaylist(_ playlist: Playlist) -> SpotifyPlaylist {
        SpotifyPlaylist(
            id: playlist.id,
            name: playlist.name,
            description: playlist.description ?? "",
            songCount: playlist.items?.total ?? playlist.tracks?.total ?? 0,
            artworkURL: preferredArtworkURL(from: playlist.images, preferredWidth: 640),
            ownerID: playlist.owner?.id,
            ownerName: playlist.owner?.displayName,
            isPublic: playlist.public,
            isCollaborative: playlist.collaborative ?? false,
            uri: playlist.uri ?? "spotify:playlist:\(playlist.id)"
        )
    }

    private func makeSong(
        _ track: Track,
        fallbackAlbum: SpotifyAlbum? = nil
    ) -> SpotifySong? {
        guard
            track.type == nil || track.type == "track",
            track.uri.hasPrefix("spotify:track:")
        else {
            return nil
        }

        let trackAlbum = track.album.flatMap(makeAlbum)
        let album = trackAlbum ?? fallbackAlbum
        let artists = (track.artists ?? []).compactMap(makeArtist)

        return SpotifySong(
            name: track.name,
            artists: (track.artists ?? []).map(\.name).joined(separator: ", "),
            albumName: album?.name,
            artworkURL: preferredArtworkURL(from: track.album?.images, preferredWidth: 640)
                ?? album?.artworkURL,
            uri: track.uri,
            durationMs: track.durationMs,
            isExplicit: track.explicit ?? false,
            albumID: album?.id,
            albumURI: album?.uri,
            artistItems: artists.isEmpty ? nil : artists
        )
    }

    private func makeAlbum(_ album: Album) -> SpotifyAlbum? {
        guard let id = album.id, let uri = album.uri else {
            return nil
        }
        return SpotifyAlbum(
            id: id,
            name: album.name,
            artists: (album.artists ?? []).map(\.name).joined(separator: ", "),
            artworkURL: preferredArtworkURL(from: album.images, preferredWidth: 640),
            releaseDate: album.releaseDate,
            songCount: album.totalTracks ?? 0,
            uri: uri
        )
    }

    private func makeArtist(_ artist: Artist) -> SpotifyArtist? {
        guard let id = artist.id, let uri = artist.uri else {
            return nil
        }
        return SpotifyArtist(
            id: id,
            name: artist.name,
            artworkURL: preferredArtworkURL(from: artist.images, preferredWidth: 640),
            uri: uri
        )
    }

    private func preferredArtworkURL(
        from images: [ImageInfo]?,
        preferredWidth: Int = 640
    ) -> URL? {
        images?
            .compactMap { image -> (url: URL, width: Int)? in
                guard let url = URL(string: image.url) else {
                    return nil
                }
                return (url, image.width ?? preferredWidth)
            }
            .min { left, right in
                abs(left.width - preferredWidth) < abs(right.width - preferredWidth)
            }?
            .url
    }
}

private extension SpotifyWebAPI {
    struct User: Decodable {
        let id: String
        let displayName: String?
        let images: [ImageInfo]?

        enum CodingKeys: String, CodingKey {
            case id, images
            case displayName = "display_name"
        }
    }

    struct PlaylistPage: Decodable {
        let items: [Playlist?]
        let next: String?
    }

    struct Playlist: Decodable {
        let id: String
        let name: String
        let description: String?
        let items: ItemCount?
        let tracks: ItemCount?
        let images: [ImageInfo]?
        let owner: Owner?
        let `public`: Bool?
        let collaborative: Bool?
        let uri: String?
    }

    struct Owner: Decodable {
        let id: String
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    struct ItemCount: Decodable {
        let total: Int
    }

    struct PlaylistItemPage: Decodable {
        let items: [PlaylistItem]
        let next: String?
    }

    struct PlaylistItem: Decodable {
        let item: Track?
        let track: Track?
    }

    struct SavedTrackPage: Decodable {
        let items: [SavedTrack]
        let next: String?
    }

    struct SavedTrack: Decodable {
        let item: Track?
        let track: Track?
    }

    struct RecentlyPlayedPage: Decodable {
        let items: [PlayHistory]
    }

    struct PlayHistory: Decodable {
        let item: Track?
        let track: Track?
    }

    struct SearchResponse: Decodable {
        let tracks: TrackPage?
        let albums: AlbumPage?
        let artists: ArtistPage?
        let playlists: PlaylistPage?
    }

    struct TrackPage: Decodable {
        let items: [Track]
        let next: String?
    }

    struct AlbumPage: Decodable {
        let items: [Album]
        let next: String?
    }

    struct ArtistPage: Decodable {
        let items: [Artist]
    }

    struct Track: Decodable {
        let name: String
        let uri: String
        let type: String?
        let artists: [Artist]?
        let album: Album?
        let durationMs: Int?
        let explicit: Bool?

        enum CodingKeys: String, CodingKey {
            case name, uri, type, artists, album, explicit
            case durationMs = "duration_ms"
        }
    }

    struct Artist: Decodable {
        let id: String?
        let name: String
        let images: [ImageInfo]?
        let uri: String?
    }

    struct Album: Decodable {
        let id: String?
        let name: String
        let images: [ImageInfo]?
        let artists: [Artist]?
        let releaseDate: String?
        let totalTracks: Int?
        let uri: String?

        enum CodingKeys: String, CodingKey {
            case id, name, images, artists, uri
            case releaseDate = "release_date"
            case totalTracks = "total_tracks"
        }
    }

    struct ImageInfo: Decodable {
        let url: String
        let width: Int?
    }

    struct ErrorEnvelope: Decodable {
        let error: ErrorDetails
    }

    struct ErrorDetails: Decodable {
        let message: String
    }
}

enum SpotifyWebAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidData(String)
    case unauthorized(String)
    case rateLimited(Int?)
    case requestFailed(String)

    var shouldRefreshAccessToken: Bool {
        if case .unauthorized = self {
            return true
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Spotify returned an invalid API URL."
        case .invalidResponse:
            "Spotify returned an invalid API response."
        case let .invalidData(message):
            "Could not read Spotify's response: \(message)"
        case let .unauthorized(message):
            "Spotify API authorization failed: \(message)"
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "Spotify rate limit exceeded. Try again in \(retryAfter) seconds."
            } else {
                "Spotify rate limit exceeded. Try again shortly."
            }
        case let .requestFailed(message):
            "Spotify API request failed: \(message)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
