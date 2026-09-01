#if os(iOS)
import SwiftUI

@main
@MainActor
struct SwiftifyIOSApp: App {
    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .tint(MusicStyle.accent)
        }
    }
}

private enum IOSTab: Hashable {
    case home
    case search
    case library
    case settings
}

private enum IOSRoute: Hashable {
    case playlist(SpotifyPlaylist)
    case album(SpotifyAlbum)
    case artist(SpotifyArtist)
    case savedSongs
    case allPlaylists
    case pinnedPlaylists
}

@MainActor
private struct IOSRootView: View {
    @StateObject private var player = PlayerModel()
    @State private var selectedTab: IOSTab = .home
    @State private var isShowingNowPlaying = false
    @State private var isShowingCreatePlaylist = false
    @State private var homePath: [IOSRoute] = []
    @State private var searchPath: [IOSRoute] = []
    @State private var libraryPath: [IOSRoute] = []
    @AppStorage(AppPreferences.visualizersEnabledKey) private var visualizersEnabled = true

    var body: some View {
        Group {
            if player.isEvaluatingStoredLogin {
                SpotifyStartupLoadingView()
            } else if player.isLibraryConnected {
                tabs
            } else {
                IOSConnectView(player: player)
            }
        }
        .sheet(isPresented: $player.isShowingLogin) {
            if let authorizationURL = player.authorizationURL {
                SpotifyLoginSheet(
                    authorizationURL: authorizationURL,
                    onCallback: { callbackURL in
                        Task { await player.completeLogin(callbackURL: callbackURL) }
                    },
                    onCancel: player.cancelLogin
                )
            }
        }
        .sheet(isPresented: $isShowingCreatePlaylist) {
            IOSPlaylistEditor(player: player)
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $isShowingNowPlaying) {
            IOSNowPlayingView(player: player)
        }
        .alert("Swiftify", isPresented: errorPresented) {
            Button("OK") { player.errorMessage = nil }
        } message: {
            Text(player.errorMessage ?? "")
        }
        .onChange(of: visualizersEnabled, initial: true) { _, isEnabled in
            player.setVisualizersEnabled(isEnabled)
        }
        .onChange(of: player.songNavigationRequest) { _, request in
            handleSongNavigationRequest(request)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { player.errorMessage != nil },
            set: { isPresented in
                if !isPresented { player.errorMessage = nil }
            }
        )
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.1, *) {
            tabContent
                .tabViewBottomAccessory(
                    isEnabled: player.currentSong != nil && !isShowingNowPlaying
                ) {
                    IOSMiniPlayer(player: player) {
                        isShowingNowPlaying = true
                    }
                }
        } else {
            tabContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if player.currentSong != nil && !isShowingNowPlaying {
                        IOSMiniPlayer(player: player) {
                            isShowingNowPlaying = true
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                    }
                }
        }
    }

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            IOSNavigationRoot(
                player: player,
                root: .home,
                path: $homePath,
                createPlaylist: showPlaylistEditor
            )
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(IOSTab.home)

            IOSNavigationRoot(
                player: player,
                root: .search,
                path: $searchPath,
                createPlaylist: showPlaylistEditor
            )
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(IOSTab.search)

            IOSNavigationRoot(
                player: player,
                root: .library,
                path: $libraryPath,
                createPlaylist: showPlaylistEditor
            )
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(IOSTab.library)

            IOSSettingsView(player: player)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(IOSTab.settings)
        }
    }

    private func showPlaylistEditor() {
        isShowingCreatePlaylist = true
    }

    private func handleSongNavigationRequest(_ destination: AppDestination?) {
        guard let destination else {
            return
        }

        let route: IOSRoute
        switch destination {
        case let .album(album):
            route = .album(album)
        case let .artist(artist):
            route = .artist(artist)
        default:
            player.consumeSongNavigationRequest()
            return
        }

        isShowingNowPlaying = false
        selectedTab = .home
        player.consumeSongNavigationRequest()
        Task { @MainActor in
            await Task.yield()
            homePath.append(route)
        }
    }
}

private enum IOSRootDestination {
    case home
    case search
    case library
}

private struct IOSNavigationRoot: View {
    @ObservedObject var player: PlayerModel
    let root: IOSRootDestination
    @Binding var path: [IOSRoute]
    let createPlaylist: () -> Void

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch root {
                case .home:
                    IOSHomeView(player: player)
                case .search:
                    IOSSearchView(player: player)
                case .library:
                    IOSLibraryView(player: player, createPlaylist: createPlaylist)
                }
            }
            .navigationDestination(for: IOSRoute.self) { route in
                switch route {
                case let .playlist(playlist):
                    IOSPlaylistDetailView(player: player, playlist: playlist)
                case let .album(album):
                    IOSAlbumDetailView(player: player, album: album)
                case let .artist(artist):
                    IOSArtistDetailView(player: player, artist: artist)
                case .savedSongs:
                    IOSSavedSongsView(player: player)
                case .allPlaylists:
                    IOSPlaylistListView(player: player, playlists: player.playlists)
                case .pinnedPlaylists:
                    IOSPlaylistListView(player: player, playlists: player.pinnedPlaylists)
                }
            }
        }
    }
}

private struct IOSConnectView: View {
    @ObservedObject var player: PlayerModel
    private let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(MusicStyle.accent)
                        .symbolEffect(.pulse)

                    Text("Swiftify")
                        .font(.largeTitle.bold())

                    Text("Swiftify needs a Client ID from your own Spotify developer app. You only have to set this up once.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 14) {
                        setupStep(
                            number: 1,
                            title: "Create a Spotify app",
                            detail: "Open the Spotify Developer Dashboard, choose Create app, and select Web API if asked."
                        )

                        Link(destination: dashboardURL) {
                            Label("Open Spotify Developer Dashboard", systemImage: "arrow.up.right.square")
                        }
                        .padding(.leading, 38)

                        setupStep(
                            number: 2,
                            title: "Add the redirect URI",
                            detail: "In the app settings, add this exact address under Redirect URIs, then save:"
                        )

                        Text(SpotifyOAuthFlow.redirectURI.absoluteString)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(10)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                            .padding(.leading, 38)

                        setupStep(
                            number: 3,
                            title: "Paste your Client ID",
                            detail: "Copy the Client ID from the app settings. You do not need the Client Secret."
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("Spotify Client ID", text: $player.libraryClientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    Button("Connect Library", action: player.beginLibraryLogin)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(player.libraryClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Connect Playback", action: player.beginPlaybackLogin)
                        .buttonStyle(.glass)
                        .controlSize(.large)

                    Text("Connect Library first, then Connect Playback so Swiftify can play music.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .background {
                RadialGradient(
                    colors: [MusicStyle.accent.opacity(0.22), .clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: 520
                )
                .ignoresSafeArea()
            }
        }
    }

    private func setupStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(MusicStyle.accent, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct IOSHomeView: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if player.isLoadingHome && player.recentlyPlayed.isEmpty {
                    ProgressView("Loading your music…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    if !player.playlists.isEmpty {
                        IOSHorizontalShelf(title: "Top Picks") {
                            ForEach(player.playlists.prefix(8)) { playlist in
                                NavigationLink(value: IOSRoute.playlist(playlist)) {
                                    IOSMediaCard(
                                        title: playlist.name,
                                        subtitle: playlist.ownerDisplayName,
                                        artworkURL: playlist.artworkURL
                                    )
                                }
                            }
                        }
                    }

                    if !player.recentlyPlayed.isEmpty {
                        IOSHorizontalShelf(title: "Recently Played") {
                            ForEach(player.recentlyPlayed) { song in
                                Button {
                                    player.play(song, in: player.recentlyPlayed)
                                } label: {
                                    IOSMediaCard(
                                        title: song.name,
                                        subtitle: song.artists,
                                        artworkURL: song.artworkURL
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.bottom, 90)
        }
        .navigationTitle("Home")
        .task { player.showHome() }
    }
}

private struct IOSSearchView: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if player.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    IOSSearchLandingView(player: player)
                } else if EasterEgg.matches(player.searchQuery) {
                    VStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 46))
                            .foregroundStyle(MusicStyle.accent)
                        Text(EasterEgg.phrase)
                            .font(.title.bold())
                        Text("You found it.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 380)
                } else if player.isSearching {
                    ProgressView("Searching Spotify…")
                        .frame(maxWidth: .infinity, minHeight: 380)
                } else if player.searchResults.isEmpty {
                    ContentUnavailableView.search(text: player.searchQuery)
                        .frame(minHeight: 380)
                } else {
                    if !player.searchResults.songs.isEmpty {
                        IOSSectionTitle("Songs")
                        IOSSongList(
                            player: player,
                            songs: player.searchResults.songs,
                            allowsPlaylistRemoval: false,
                            recordsSearchPlayback: true
                        )
                    }

                    if !player.searchResults.albums.isEmpty {
                        IOSHorizontalShelf(title: "Albums") {
                            ForEach(player.searchResults.albums) { album in
                                NavigationLink(value: IOSRoute.album(album)) {
                                    IOSMediaCard(
                                        title: album.name,
                                        subtitle: album.artists,
                                        artworkURL: album.artworkURL
                                    )
                                }
                            }
                        }
                    }

                    if !player.searchResults.artists.isEmpty {
                        IOSHorizontalShelf(title: "Artists") {
                            ForEach(player.searchResults.artists) { artist in
                                NavigationLink(value: IOSRoute.artist(artist)) {
                                    IOSMediaCard(
                                        title: artist.name,
                                        subtitle: "Artist",
                                        artworkURL: artist.artworkURL,
                                        isCircular: true
                                    )
                                }
                            }
                        }
                    }

                    if !player.searchResults.playlists.isEmpty {
                        IOSHorizontalShelf(title: "Playlists") {
                            ForEach(player.searchResults.playlists) { playlist in
                                NavigationLink(value: IOSRoute.playlist(playlist)) {
                                    IOSMediaCard(
                                        title: playlist.name,
                                        subtitle: playlist.ownerDisplayName,
                                        artworkURL: playlist.artworkURL
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $player.searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Spotify"
        )
        .onChange(of: player.searchQuery) { _, _ in player.scheduleSearch() }
    }
}

private struct IOSSearchLandingView: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !player.searchPlaybackHistory.isEmpty {
                HStack {
                    Text("Recent searches")
                        .font(.title2.bold())
                    Spacer()
                    Button("Clear", action: player.clearSearchPlaybackHistory)
                        .font(.callout)
                }

                IOSSongList(
                    player: player,
                    songs: Array(player.searchPlaybackHistory.prefix(8)),
                    allowsPlaylistRemoval: false,
                    recordsSearchPlayback: true
                )
            }

            ContentUnavailableView(
                "Search Spotify",
                systemImage: "magnifyingglass",
                description: Text("Find songs, albums, artists, and playlists.")
            )
            .frame(maxWidth: .infinity, minHeight: 260)
        }
    }
}

private struct IOSLibraryView: View {
    @ObservedObject var player: PlayerModel
    let createPlaylist: () -> Void

    var body: some View {
        List {
            Section {
                NavigationLink(value: IOSRoute.savedSongs) {
                    Label("Songs", systemImage: "music.note")
                }
                NavigationLink(value: IOSRoute.allPlaylists) {
                    Label("All Playlists", systemImage: "square.grid.2x2.fill")
                }
                NavigationLink(value: IOSRoute.pinnedPlaylists) {
                    Label("Pinned Playlists", systemImage: "pin.fill")
                }
            }

            Section("Playlists") {
                ForEach(player.playlists) { playlist in
                    NavigationLink(value: IOSRoute.playlist(playlist)) {
                        HStack(spacing: 12) {
                            ArtworkView(url: playlist.artworkURL, size: 48, cornerRadius: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name).lineLimit(1)
                                Text("\(playlist.songCount) songs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            player.togglePinnedPlaylist(playlist)
                        } label: {
                            Label(
                                player.isPlaylistPinned(playlist) ? "Unpin" : "Pin",
                                systemImage: player.isPlaylistPinned(playlist) ? "pin.slash" : "pin"
                            )
                        }
                        .tint(MusicStyle.accent)
                    }
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: createPlaylist) {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

private struct IOSPlaylistListView: View {
    @ObservedObject var player: PlayerModel
    let playlists: [SpotifyPlaylist]

    var body: some View {
        Group {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Your playlists will appear here.")
                )
            } else {
                List(playlists) { playlist in
                    NavigationLink(value: IOSRoute.playlist(playlist)) {
                        HStack(spacing: 12) {
                            ArtworkView(url: playlist.artworkURL, size: 54, cornerRadius: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(playlist.name).lineLimit(1)
                                Text("\(playlist.songCount) songs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Playlists")
    }
}

private struct IOSPlaylistDetailView: View {
    @ObservedObject var player: PlayerModel
    let playlist: SpotifyPlaylist
    @State private var isShowingEditor = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                VStack(spacing: 14) {
                    ArtworkView(url: playlist.artworkURL, size: 220, cornerRadius: 16)
                        .artworkBackdropGlow(colors: player.spectrum.gradientColors, intensity: 0.28)

                    Text(playlist.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(playlist.ownerDisplayName)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 14) {
                        Button {
                            guard let song = player.songs.randomElement() else { return }
                            if !player.isShuffleEnabled { player.toggleShuffle() }
                            player.play(song, in: player.songs)
                        } label: {
                            Image(systemName: "shuffle")
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.glass)

                        Button {
                            guard let song = player.songs.first else { return }
                            player.play(song, in: player.songs)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.headline)
                                .frame(width: 104, height: 48)
                        }
                        .buttonStyle(.glassProminent)

                        Button {
                            player.downloadPlaylist(playlist)
                        } label: {
                            Image(systemName: "arrow.down")
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.glass)
                    }
                    .disabled(player.songs.isEmpty)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

                if player.isLoadingSongs {
                    ProgressView("Loading songs…")
                        .padding(.top, 40)
                } else {
                    IOSSongList(
                        player: player,
                        songs: player.songs,
                        allowsPlaylistRemoval: playlist.canModify(currentUserID: player.profile?.id)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if playlist.canModify(currentUserID: player.profile?.id) {
                    Button {
                        isShowingEditor = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
                Button {
                    player.togglePinnedPlaylist(playlist)
                } label: {
                    Image(systemName: player.isPlaylistPinned(playlist) ? "pin.fill" : "pin")
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            IOSPlaylistEditor(player: player, mode: .edit(playlist))
                .presentationDetents([.medium])
        }
        .task(id: playlist.id) { player.selectPlaylist(playlist) }
    }
}

private struct IOSAlbumDetailView: View {
    @ObservedObject var player: PlayerModel
    let album: SpotifyAlbum

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ArtworkView(url: album.artworkURL, size: 230, cornerRadius: 16)
                    .artworkBackdropGlow(colors: player.spectrum.gradientColors, intensity: 0.28)
                Text(album.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(album.artists)
                    .foregroundStyle(.secondary)

                IOSSongList(
                    player: player,
                    songs: player.albumSongs,
                    allowsPlaylistRemoval: false
                )
            }
            .padding(16)
            .padding(.bottom, 90)
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: album.id) { player.selectAlbum(album) }
    }
}

private struct IOSArtistDetailView: View {
    @ObservedObject var player: PlayerModel
    let artist: SpotifyArtist

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 12) {
                    ArtworkView(url: artist.artworkURL, size: 230, cornerRadius: 115)
                        .shadow(color: .black.opacity(0.22), radius: 20, y: 9)
                    Text(artist.name)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                if player.isLoadingArtist {
                    ProgressView("Loading albums…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if player.artistAlbums.isEmpty {
                    ContentUnavailableView(
                        "No Albums Found",
                        systemImage: "music.note",
                        description: Text("Spotify did not return any releases for this artist.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    IOSHorizontalShelf(title: "Albums & Singles") {
                        ForEach(player.artistAlbums) { album in
                            NavigationLink(value: IOSRoute.album(album)) {
                                IOSMediaCard(
                                    title: album.name,
                                    subtitle: album.releaseDate ?? album.artists,
                                    artworkURL: album.artworkURL
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: artist.id) { player.selectArtist(artist) }
    }
}

private struct IOSSavedSongsView: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        Group {
            if player.isLoadingSavedSongs {
                ProgressView("Loading songs…")
            } else if player.savedSongs.isEmpty {
                ContentUnavailableView(
                    "No Saved Songs",
                    systemImage: "star",
                    description: Text("Save songs to find them here.")
                )
            } else {
                ScrollView {
                    IOSSongList(
                        player: player,
                        songs: player.savedSongs,
                        allowsPlaylistRemoval: false
                    )
                    .padding(16)
                    .padding(.bottom, 90)
                }
            }
        }
        .navigationTitle("Songs")
        .task { player.showSavedSongs() }
    }
}

private struct IOSSongList: View {
    @ObservedObject var player: PlayerModel
    let songs: [SpotifySong]
    let allowsPlaylistRemoval: Bool
    var recordsSearchPlayback = false

    var body: some View {
        LazyVStack(spacing: 2) {
            ForEach(songs) { song in
                HStack(spacing: 11) {
                    Button {
                        if recordsSearchPlayback {
                            player.playFromSearch(song, in: songs)
                        } else {
                            player.play(song, in: songs)
                        }
                    } label: {
                        HStack(spacing: 11) {
                            ZStack {
                                ArtworkView(url: song.artworkURL, size: 48, cornerRadius: 7)
                                if player.visualizersEnabled, player.currentSong?.id == song.id {
                                    Color.black.opacity(0.32)
                                        .clipShape(.rect(cornerRadius: 7))
                                    AudioSpectrumView(
                                        spectrum: player.spectrum,
                                        isActive: player.isPlaying,
                                        width: 30,
                                        height: 30
                                    )
                                }
                            }
                            .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.name)
                                    .font(.body.weight(player.currentSong?.id == song.id ? .semibold : .regular))
                                    .foregroundStyle(player.currentSong?.id == song.id ? MusicStyle.accent : .primary)
                                    .lineLimit(1)
                                Text(song.artists)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    SongOptionsMenu(
                        player: player,
                        song: song,
                        allowsPlaylistRemoval: allowsPlaylistRemoval,
                        labelWidth: 32,
                        labelHeight: 44
                    )
                }
                .padding(.vertical, 5)

                Divider().padding(.leading, 59)
            }
        }
    }
}

private struct IOSMiniPlayer: View {
    @ObservedObject var player: PlayerModel
    let showNowPlaying: () -> Void

    var body: some View {
        ZStack {
            Button(action: showNowPlaying) {
                Color.clear
                    .contentShape(.rect)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                ArtworkView(url: player.currentSong?.artworkURL, size: 38, cornerRadius: 7)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentSong?.name ?? "Not Playing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(player.currentSong?.artists ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .allowsHitTesting(false)

                Spacer(minLength: 2)

                if let song = player.currentSong {
                    SongOptionsMenu(
                        player: player,
                        song: song,
                        labelWidth: 30,
                        labelHeight: 38
                    )
                }

                Button(action: player.togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.08), value: player.isPlaying)
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 32, height: 38)
                }
                .buttonStyle(.plain)

                Button(action: player.skipForward) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 38)
                }
                .buttonStyle(.plain)
                .disabled(!player.canSkipForward)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum IOSNowPlayingPage: String, CaseIterable, Identifiable {
    case lyrics = "Lyrics"
    case queue = "Queue"
    var id: Self { self }
}

private struct IOSNowPlayingView: View {
    @ObservedObject var player: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var page: IOSNowPlayingPage = .lyrics
    @State private var scrubPosition: Double?
    @State private var isShowingEasterEgg = false
    @State private var fullscreenScrollOffset: CGFloat = 0
    @AppStorage(AppPreferences.visualizersEnabledKey) private var visualizersEnabled = true

    var body: some View {
        GeometryReader { geometry in
            let artworkSize = min(
                geometry.size.width - 48,
                340
            )
            let isCompactLyricsMessage = page == .lyrics
                && !player.isLoadingLyrics
                && player.lyrics == nil
            let pageHeight = isCompactLyricsMessage
                ? CGFloat(190)
                : max(440, geometry.size.height * 0.72)

            ZStack {
                IOSArtworkBackdrop(colors: player.spectrum.gradientColors)

                ScrollView {
                    LazyVStack(spacing: 18) {
                        Capsule(style: .continuous)
                            .fill(.secondary.opacity(0.72))
                            .frame(width: 38, height: 5)

                        ZStack {
                            ArtworkView(
                                url: player.currentSong?.artworkURL,
                                size: artworkSize,
                                cornerRadius: 22
                            )
                            if isShowingEasterEgg { EasterEggHUD() }
                        }
                        .onLongPressGesture {
                            withAnimation(.snappy) { isShowingEasterEgg.toggle() }
                        }
                        .artworkBackdropGlow(
                            colors: player.spectrum.gradientColors,
                            intensity: 0.5,
                            radius: 42
                        )

                        VStack(spacing: 3) {
                            Text(player.currentSong?.name ?? "Not Playing")
                                .font(.title3.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: artworkSize)
                                .frame(minHeight: 52, alignment: .center)

                            HStack(spacing: 4) {
                                Text(player.currentSong?.artists ?? "")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                if let song = player.currentSong {
                                    SongOptionsMenu(
                                        player: player,
                                        song: song,
                                        labelWidth: 30,
                                        labelHeight: 30,
                                        labelForegroundColor: .secondary,
                                        onNavigate: { dismiss() }
                                    )
                                }
                            }
                        }

                        IOSPlaybackSlider(
                            player: player,
                            scrubPosition: $scrubPosition
                        )

                        playbackControls

                        if visualizersEnabled {
                            IOSImmersiveSpectrum(
                                spectrum: player.spectrum,
                                isActive: player.isPlaying
                            )
                            .frame(height: 160)
                        }

                        Picker("Now Playing", selection: $page) {
                            ForEach(IOSNowPlayingPage.allCases) { page in
                                Text(page.rawValue).tag(page)
                            }
                        }
                        .pickerStyle(.segmented)

                        Group {
                            switch page {
                            case .lyrics:
                                IOSLyricsView(player: player)
                            case .queue:
                                IOSQueueView(player: player)
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: pageHeight,
                            maxHeight: pageHeight,
                            alignment: .top
                        )
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { scrollGeometry in
                    scrollGeometry.contentOffset.y + scrollGeometry.contentInsets.top
                } action: { _, newOffset in
                    fullscreenScrollOffset = newOffset
                }
                .simultaneousGesture(dismissGesture)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var playbackControls: some View {
        HStack(spacing: 30) {
            Button(action: player.toggleShuffle) {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.isShuffleEnabled ? MusicStyle.accent : .primary)
            }
            Button(action: player.skipBackward) {
                Image(systemName: "backward.fill")
            }
            .disabled(!player.canSkipBackward)

            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.08), value: player.isPlaying)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 60, height: 60)
                    .background(.white, in: .circle)
            }

            Button(action: player.skipForward) {
                Image(systemName: "forward.fill")
            }
            .disabled(!player.canSkipForward)

            Button(action: player.cycleRepeatMode) {
                Image(systemName: player.repeatMode.symbolName)
                    .foregroundStyle(player.repeatMode == .off ? .primary : MusicStyle.accent)
            }
        }
        .font(.system(size: 20, weight: .semibold))
        .buttonStyle(.plain)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onEnded { value in
                let vertical = value.translation.height
                let predicted = value.predictedEndTranslation.height
                let horizontal = abs(value.translation.width)

                if fullscreenScrollOffset <= 1,
                   vertical > horizontal * 1.15,
                   max(vertical, predicted) > 150 {
                    dismiss()
                }
            }
    }
}

private struct IOSPlaybackSlider: View {
    @ObservedObject var player: PlayerModel
    @Binding var scrubPosition: Double?

    var body: some View {
        VStack(spacing: 3) {
            Slider(
                value: Binding(
                    get: { scrubPosition ?? Double(player.playbackPositionMs) },
                    set: { scrubPosition = $0 }
                ),
                in: 0 ... max(Double(player.playbackDurationMs), 1),
                onEditingChanged: { editing in
                    guard !editing, let scrubPosition else { return }
                    player.seek(to: UInt32(scrubPosition.rounded()))
                    self.scrubPosition = nil
                }
            )
            .tint(player.spectrum.gradientColors.first ?? MusicStyle.accent)

            HStack {
                Text(iosTime(scrubPosition ?? Double(player.playbackPositionMs)))
                Spacer()
                Text("−\(iosTime(max(Double(player.playbackDurationMs) - (scrubPosition ?? Double(player.playbackPositionMs)), 0)))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

private struct IOSLyricsView: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        Group {
            if player.isLoadingLyrics {
                ProgressView("Loading lyrics…")
            } else if let lyrics = player.lyrics {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(lyrics.lines) { line in
                                let isActive = !lyrics.isSynchronized || player.activeLyricLineID == line.id
                                Text(line.words.isEmpty ? "♪" : line.words)
                                    .font(.title3.bold())
                                    .fixedSize(horizontal: false, vertical: true)
                                    .opacity(isActive ? 1 : 0.36)
                                    .id(line.id)
                                    .onTapGesture {
                                        guard lyrics.isSynchronized else { return }
                                        player.seek(to: line.startTimeMs)
                                    }
                            }

                            Text("Lyrics provided by \(lyrics.provider)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: player.activeLyricLineID) { _, lineID in
                        guard let lineID else { return }
                        withAnimation(.smooth(duration: 0.42)) {
                            proxy.scrollTo(lineID, anchor: .center)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Lyrics Unavailable",
                    systemImage: "quote.bubble",
                    description: Text(player.lyricsMessage ?? EasterEgg.phrase)
                )
            }
        }
    }
}

private struct IOSQueueView: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let song = player.currentSong {
                    IOSQueueRow(song: song, isCurrent: true) {}
                }
                if player.upNextSongs.isEmpty {
                    ContentUnavailableView(
                        "Queue Empty",
                        systemImage: "text.line.last.and.arrowtriangle.forward",
                        description: Text(EasterEgg.phrase)
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(player.upNextSongs) { song in
                        IOSQueueRow(song: song, isCurrent: false) {
                            player.playFromQueue(song)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}

private struct IOSQueueRow: View {
    let song: SpotifySong
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ArtworkView(url: song.artworkURL, size: 48, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.name).fontWeight(isCurrent ? .semibold : .regular)
                    Text(song.artists).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }
}

private struct IOSImmersiveSpectrum: View {
    @ObservedObject var spectrum: AudioSpectrumModel
    let isActive: Bool

    var body: some View {
        GeometryReader { geometry in
            let oneSide = bassExpandedSpectrumLevels(
                spectrum.levels,
                perSideCount: 18
            )
            let levels = oneSide + oneSide.reversed()
            let spacing: CGFloat = 2.5
            let width = max(1.5, (geometry.size.width - spacing * CGFloat(levels.count - 1)) / CGFloat(max(levels.count, 1)))
            let bars = HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .frame(width: width, height: max(3, geometry.size.height * (0.04 + level * 0.96)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            LinearGradient(
                colors: spectrum.gradientColors,
                startPoint: .leading,
                endPoint: .trailing
            )
            .mask { bars }
            .shadow(
                color: spectrum.gradientColors.first?.opacity(0.48) ?? .clear,
                radius: 5
            )
            .opacity(isActive ? 1 : 0.4)
        }
        .animation(.smooth(duration: 0.14), value: spectrum.levels)
    }
}

private struct IOSArtworkBackdrop: View {
    let colors: [Color]

    var body: some View {
        let palette = colors.isEmpty ? [MusicStyle.accent, MusicStyle.deepGreen] : colors
        ZStack {
            Color.black
            RadialGradient(
                colors: [palette[0].opacity(0.48), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 620
            )
            RadialGradient(
                colors: [palette[palette.count > 1 ? 1 : 0].opacity(0.38), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 680
            )
            Color.black.opacity(0.32)
        }
        .ignoresSafeArea()
    }
}

private struct IOSSettingsView: View {
    @ObservedObject var player: PlayerModel
    @AppStorage(AppPreferences.visualizersEnabledKey) private var visualizersEnabled = true
    @State private var isShowingEasterEgg = false

    var body: some View {
        NavigationStack {
            Form {
                if let profile = player.profile {
                    Section {
                        HStack(spacing: 12) {
                            ArtworkView(url: profile.artworkURL, size: 54, cornerRadius: 27)
                            VStack(alignment: .leading) {
                                Text(profile.displayName).font(.headline)
                                Text(player.status).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Playback") {
                    Toggle("Show audio visualizers", isOn: $visualizersEnabled)
                    Button("Connect Playback", action: player.beginPlaybackLogin)
                    Button("Reconnect Library", action: player.beginLibraryLogin)
                }

                Section {
                    Button(
                        "Log Out",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        role: .destructive,
                        action: player.logOut
                    )
                }

                Section("About") {
                    Text("Swiftify \(appVersion)")
                        .contentShape(.rect)
                        .onTapGesture {
                            withAnimation(.snappy) { isShowingEasterEgg = true }
                        }
                    if isShowingEasterEgg {
                        Text(EasterEgg.versionPhrase)
                            .foregroundStyle(MusicStyle.accent)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

private struct IOSPlaylistEditor: View {
    enum Mode {
        case create
        case edit(SpotifyPlaylist)
    }

    @ObservedObject var player: PlayerModel
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var isPublic: Bool

    init(player: PlayerModel, mode: Mode = .create) {
        self.player = player
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _isPublic = State(initialValue: false)
        case let .edit(playlist):
            _name = State(initialValue: playlist.name)
            _description = State(initialValue: playlist.description)
            _isPublic = State(initialValue: playlist.isPublic ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(2 ... 4)
                Toggle("Public playlist", isOn: $isPublic)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) {
                        Task {
                            if await save() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .create: "New Playlist"
        case .edit: "Edit Playlist"
        }
    }

    private var saveButtonTitle: String {
        switch mode {
        case .create: "Create"
        case .edit: "Save"
        }
    }

    private func save() async -> Bool {
        switch mode {
        case .create:
            return await player.createPlaylist(
                name: name,
                description: description,
                isPublic: isPublic
            )
        case .edit:
            return await player.updateSelectedPlaylist(
                name: name,
                description: description,
                isPublic: isPublic
            )
        }
    }
}

private struct IOSHorizontalShelf<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IOSSectionTitle(title).padding(.horizontal, 16)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) { content }
                    .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct IOSMediaCard: View {
    let title: String
    let subtitle: String
    let artworkURL: URL?
    var isCircular = false

    var body: some View {
        VStack(alignment: isCircular ? .center : .leading, spacing: 7) {
            ArtworkView(
                url: artworkURL,
                size: 154,
                cornerRadius: isCircular ? 77 : 12
            )
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 154, alignment: isCircular ? .center : .leading)
    }
}

private struct IOSSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func iosTime(_ milliseconds: Double) -> String {
    let seconds = max(Int(milliseconds / 1_000), 0)
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
}
#endif // os(iOS)
