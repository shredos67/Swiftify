import Foundation

struct SpotifyProfile: Hashable, Sendable {
    let id: String
    let displayName: String
    let artworkURL: URL?
}

struct SpotifyPlaylist: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let songCount: Int
    let artworkURL: URL?
    let ownerID: String?
    let ownerName: String?
    let isPublic: Bool?
    let isCollaborative: Bool
    let uri: String

    var ownerDisplayName: String {
        ownerName?.nilIfEmpty ?? "Spotify"
    }

    func canModify(currentUserID: String?) -> Bool {
        isCollaborative || (currentUserID != nil && ownerID == currentUserID)
    }
}

struct SpotifySong: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let artists: String
    let albumName: String?
    let artworkURL: URL?
    let uri: String
    let durationMs: Int?
    let isExplicit: Bool
    let albumID: String?
    let albumURI: String?
    let artistItems: [SpotifyArtist]?

    init(
        name: String,
        artists: String,
        albumName: String?,
        artworkURL: URL?,
        uri: String,
        durationMs: Int? = nil,
        isExplicit: Bool = false,
        albumID: String? = nil,
        albumURI: String? = nil,
        artistItems: [SpotifyArtist]? = nil
    ) {
        id = UUID()
        self.name = name
        self.artists = artists
        self.albumName = albumName
        self.artworkURL = artworkURL
        self.uri = uri
        self.durationMs = durationMs
        self.isExplicit = isExplicit
        self.albumID = albumID
        self.albumURI = albumURI
        self.artistItems = artistItems
    }

    var spotifyID: String {
        uri.split(separator: ":").last.map(String.init) ?? uri
    }

    var albumDestination: SpotifyAlbum? {
        guard let albumID, let albumName else {
            return nil
        }
        return SpotifyAlbum(
            id: albumID,
            name: albumName,
            artists: artists,
            artworkURL: artworkURL,
            releaseDate: nil,
            songCount: 0,
            uri: albumURI ?? "spotify:album:\(albumID)"
        )
    }

    var primaryArtist: SpotifyArtist? {
        artistItems?.first
    }
}

struct SpotifyAlbum: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let artists: String
    let artworkURL: URL?
    let releaseDate: String?
    let songCount: Int
    let uri: String
}

struct SpotifyArtist: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let artworkURL: URL?
    let uri: String
}

struct SpotifySearchResults: Sendable {
    let songs: [SpotifySong]
    let albums: [SpotifyAlbum]
    let artists: [SpotifyArtist]
    let playlists: [SpotifyPlaylist]

    static let empty = SpotifySearchResults(
        songs: [],
        albums: [],
        artists: [],
        playlists: []
    )

    var isEmpty: Bool {
        songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
