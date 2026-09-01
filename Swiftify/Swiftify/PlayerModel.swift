//
//  PlayerModel.swift
//  Swiftify
//
//  Created by addenator on 2026-08-27.
//

import Combine
import Foundation

enum AppDestination: Hashable {
    case home
    case search
    case songs
    case playlists
    case pinnedPlaylists
    case playlist(String)
    case album(SpotifyAlbum)
    case artist(SpotifyArtist)
}

enum PlaylistSortOrder: String, CaseIterable, Identifiable {
    case playlist = "Playlist Order"
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case duration = "Time"

    var id: Self { self }
}

@MainActor
final class PlayerModel: ObservableObject {
    private enum LoginPurpose {
        case playback
        case library(clientID: String)

        var clientID: String {
            switch self {
            case .playback:
                SpotifyOAuthFlow.playbackClientID
            case let .library(clientID):
                clientID
            }
        }
    }

    let core = SpotifyCore()
    let spectrum = AudioSpectrumModel()
    private let oauthFlow = SpotifyOAuthFlow()
    private let webAPI = SpotifyWebAPI()
    private let playbackClientID = SpotifyOAuthFlow.playbackClientID
    private(set) var refreshToken: String?
    private var playbackAccessToken: String?
    private var playbackAccessTokenExpirationDate: Date?
    private var playbackTokenRefreshTask: Task<SpotifyOAuthToken, Error>?
    private var libraryAccessToken: String?
    private var libraryRefreshToken: String?
    private var libraryAccessTokenExpirationDate: Date?
    private var libraryTokenRefreshTask: Task<SpotifyOAuthToken, Error>?
    private var libraryAuthorizationVersion = 0
    private var loginPurpose: LoginPurpose?
    private var songLoadTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var playbackUpdateTask: Task<Void, Never>?
    private var spectrumUpdateTask: Task<Void, Never>?
    private var lastSyncedMediaPosition: UInt32 = .max
    private var lyricsTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var artistLoadTask: Task<Void, Never>?
    private var playbackHistory: [SpotifySong] = []
    private var shuffledPlaybackQueue: [SpotifySong] = []
    private var volumeBeforeMute = 0.75
    private lazy var systemMediaSession = SystemMediaSession(
        handlers: .init(
            play: { [weak self] in self?.resume() },
            pause: { [weak self] in self?.pause() },
            togglePlayback: { [weak self] in self?.togglePlayback() },
            nextTrack: { [weak self] in self?.skipForward() },
            previousTrack: { [weak self] in self?.skipBackward() },
            seek: { [weak self] position in
                let milliseconds = min(
                    max(position * 1_000, 0),
                    Double(UInt32.max)
                )
                self?.seek(to: UInt32(milliseconds.rounded()))
            }
        )
    )

    @Published var libraryClientID = ""
    @Published var status = "Disconnected"
    @Published var errorMessage: String?
    @Published var authorizationURL: URL?
    @Published var isShowingLogin = false
    @Published var isConnected = false
    @Published private(set) var isEvaluatingStoredLogin = true
    @Published private(set) var libraryStatus = "Not connected"
    @Published private(set) var isLibraryConnected = false
    @Published private(set) var libraryNeedsAuthorizationUpgrade = false
    @Published private(set) var profile: SpotifyProfile?
    @Published private(set) var playlists: [SpotifyPlaylist] = []
    @Published private(set) var pinnedPlaylistIDs: Set<String> = []
    @Published private(set) var songs: [SpotifySong] = []
    @Published private(set) var savedSongs: [SpotifySong] = []
    @Published private(set) var recentlyPlayed: [SpotifySong] = []
    @Published private(set) var albumSongs: [SpotifySong] = []
    @Published private(set) var artistAlbums: [SpotifyAlbum] = []
    @Published private(set) var searchResults = SpotifySearchResults.empty
    @Published private(set) var searchPlaybackHistory: [SpotifySong] = []
    @Published private(set) var savedTrackURIs: Set<String> = []
    @Published private(set) var playbackQueue: [SpotifySong] = []
    @Published private(set) var songNavigationRequest: AppDestination?
    @Published var destination: AppDestination? = .home
    @Published var searchQuery = ""
    @Published var playlistFilterQuery = ""
    @Published var playlistSortOrder = PlaylistSortOrder.playlist
    @Published private(set) var selectedPlaylistID: String?
    @Published private(set) var isLoadingPlaylists = false
    @Published private(set) var isLoadingSongs = false
    @Published private(set) var isLoadingHome = false
    @Published private(set) var isLoadingSavedSongs = false
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingArtist = false
    @Published private(set) var isCreatingPlaylist = false
    @Published private(set) var currentSong: SpotifySong?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackPositionMs: UInt32 = 0
    @Published private(set) var playbackDurationMs: UInt32 = 0
    @Published private(set) var volume = 0.75
    @Published private(set) var isShuffleEnabled = false
    @Published private(set) var repeatMode: PlaybackRepeatMode = .off
    @Published private(set) var visualizersEnabled = true
    @Published private(set) var lyrics: SpotifyLyrics?
    @Published private(set) var isLoadingLyrics = false
    @Published private(set) var lyricsMessage: String?
    @Published var isShowingLyrics = true
    @Published var isShowingQueue = false
    @Published private(set) var isDownloadingPlaylist = false
    @Published private(set) var downloadedTrackURIs: Set<String> = []

    var selectedPlaylistName: String {
        playlists.first(where: { $0.id == selectedPlaylistID })?.name ?? "Songs"
    }

    var selectedPlaylist: SpotifyPlaylist? {
        playlists.first(where: { $0.id == selectedPlaylistID })
    }

    var editablePlaylists: [SpotifyPlaylist] {
        playlists.filter { $0.canModify(currentUserID: profile?.id) }
    }

    var pinnedPlaylists: [SpotifyPlaylist] {
        playlists.filter { pinnedPlaylistIDs.contains($0.id) }
    }

    var upNextSongs: [SpotifySong] {
        let queue = activePlaybackQueue
        guard let currentQueueIndex else {
            return queue
        }
        let nextIndex = queue.index(after: currentQueueIndex)
        return nextIndex < queue.endIndex ? Array(queue[nextIndex...]) : []
    }

    var canSkipBackward: Bool {
        guard currentSong != nil else {
            return false
        }

        if playbackPositionMs > 3_000 {
            return true
        }
        if isShuffleEnabled {
            return !playbackHistory.isEmpty
        }
        guard let currentQueueIndex else {
            return false
        }
        return currentQueueIndex > playbackQueue.startIndex || repeatMode == .all
    }

    var canSkipForward: Bool {
        guard currentSong != nil else {
            return false
        }
        if isShuffleEnabled {
            let queue = activePlaybackQueue
            guard let currentQueueIndex else {
                return false
            }
            return currentQueueIndex < queue.index(before: queue.endIndex)
                || repeatMode == .all
        }
        guard let currentQueueIndex else {
            return false
        }
        return currentQueueIndex < playbackQueue.index(before: playbackQueue.endIndex)
            || repeatMode == .all
    }

    var activeLyricLineID: SpotifyLyricLine.ID? {
        guard let lyrics, lyrics.isSynchronized else {
            return nil
        }

        return lyrics.lines.last(where: { $0.startTimeMs <= playbackPositionMs })?.id
    }

    init() {
        _ = systemMediaSession
        configureDownloadsDirectory()
        do {
            try systemMediaSession.configureAudioSession()
        } catch {
            logError("Configuring the system audio session", error)
        }
        visualizersEnabled = UserDefaults.standard.object(
            forKey: AppPreferences.visualizersEnabledKey
        ) as? Bool ?? true
        pinnedPlaylistIDs = Set(
            UserDefaults.standard.stringArray(
                forKey: AppPreferences.pinnedPlaylistIDsKey
            ) ?? []
        )
        if let historyData = UserDefaults.standard.data(
            forKey: AppPreferences.searchPlaybackHistoryKey
        ), let storedHistory = try? JSONDecoder().decode(
            [SpotifySong].self,
            from: historyData
        ) {
            searchPlaybackHistory = storedHistory
        }
        if visualizersEnabled {
            startSpectrumUpdates()
        }
        startPlaybackUpdates()

        do {
            let playbackCredentials = try SpotifyCredentialStore.loadPlayback()
            let libraryCredentials = try SpotifyCredentialStore.loadLibrary()

            let validPlaybackCredentials = playbackCredentials.flatMap { credentials in
                credentials.clientID == playbackClientID
                    && credentials.authorizationVersion == SpotifyOAuthFlow.playbackAuthorizationVersion
                    ? credentials
                    : nil
            }
            let validLibraryCredentials = libraryCredentials

            if let libraryCredentials {
                libraryClientID = libraryCredentials.clientID
                libraryRefreshToken = libraryCredentials.refreshToken
                libraryAuthorizationVersion = libraryCredentials.authorizationVersion ?? 0
                libraryNeedsAuthorizationUpgrade =
                    libraryCredentials.authorizationVersion
                    != SpotifyOAuthFlow.libraryAuthorizationVersion
            }

            if let validPlaybackCredentials {
                refreshToken = validPlaybackCredentials.refreshToken
                status = "Reconnecting"
            } else {
                status = "Sign in to play"
            }

            if validLibraryCredentials != nil {
                libraryStatus = "Reconnecting"
            }

            guard validPlaybackCredentials != nil || validLibraryCredentials != nil else {
                isEvaluatingStoredLogin = false
                return
            }

            Task { [weak self] in
                guard let self else { return }

                if let validPlaybackCredentials {
                    await self.restorePlaybackSession(using: validPlaybackCredentials)
                }
                if let validLibraryCredentials {
                    await self.restoreLibrarySession(using: validLibraryCredentials)
                }
                self.isEvaluatingStoredLogin = false
            }
        } catch {
            isEvaluatingStoredLogin = false
            errorMessage = error.userFacingMessage
            logError("Reading saved logins", error)
        }
    }

    private func configureDownloadsDirectory() {
        do {
            let fileManager = FileManager.default
            var directory = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appending(path: "Swiftify", directoryHint: .isDirectory)
            .appending(path: "Downloads", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? directory.setResourceValues(resourceValues)
            try core.set_downloads_directory(directory.path(percentEncoded: false))
            refreshDownloadedTracks()
        } catch {
            errorMessage = "Could not prepare offline downloads: \(error.userFacingMessage)"
            logError("Preparing offline downloads", error)
        }
    }

    func beginPlaybackLogin() {

        do {
            loginPurpose = .playback
            authorizationURL = try oauthFlow.makeAuthorizationURL(
                clientID: playbackClientID,
                scopes: ["streaming"]
            )
            errorMessage = nil
            status = "Waiting for Spotify login"
            isShowingLogin = true
        } catch {
            loginPurpose = nil
            errorMessage = error.userFacingMessage
            logError("Starting playback authorization", error)
        }
    }

    func beginLibraryLogin() {
        let clientID = libraryClientID.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            loginPurpose = .library(clientID: clientID)
            authorizationURL = try oauthFlow.makeAuthorizationURL(
                clientID: clientID,
                scopes: [
                    "playlist-read-private",
                    "playlist-read-collaborative",
                    "playlist-modify-public",
                    "playlist-modify-private",
                    "user-read-private",
                    "user-read-recently-played",
                    "user-library-read",
                    "user-library-modify",
                ]
            )
            libraryClientID = clientID
            errorMessage = nil
            libraryStatus = "Waiting for Spotify login"
            isShowingLogin = true
        } catch {
            loginPurpose = nil
            errorMessage = error.userFacingMessage
            logError("Starting playlist authorization", error)
        }
    }

    func completeLogin(callbackURL: URL) async {
        guard let loginPurpose else {
            errorMessage = SpotifyOAuthError.invalidCallback.localizedDescription
            return
        }

        isShowingLogin = false
        authorizationURL = nil
        defer { self.loginPurpose = nil }

        do {
            let token = try await oauthFlow.exchangeCallback(
                callbackURL,
                clientID: loginPurpose.clientID
            )
            errorMessage = nil

            switch loginPurpose {
            case .playback:
                try await completePlaybackLogin(with: token)
            case let .library(clientID):
                try await completeLibraryLogin(with: token, clientID: clientID)
            }
        } catch {
            switch loginPurpose {
            case .playback:
                status = "Disconnected"
                isConnected = false
            case .library:
                libraryStatus = "Not connected"
                isLibraryConnected = false
            }
            errorMessage = error.userFacingMessage
            logError("Completing Spotify authorization", error)
        }
    }

    func cancelLogin() {
        oauthFlow.cancel()
        authorizationURL = nil
        isShowingLogin = false

        switch loginPurpose {
        case .playback:
            status = isConnected ? "Connected" : "Disconnected"
        case .library:
            libraryStatus = isLibraryConnected ? "Connected" : "Not connected"
        case nil:
            break
        }
        loginPurpose = nil
    }

    func connect(accessToken: String) async {
        playbackAccessToken = accessToken
        playbackAccessTokenExpirationDate = nil

        do {
            try await connectPlaybackCore(
                accessToken: accessToken,
                clientID: playbackClientID
            )
            status = "Connected"
            isConnected = true
            errorMessage = nil
        } catch {
            status = "Disconnected"
            isConnected = false
            errorMessage = error.userFacingMessage
            logError("Connecting playback session", error)
        }
    }

    func play(_ song: SpotifySong, in queue: [SpotifySong]? = nil) {
        beginPlayback(song, in: queue, addsToSearchHistory: false)
    }

    func playFromSearch(_ song: SpotifySong, in queue: [SpotifySong]) {
        beginPlayback(song, in: queue, addsToSearchHistory: true)
    }

    private func beginPlayback(
        _ song: SpotifySong,
        in requestedQueue: [SpotifySong]?,
        addsToSearchHistory: Bool
    ) {
        let queue = requestedQueue ?? songs
        playbackQueue = queue.contains(where: { $0.id == song.id }) ? queue : [song]
        playbackHistory = []
        if isShuffleEnabled {
            rebuildShuffledPlaybackQueue(startingWith: song)
        } else {
            shuffledPlaybackQueue = []
        }
        startPlayback(song, addsToSearchHistory: addsToSearchHistory)
    }

    func playNext(_ song: SpotifySong) {
        guard let currentSong, currentQueueIndex != nil else {
            play(song, in: [song])
            return
        }
        guard song.id != currentSong.id else {
            return
        }

        playbackQueue.removeAll { $0.uri == song.uri && $0.id != currentSong.id }
        guard let refreshedIndex = playbackQueue.firstIndex(where: { $0.id == currentSong.id }) else {
            return
        }
        playbackQueue.insert(song, at: playbackQueue.index(after: refreshedIndex))

        if isShuffleEnabled {
            shuffledPlaybackQueue.removeAll { $0.id == song.id }
            if let shuffledIndex = shuffledPlaybackQueue.firstIndex(where: { $0.id == currentSong.id }) {
                shuffledPlaybackQueue.insert(
                    song,
                    at: shuffledPlaybackQueue.index(after: shuffledIndex)
                )
            } else {
                rebuildShuffledPlaybackQueue(startingWith: currentSong)
            }
        }
        syncSystemMediaSession()
    }

    func playLast(_ song: SpotifySong) {
        guard let currentSong else {
            play(song, in: [song])
            return
        }
        guard song.id != currentSong.id else {
            return
        }
        playbackQueue.removeAll { $0.uri == song.uri && $0.id != currentSong.id }
        playbackQueue.append(song)
        if isShuffleEnabled {
            shuffledPlaybackQueue.removeAll { $0.id == song.id }
            shuffledPlaybackQueue.append(song)
        }
        syncSystemMediaSession()
    }

    func playFromQueue(_ song: SpotifySong) {
        guard playbackQueue.contains(where: { $0.id == song.id }) else {
            return
        }
        startPlayback(song)
    }

    func toggleLyricsPanel() {
        isShowingLyrics.toggle()
        if isShowingLyrics {
            isShowingQueue = false
        }
    }

    func toggleQueuePanel() {
        isShowingQueue.toggle()
        if isShowingQueue {
            isShowingLyrics = false
        }
    }

    func downloadPlaylist(_ playlist: SpotifyPlaylist) {
        let songs = self.songs
        guard !songs.isEmpty, !isDownloadingPlaylist else {
            return
        }
        isDownloadingPlaylist = true
        Task {
            defer {
                Task { @MainActor in
                    self.isDownloadingPlaylist = false
                    self.refreshDownloadedTracks()
                }
            }
            do {
                for song in songs where !Task.isCancelled {
                    if core.track_available_locally(song.uri) {
                        continue
                    }
                    do {
                        try await downloadTrackWithRetry(song.uri)
                    } catch {
                        logError("Downloading \(song.uri)", error)
                        throw error
                    }
                }
            } catch {
                errorMessage = error.userFacingMessage
            }
        }
    }

    func downloadTrack(_ song: SpotifySong) {
        Task {
            defer { refreshDownloadedTracks() }
            do {
                try await downloadTrackWithRetry(song.uri)
            } catch {
                errorMessage = error.userFacingMessage
            }
        }
    }

    func removeDownloadedTrack(_ song: SpotifySong) {
        if core.remove_download(song.uri) {
            refreshDownloadedTracks()
        }
    }

    func refreshDownloadedTracks() {
        let uris = core.downloaded_track_uris().map { $0.as_str().toString() }
        downloadedTrackURIs = Set(uris)
    }

    func isDownloaded(_ song: SpotifySong) -> Bool {
        core.track_available_locally(song.uri)
    }

    func isPlaylistDownloaded(_ songs: [SpotifySong]) -> Bool {
        !songs.isEmpty && songs.allSatisfy { downloadedTrackURIs.contains($0.uri) }
    }

    func togglePlayback() {
        guard currentSong != nil else {
            return
        }

        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func skipBackward() {
        if playbackPositionMs > 3_000 {
            seek(to: 0)
            return
        }

        if isShuffleEnabled {
            guard let previous = playbackHistory.popLast() else {
                return
            }
            startPlayback(previous, recordHistory: false)
            return
        }

        guard let currentQueueIndex else {
            return
        }
        let queue = activePlaybackQueue
        if currentQueueIndex > playbackQueue.startIndex {
            startPlayback(
                queue[queue.index(before: currentQueueIndex)],
                recordHistory: false
            )
        } else if repeatMode == .all, let last = queue.last {
            startPlayback(last, recordHistory: false)
        }
    }

    func skipForward() {
        guard let nextSong = nextQueueSong(allowWrap: repeatMode == .all) else {
            return
        }

        startPlayback(nextSong)
    }

    func seek(to positionMs: UInt32) {
        let positionMs = min(positionMs, playbackDurationMs == 0 ? positionMs : playbackDurationMs)

        do {
            try core.seek(positionMs)
            playbackPositionMs = positionMs
            syncSystemMediaSession()
        } catch {
            errorMessage = error.userFacingMessage
            logError("Seeking playback", error)
        }
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
        playbackHistory = []
        if isShuffleEnabled {
            rebuildShuffledPlaybackQueue(startingWith: currentSong)
        } else {
            shuffledPlaybackQueue = []
        }
        syncSystemMediaSession()
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    func setVolume(_ volume: Double) {
        let volume = volume.clamped(to: 0 ... 1)
        if volume > 0.01 {
            volumeBeforeMute = volume
        }

        do {
            try core.set_volume(Float(volume))
            self.volume = volume
        } catch {
            errorMessage = error.userFacingMessage
            logError("Changing volume", error)
        }
    }

    func toggleMute() {
        setVolume(volume > 0.01 ? 0 : max(volumeBeforeMute, 0.25))
    }

    private func startPlayback(
        _ song: SpotifySong,
        recordHistory: Bool = true,
        addsToSearchHistory: Bool = false
    ) {
        if recordHistory, let currentSong, currentSong.id != song.id {
            playbackHistory.append(currentSong)
        }

        playbackTask?.cancel()
        currentSong = song
        spectrum.setArtwork(song.artworkURL)
        isPlaying = false
        playbackPositionMs = 0
        playbackDurationMs = 0
        loadLyrics(for: song)
        do {
            try systemMediaSession.prepareForPlayback()
        } catch {
            logError("Preparing the system audio session", error)
        }
        syncSystemMediaSession()

        playbackTask = Task {
            do {
                status = "Loading"
                errorMessage = nil

                if core.track_available_locally(song.uri) {
                    try await core.play_local_track(song.uri)
                } else {
                    try await ensureFreshPlaybackConnection()

                    do {
                        try await core.play_track(song.uri)
                    } catch {
                        try await ensureFreshPlaybackConnection(force: true)
                        try await core.play_track(song.uri)
                    }
                }

                guard !Task.isCancelled, currentSong?.id == song.id else {
                    return
                }
                status = "Playing"
                isPlaying = true
                if addsToSearchHistory {
                    recordSearchPlayback(song)
                }
                syncSystemMediaSession()
            } catch {
                guard !Task.isCancelled, currentSong?.id == song.id else {
                    return
                }
                status = isConnected ? "Connected" : "Disconnected"
                isPlaying = false
                syncSystemMediaSession()
                errorMessage = error.userFacingMessage
                logError("Playing \(song.uri)", error)
            }
        }
    }

    private func downloadTrackWithRetry(_ spotifyURI: String) async throws {
        try await ensureFreshPlaybackConnection()
        do {
            try await core.download_track(spotifyURI)
        } catch {
            try await ensureFreshPlaybackConnection(force: true)
            try await core.download_track(spotifyURI)
        }
    }

    private func refreshPlaybackAccessTokenIfNeeded(force: Bool = false) async throws -> String {
        if let playbackTokenRefreshTask {
            return try await playbackTokenRefreshTask.value.accessToken
        }

        if !force,
           let accessToken = playbackAccessToken,
           let expirationDate = playbackAccessTokenExpirationDate,
           expirationDate > Date().addingTimeInterval(60) {
            return accessToken
        }

        guard let refreshToken else {
            throw LibrarySessionError.missingRefreshToken
        }

        let clientID = playbackClientID
        let refreshTask = Task {
            try await oauthFlow.refreshAccessToken(
                refreshToken: refreshToken,
                clientID: clientID
            )
        }
        playbackTokenRefreshTask = refreshTask
        defer { playbackTokenRefreshTask = nil }

        let token = try await refreshTask.value
        let nextRefreshToken = token.refreshToken ?? refreshToken
        try SpotifyCredentialStore.savePlayback(
            StoredSpotifyCredentials(
                clientID: clientID,
                refreshToken: nextRefreshToken,
                authorizationVersion: SpotifyOAuthFlow.playbackAuthorizationVersion
            )
        )
        playbackAccessToken = token.accessToken
        playbackAccessTokenExpirationDate = token.expirationDate
        self.refreshToken = nextRefreshToken
        return token.accessToken
    }

    private func ensureFreshPlaybackConnection(force: Bool = false) async throws {
        let previousAccessToken = playbackAccessToken
        let accessToken = try await refreshPlaybackAccessTokenIfNeeded(force: force)

        if force || previousAccessToken != accessToken || !isConnected {
            try await connectPlaybackCore(
                accessToken: accessToken,
                clientID: playbackClientID
            )
            playbackAccessToken = accessToken
            status = "Connected"
            isConnected = true
            errorMessage = nil
            refreshDownloadedTracks()
        }
    }

    private func recordSearchPlayback(_ song: SpotifySong) {
        searchPlaybackHistory.removeAll { $0.uri == song.uri }
        searchPlaybackHistory.insert(song, at: 0)
        if searchPlaybackHistory.count > 20 {
            searchPlaybackHistory.removeLast(searchPlaybackHistory.count - 20)
        }
        persistSearchPlaybackHistory()
    }

    private func persistSearchPlaybackHistory() {
        guard let data = try? JSONEncoder().encode(searchPlaybackHistory) else {
            return
        }
        UserDefaults.standard.set(
            data,
            forKey: AppPreferences.searchPlaybackHistoryKey
        )
    }

    func pause() {

        do {
            try core.pause()
            status = "Paused"
            isPlaying = false
            syncSystemMediaSession()
        } catch {
            errorMessage = error.userFacingMessage
            logError("Pausing playback", error)
        }
    }

    private func resume() {

        do {
            try systemMediaSession.prepareForPlayback()
            try core.play()
            status = "Playing"
            isPlaying = true
            syncSystemMediaSession()
        } catch {
            errorMessage = error.userFacingMessage
            logError("Resuming playback", error)
        }
    }

    private func startSpectrumUpdates() {
        spectrumUpdateTask?.cancel()
        spectrumUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))

                guard let self else {
                    return
                }

                if isPlaying {
                    spectrum.update(core.spectrum_levels().map(CGFloat.init))
                } else {
                    spectrum.clear()
                }
            }
        }
    }

    func setVisualizersEnabled(_ isEnabled: Bool) {
        guard visualizersEnabled != isEnabled else {
            return
        }

        visualizersEnabled = isEnabled
        if isEnabled {
            startSpectrumUpdates()
        } else {
            spectrumUpdateTask?.cancel()
            spectrumUpdateTask = nil
            spectrum.clear()
        }
    }

    private func startPlaybackUpdates() {
        playbackUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))

                guard let self, currentSong != nil else {
                    continue
                }

                syncPlaybackPositionAndDuration()

                if core.take_end_of_track() {
                    handleEndOfTrack()
                }
            }
        }
    }

    private func syncPlaybackPositionAndDuration() {
        let position = core.playback_position_ms()
        let duration = core.playback_duration_ms()

        if playbackPositionMs != position {
            playbackPositionMs = position
        }
        if playbackDurationMs != duration {
            playbackDurationMs = duration
        }

        if abs(Int64(position) - Int64(lastSyncedMediaPosition)) >= 1_000 {
            lastSyncedMediaPosition = position
            syncSystemMediaSession()
        }
    }

    private func loadLyrics(for song: SpotifySong) {
        lyricsTask?.cancel()
        lyrics = nil
        lyricsMessage = nil
        isLoadingLyrics = true

        lyricsTask = Task {
            do {
                let json = try await core.lyrics_json(song.uri).toString()
                let decodedLyrics = try JSONDecoder().decode(
                    SpotifyLyrics.self,
                    from: Data(json.utf8)
                )
                guard !Task.isCancelled, currentSong?.id == song.id else {
                    return
                }

                lyrics = decodedLyrics
                isLoadingLyrics = false
            } catch {
                guard !Task.isCancelled, currentSong?.id == song.id else {
                    return
                }

                isLoadingLyrics = false
                lyricsMessage = EasterEgg.phrase
            }
        }
    }

    private func handleEndOfTrack() {
        guard let currentSong else {
            return
        }

        switch repeatMode {
        case .one:
            startPlayback(currentSong, recordHistory: false)
        case .off, .all:
            if let nextSong = nextQueueSong(allowWrap: repeatMode == .all) {
                startPlayback(nextSong)
            } else {
                isPlaying = false
                status = "Finished"
                syncSystemMediaSession()
            }
        }
    }

    private func syncSystemMediaSession() {
        let queue = activePlaybackQueue
        let index = currentSong.flatMap { song in
            queue.firstIndex(where: { $0.id == song.id })
        }
        let reportedDuration = max(
            playbackDurationMs,
            UInt32(clamping: currentSong?.durationMs ?? 0)
        )
        systemMediaSession.update(
            song: currentSong,
            isPlaying: isPlaying,
            position: TimeInterval(playbackPositionMs) / 1_000,
            duration: TimeInterval(reportedDuration) / 1_000,
            queueIndex: index,
            queueCount: queue.count,
            canSkipBackward: canSkipBackward,
            canSkipForward: canSkipForward
        )
    }

    private func nextQueueSong(allowWrap: Bool) -> SpotifySong? {
        let queue = activePlaybackQueue
        guard currentSong != nil else {
            return queue.first
        }

        guard let currentQueueIndex else {
            return queue.first
        }
        if currentQueueIndex < queue.index(before: queue.endIndex) {
            return queue[queue.index(after: currentQueueIndex)]
        }
        return allowWrap ? queue.first : nil
    }

    func showHome() {
        destination = .home
        selectedPlaylistID = nil
        if recentlyPlayed.isEmpty {
            Task { await loadHome() }
        }
    }

    func showSearch() {
        destination = .search
        selectedPlaylistID = nil
    }

    func showSavedSongs() {
        destination = .songs
        selectedPlaylistID = nil
        if savedSongs.isEmpty {
            Task { await loadSavedSongs() }
        }
    }

    func showPlaylists() {
        destination = .playlists
        selectedPlaylistID = nil
    }

    func showPinnedPlaylists() {
        destination = .pinnedPlaylists
        selectedPlaylistID = nil
    }

    func isPlaylistPinned(_ playlist: SpotifyPlaylist) -> Bool {
        pinnedPlaylistIDs.contains(playlist.id)
    }

    func togglePinnedPlaylist(_ playlist: SpotifyPlaylist) {
        if pinnedPlaylistIDs.contains(playlist.id) {
            pinnedPlaylistIDs.remove(playlist.id)
        } else {
            pinnedPlaylistIDs.insert(playlist.id)
        }
        UserDefaults.standard.set(
            Array(pinnedPlaylistIDs).sorted(),
            forKey: AppPreferences.pinnedPlaylistIDsKey
        )
    }

    func selectPlaylist(_ playlist: SpotifyPlaylist) {
        destination = .playlist(playlist.id)
        selectedPlaylistID = playlist.id
        playlistFilterQuery = ""
        playlistSortOrder = .playlist
        songs = []
        errorMessage = nil
        songLoadTask?.cancel()

        guard libraryAccessToken != nil else {
            return
        }

        isLoadingSongs = true
        songLoadTask = Task {
            do {
                let loadedSongs = try await withLibraryAccessToken {
                    try await webAPI.songs(playlistID: playlist.id, accessToken: $0)
                }
                guard !Task.isCancelled else {
                    return
                }

                songs = loadedSongs
                isLoadingSongs = false
                await loadSavedStatuses(for: loadedSongs)
            } catch is CancellationError {
                isLoadingSongs = false
            } catch {
                isLoadingSongs = false
                errorMessage = error.userFacingMessage
                logError("Loading songs from \"\(playlist.name)\"", error)
            }
        }
    }

    func selectAlbum(_ album: SpotifyAlbum) {
        destination = .album(album)
        selectedPlaylistID = nil
        albumSongs = []
        songLoadTask?.cancel()

        guard libraryAccessToken != nil else {
            return
        }

        isLoadingSongs = true
        songLoadTask = Task {
            do {
                let loadedSongs = try await withLibraryAccessToken {
                    try await webAPI.albumSongs(album, accessToken: $0)
                }
                guard !Task.isCancelled else {
                    return
                }
                albumSongs = loadedSongs
                isLoadingSongs = false
                await loadSavedStatuses(for: loadedSongs)
            } catch is CancellationError {
                isLoadingSongs = false
            } catch {
                isLoadingSongs = false
                errorMessage = error.userFacingMessage
                logError("Loading \"\(album.name)\"", error)
            }
        }
    }

    func goToAlbum(for song: SpotifySong) {
        Task {
            do {
                let album: SpotifyAlbum
                if let knownAlbum = song.albumDestination {
                    album = knownAlbum
                } else {
                    let resolvedSong = try await songWithNavigationMetadata(song)
                    guard let resolvedAlbum = resolvedSong.albumDestination else {
                        throw SpotifyWebAPIError.invalidData("Spotify did not return an album for this track.")
                    }
                    album = resolvedAlbum
                }
                navigateFromSong(to: .album(album))
            } catch {
                errorMessage = error.userFacingMessage
                logError("Opening album for \(song.uri)", error)
            }
        }
    }

    func goToArtist(for song: SpotifySong) {
        Task {
            do {
                let artist: SpotifyArtist
                if let knownArtist = song.primaryArtist {
                    artist = knownArtist
                } else {
                    let resolvedSong = try await songWithNavigationMetadata(song)
                    guard let resolvedArtist = resolvedSong.primaryArtist else {
                        throw SpotifyWebAPIError.invalidData("Spotify did not return an artist for this track.")
                    }
                    artist = resolvedArtist
                }
                navigateFromSong(to: .artist(artist))
            } catch {
                errorMessage = error.userFacingMessage
                logError("Opening artist for \(song.uri)", error)
            }
        }
    }

    func consumeSongNavigationRequest() {
        songNavigationRequest = nil
    }

    private func songWithNavigationMetadata(_ song: SpotifySong) async throws -> SpotifySong {
        try await withLibraryAccessToken {
            try await webAPI.song(trackID: song.spotifyID, accessToken: $0)
        }
    }

    private func navigateFromSong(to destination: AppDestination) {
        #if os(iOS)
        songNavigationRequest = destination
        #else
        switch destination {
        case let .album(album):
            selectAlbum(album)
        case let .artist(artist):
            selectArtist(artist)
        default:
            break
        }
        #endif
    }

    func selectArtist(_ artist: SpotifyArtist) {
        destination = .artist(artist)
        selectedPlaylistID = nil
        artistAlbums = []
        errorMessage = nil
        artistLoadTask?.cancel()

        guard libraryAccessToken != nil else {
            return
        }

        isLoadingArtist = true
        artistLoadTask = Task {
            do {
                let loadedAlbums = try await withLibraryAccessToken {
                    try await webAPI.artistAlbums(artist, accessToken: $0)
                }
                guard !Task.isCancelled else {
                    return
                }
                artistAlbums = loadedAlbums
                isLoadingArtist = false
            } catch is CancellationError {
                isLoadingArtist = false
            } catch {
                isLoadingArtist = false
                errorMessage = error.userFacingMessage
                logError("Loading \(artist.name)", error)
            }
        }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = .empty
            isSearching = false
            return
        }
        guard !EasterEgg.matches(query) else {
            searchResults = .empty
            isSearching = false
            return
        }
        guard libraryAccessToken != nil else {
            errorMessage = "Connect your Spotify library to search the catalog."
            return
        }

        isSearching = true
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
                let results = try await withLibraryAccessToken {
                    try await webAPI.search(query: query, accessToken: $0)
                }
                guard !Task.isCancelled, searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                    return
                }
                searchResults = results
                isSearching = false
                await loadSavedStatuses(for: results.songs)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                isSearching = false
                errorMessage = error.userFacingMessage
                logError("Searching for \"\(query)\"", error)
            }
        }
    }

    func clearSearchPlaybackHistory() {
        searchPlaybackHistory = []
        persistSearchPlaybackHistory()
    }

    func isSaved(_ song: SpotifySong) -> Bool {
        savedTrackURIs.contains(song.uri)
    }

    func toggleSaved(_ song: SpotifySong) {
        guard hasFullLibraryAccess else {
            errorMessage = "Reconnect your library once to enable saved songs and playlist editing."
            return
        }
        guard libraryAccessToken != nil else {
            errorMessage = "Connect your Spotify library to save songs."
            return
        }

        let shouldSave = !savedTrackURIs.contains(song.uri)
        if shouldSave {
            savedTrackURIs.insert(song.uri)
            if !savedSongs.contains(where: { $0.uri == song.uri }) {
                savedSongs.insert(song, at: 0)
            }
        } else {
            savedTrackURIs.remove(song.uri)
            savedSongs.removeAll { $0.uri == song.uri }
        }

        Task {
            do {
                try await withLibraryAccessToken {
                    try await webAPI.setSaved(shouldSave, song: song, accessToken: $0)
                }
            } catch {
                if shouldSave {
                    savedTrackURIs.remove(song.uri)
                    savedSongs.removeAll { $0.uri == song.uri }
                } else {
                    savedTrackURIs.insert(song.uri)
                    savedSongs.insert(song, at: 0)
                }
                errorMessage = error.userFacingMessage
                logError("Updating saved songs", error)
            }
        }
    }

    @discardableResult
    func createPlaylist(name: String, description: String, isPublic: Bool) async -> Bool {
        guard hasFullLibraryAccess else {
            errorMessage = "Reconnect your library once to create and edit playlists."
            return false
        }
        guard libraryAccessToken != nil else {
            errorMessage = "Connect your Spotify library to create playlists."
            return false
        }

        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter a playlist name."
            return false
        }

        isCreatingPlaylist = true
        defer { isCreatingPlaylist = false }
        do {
            let playlist = try await withLibraryAccessToken {
                try await webAPI.createPlaylist(
                    name: name,
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    isPublic: isPublic,
                    accessToken: $0
                )
            }
            playlists.insert(playlist, at: 0)
            songs = []
            selectedPlaylistID = playlist.id
            destination = .playlist(playlist.id)
            return true
        } catch {
            errorMessage = error.userFacingMessage
            logError("Creating playlist", error)
            return false
        }
    }

    func add(_ song: SpotifySong, to playlist: SpotifyPlaylist) async {
        guard hasFullLibraryAccess else {
            errorMessage = "Reconnect your library once to create and edit playlists."
            return
        }
        guard libraryAccessToken != nil else {
            errorMessage = "Connect your Spotify library to edit playlists."
            return
        }
        do {
            try await withLibraryAccessToken {
                try await webAPI.add(song, to: playlist.id, accessToken: $0)
            }
            if selectedPlaylistID == playlist.id {
                songs.append(song)
            }
            adjustPlaylistSongCount(id: playlist.id, by: 1)
        } catch {
            errorMessage = error.userFacingMessage
            logError("Adding to \"\(playlist.name)\"", error)
        }
    }

    func removeFromSelectedPlaylist(_ song: SpotifySong) async {
        guard hasFullLibraryAccess else {
            errorMessage = "Reconnect your library once to create and edit playlists."
            return
        }
        guard
            let playlist = selectedPlaylist,
            playlist.canModify(currentUserID: profile?.id),
            libraryAccessToken != nil
        else {
            return
        }
        do {
            try await withLibraryAccessToken {
                try await webAPI.remove(song, from: playlist.id, accessToken: $0)
            }
            let oldCount = songs.count
            songs.removeAll { $0.uri == song.uri }
            adjustPlaylistSongCount(id: playlist.id, by: -(oldCount - songs.count))
        } catch {
            errorMessage = error.userFacingMessage
            logError("Removing from \"\(playlist.name)\"", error)
        }
    }

    @discardableResult
    func updateSelectedPlaylist(name: String, description: String, isPublic: Bool) async -> Bool {
        guard hasFullLibraryAccess else {
            errorMessage = "Reconnect your library once to create and edit playlists."
            return false
        }
        guard let playlist = selectedPlaylist, libraryAccessToken != nil else {
            return false
        }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter a playlist name."
            return false
        }
        do {
            try await withLibraryAccessToken {
                try await webAPI.updatePlaylist(
                    id: playlist.id,
                    name: name,
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    isPublic: isPublic,
                    accessToken: $0
                )
            }
            replacePlaylist(
                playlist,
                name: name,
                description: description,
                isPublic: isPublic
            )
            return true
        } catch {
            errorMessage = error.userFacingMessage
            logError("Updating playlist", error)
            return false
        }
    }

    func retryLoadingPlaylists() {
        Task {
            await loadPlaylists()
        }
    }

    private func completePlaybackLogin(with token: SpotifyOAuthToken) async throws {
        guard let refreshToken = token.refreshToken else {
            throw SpotifyOAuthError.missingRefreshToken
        }

        try SpotifyCredentialStore.savePlayback(
            StoredSpotifyCredentials(
                clientID: playbackClientID,
                refreshToken: refreshToken,
                authorizationVersion: SpotifyOAuthFlow.playbackAuthorizationVersion
            )
        )
        try await connectPlaybackCore(
            accessToken: token.accessToken,
            clientID: playbackClientID
        )

        playbackAccessToken = token.accessToken
        playbackAccessTokenExpirationDate = token.expirationDate
        self.refreshToken = refreshToken
        status = "Connected"
        isConnected = true
        refreshDownloadedTracks()
    }

    private func completeLibraryLogin(
        with token: SpotifyOAuthToken,
        clientID: String
    ) async throws {
        guard let refreshToken = token.refreshToken else {
            throw SpotifyOAuthError.missingRefreshToken
        }

        try SpotifyCredentialStore.saveLibrary(
            StoredSpotifyCredentials(
                clientID: clientID,
                refreshToken: refreshToken,
                authorizationVersion: SpotifyOAuthFlow.libraryAuthorizationVersion
            )
        )

        libraryClientID = clientID
        libraryAccessToken = token.accessToken
        libraryRefreshToken = refreshToken
        libraryAccessTokenExpirationDate = token.expirationDate
        libraryAuthorizationVersion = SpotifyOAuthFlow.libraryAuthorizationVersion
        libraryStatus = "Connected"
        isLibraryConnected = true
        libraryNeedsAuthorizationUpgrade = false
        await loadInitialLibrary()
    }

    private func loadInitialLibrary() async {
        guard libraryAccessToken != nil else {
            return
        }

        if !libraryNeedsAuthorizationUpgrade {
            do {
                profile = try await withLibraryAccessToken {
                    try await webAPI.profile(accessToken: $0)
                }
            } catch {
                logError("Loading Spotify profile", error)
            }
        }
        await loadPlaylists()
        if !libraryNeedsAuthorizationUpgrade {
            await loadHome()
        }
    }

    private func loadHome() async {
        guard !libraryNeedsAuthorizationUpgrade else {
            return
        }
        guard libraryAccessToken != nil else {
            return
        }
        isLoadingHome = true
        defer { isLoadingHome = false }

        do {
            recentlyPlayed = try await withLibraryAccessToken {
                try await webAPI.recentlyPlayed(accessToken: $0)
            }
            await loadSavedStatuses(for: recentlyPlayed)
        } catch {
            logError("Loading recently played songs", error)
        }
    }

    private func loadSavedSongs() async {
        guard !libraryNeedsAuthorizationUpgrade else {
            errorMessage = "Reconnect your library once to enable saved songs and playlist editing."
            return
        }
        guard libraryAccessToken != nil else {
            return
        }
        isLoadingSavedSongs = true
        defer { isLoadingSavedSongs = false }

        do {
            savedSongs = try await withLibraryAccessToken {
                try await webAPI.savedSongs(accessToken: $0)
            }
            savedTrackURIs.formUnion(savedSongs.map(\.uri))
        } catch {
            errorMessage = error.userFacingMessage
            logError("Loading saved songs", error)
        }
    }

    private func loadSavedStatuses(for songs: [SpotifySong]) async {
        guard !libraryNeedsAuthorizationUpgrade,
              libraryAccessToken != nil,
              !songs.isEmpty else {
            return
        }
        do {
            let statuses = try await withLibraryAccessToken {
                try await webAPI.savedStatuses(for: songs, accessToken: $0)
            }
            for (uri, isSaved) in statuses {
                if isSaved {
                    savedTrackURIs.insert(uri)
                } else {
                    savedTrackURIs.remove(uri)
                }
            }
        } catch {
            logError("Checking saved songs", error)
        }
    }

    private func loadPlaylists() async {
        guard libraryAccessToken != nil else {
            return
        }

        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }

        do {
            playlists = try await withLibraryAccessToken {
                try await webAPI.playlists(accessToken: $0)
            }
            libraryStatus = "Connected"
        } catch {
            errorMessage = error.userFacingMessage
            logError("Loading playlists", error)
        }
    }

    private func restorePlaybackSession(using credentials: StoredSpotifyCredentials) async {

        do {
            let token = try await oauthFlow.refreshAccessToken(
                refreshToken: credentials.refreshToken,
                clientID: credentials.clientID
            )
            let nextRefreshToken = token.refreshToken ?? credentials.refreshToken

            try SpotifyCredentialStore.savePlayback(
                StoredSpotifyCredentials(
                    clientID: credentials.clientID,
                    refreshToken: nextRefreshToken,
                    authorizationVersion: SpotifyOAuthFlow.playbackAuthorizationVersion
                )
            )

            try await connectPlaybackCore(
                accessToken: token.accessToken,
                clientID: credentials.clientID
            )
            playbackAccessToken = token.accessToken
            playbackAccessTokenExpirationDate = token.expirationDate
            refreshToken = nextRefreshToken
            status = "Connected"
            isConnected = true
            errorMessage = nil
            refreshDownloadedTracks()
        } catch {
            status = "Disconnected"
            isConnected = false
            errorMessage = "Could not restore playback login: \(error.userFacingMessage)"
            logError("Restoring playback login", error)
        }
    }

    private func connectPlaybackCore(
        accessToken: String,
        clientID: String
    ) async throws {
        try systemMediaSession.prepareForPlayback()
        try await core.connect(accessToken, clientID)
    }

    private func restoreLibrarySession(using credentials: StoredSpotifyCredentials) async {

        do {
            let token = try await oauthFlow.refreshAccessToken(
                refreshToken: credentials.refreshToken,
                clientID: credentials.clientID
            )
            let nextRefreshToken = token.refreshToken ?? credentials.refreshToken

            try SpotifyCredentialStore.saveLibrary(
                StoredSpotifyCredentials(
                    clientID: credentials.clientID,
                    refreshToken: nextRefreshToken,
                    authorizationVersion: credentials.authorizationVersion ?? 0
                )
            )

            libraryAccessToken = token.accessToken
            libraryRefreshToken = nextRefreshToken
            libraryAccessTokenExpirationDate = token.expirationDate
            libraryAuthorizationVersion = credentials.authorizationVersion ?? 0
            libraryStatus = libraryNeedsAuthorizationUpgrade
                ? "Reconnect for full access"
                : "Connected"
            isLibraryConnected = true
            errorMessage = nil
            await loadInitialLibrary()
        } catch {
            libraryStatus = "Not connected"
            isLibraryConnected = false
            errorMessage = "Could not restore playlist login: \(error.userFacingMessage)"
            logError("Restoring playlist login", error)
        }
    }

    private func logError(_ context: String, _ error: Error) {
        errorMessage = error.userFacingMessage
    }

    private func withLibraryAccessToken<Value>(
        _ operation: (String) async throws -> Value
    ) async throws -> Value {
        guard var accessToken = libraryAccessToken else {
            throw LibrarySessionError.notConnected
        }

        if let expirationDate = libraryAccessTokenExpirationDate,
           expirationDate <= Date().addingTimeInterval(60) {
            accessToken = try await refreshLibraryAccessToken(reason: "access token nearing expiry")
        }

        do {
            return try await operation(accessToken)
        } catch let error as SpotifyWebAPIError where error.shouldRefreshAccessToken {

            let retryToken: String
            if let currentToken = libraryAccessToken, currentToken != accessToken {
                retryToken = currentToken
            } else {
                retryToken = try await refreshLibraryAccessToken(reason: "Web API returned HTTP 401")
            }
            return try await operation(retryToken)
        }
    }

    private func refreshLibraryAccessToken(reason: String) async throws -> String {
        if let libraryTokenRefreshTask {
            return try await libraryTokenRefreshTask.value.accessToken
        }

        guard
            let libraryRefreshToken,
            !libraryClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw LibrarySessionError.missingRefreshToken
        }

        let clientID = libraryClientID
        let refreshTask = Task {
            try await oauthFlow.refreshAccessToken(
                refreshToken: libraryRefreshToken,
                clientID: clientID
            )
        }
        libraryTokenRefreshTask = refreshTask
        defer { libraryTokenRefreshTask = nil }

        do {
            let token = try await refreshTask.value
            let nextRefreshToken = token.refreshToken ?? libraryRefreshToken
            try SpotifyCredentialStore.saveLibrary(
                StoredSpotifyCredentials(
                    clientID: clientID,
                    refreshToken: nextRefreshToken,
                    authorizationVersion: libraryAuthorizationVersion
                )
            )

            libraryAccessToken = token.accessToken
            self.libraryRefreshToken = nextRefreshToken
            libraryAccessTokenExpirationDate = token.expirationDate
            libraryStatus = libraryNeedsAuthorizationUpgrade
                ? "Reconnect for full access"
                : "Connected"
            isLibraryConnected = true
            return token.accessToken
        } catch {
            throw error
        }
    }

    private func adjustPlaylistSongCount(id: String, by delta: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else {
            return
        }
        let playlist = playlists[index]
        playlists[index] = SpotifyPlaylist(
            id: playlist.id,
            name: playlist.name,
            description: playlist.description,
            songCount: max(playlist.songCount + delta, 0),
            artworkURL: playlist.artworkURL,
            ownerID: playlist.ownerID,
            ownerName: playlist.ownerName,
            isPublic: playlist.isPublic,
            isCollaborative: playlist.isCollaborative,
            uri: playlist.uri
        )
    }

    private func replacePlaylist(
        _ playlist: SpotifyPlaylist,
        name: String,
        description: String,
        isPublic: Bool
    ) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else {
            return
        }
        playlists[index] = SpotifyPlaylist(
            id: playlist.id,
            name: name,
            description: description,
            songCount: playlist.songCount,
            artworkURL: playlist.artworkURL,
            ownerID: playlist.ownerID,
            ownerName: playlist.ownerName,
            isPublic: isPublic,
            isCollaborative: playlist.isCollaborative,
            uri: playlist.uri
        )
    }

    private var activePlaybackQueue: [SpotifySong] {
        if isShuffleEnabled, !shuffledPlaybackQueue.isEmpty {
            return shuffledPlaybackQueue
        }
        return playbackQueue
    }

    private var currentQueueIndex: [SpotifySong].Index? {
        guard let currentSong else {
            return nil
        }
        return activePlaybackQueue.firstIndex(where: { $0.id == currentSong.id })
    }

    private func rebuildShuffledPlaybackQueue(startingWith song: SpotifySong?) {
        var remainingSongs = playbackQueue
        guard
            let song,
            let currentIndex = remainingSongs.firstIndex(where: { $0.id == song.id })
        else {
            shuffledPlaybackQueue = remainingSongs.shuffled()
            return
        }

        let currentSong = remainingSongs.remove(at: currentIndex)
        shuffledPlaybackQueue = [currentSong] + remainingSongs.shuffled()
    }

    private var hasFullLibraryAccess: Bool {
        isLibraryConnected && !libraryNeedsAuthorizationUpgrade
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

private enum LibrarySessionError: LocalizedError {
    case notConnected
    case missingRefreshToken

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Connect your Spotify library to continue."
        case .missingRefreshToken:
            "Your saved Spotify library login cannot be refreshed. Reconnect it once to continue."
        }
    }
}

private extension Error {
    var userFacingMessage: String {
        if let rustError = self as? RustString {
            return rustError.toString()
        }

        return localizedDescription
    }
}
