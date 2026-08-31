#if os(macOS)
import Foundation
import SwiftUI

struct MusicHomeView: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                Text("Home")
                    .font(.system(size: 34, weight: .bold))

                if player.isLoadingHome && player.recentlyPlayed.isEmpty {
                    ProgressView("Loading your music…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    if !player.playlists.isEmpty {
                        mediaShelf(title: "Top Picks for You") {
                            ForEach(player.playlists.prefix(8)) { playlist in
                                PlaylistCard(playlist: playlist, size: 230) {
                                    player.selectPlaylist(playlist)
                                }
                            }
                        }
                    }

                    if !player.recentlyPlayed.isEmpty {
                        mediaShelf(title: "Recently Played") {
                            ForEach(player.recentlyPlayed) { song in
                                SongCard(song: song, size: 168) {
                                    player.play(song, in: player.recentlyPlayed)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .navigationTitle("Home")
    }

    private func mediaShelf<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    content()
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct GlobalSearchView: View {
    @ObservedObject var player: PlayerModel

    private let categories: [(String, Color, Color)] = [
        ("Pop", .pink, .orange),
        ("Rock", .red, .purple),
        ("Hip-Hop", .indigo, .blue),
        ("Electronic", .cyan, .green),
        ("Alternative", .purple, .pink),
        ("Metal", .gray, .black),
        ("R&B", .orange, .pink),
        ("Chill", .mint, .blue),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if player.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    categoryBrowser
                } else if EasterEgg.matches(player.searchQuery) {
                    easterEggResult
                } else if player.isSearching {
                    ProgressView("Searching Spotify…")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else if player.searchResults.isEmpty {
                    ContentUnavailableView.search(text: player.searchQuery)
                        .frame(minHeight: 360)
                } else {
                    searchResults
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .navigationTitle("Search")
        .onChange(of: player.searchQuery) { _, _ in
            player.scheduleSearch()
        }
    }

    private var easterEggResult: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(MusicStyle.accent)

            Text(EasterEgg.phrase)
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("You found it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .transition(.blurReplace.combined(with: .opacity))
    }

    private var categoryBrowser: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !player.searchPlaybackHistory.isEmpty {
                recentSearchPlaybacks
            }

            Text("Browse Categories")
                .font(.system(size: 32, weight: .bold))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: 16)],
                spacing: 16
            ) {
                ForEach(categories, id: \.0) { category in
                    Button {
                        player.searchQuery = category.0
                        player.scheduleSearch()
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(
                                colors: [category.1, category.2],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )

                            Circle()
                                .fill(.white.opacity(0.14))
                                .frame(width: 110, height: 110)
                                .offset(x: 115, y: 42)

                            Text(category.0)
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .padding(16)
                        }
                        .frame(height: 118)
                        .clipShape(.rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recentSearchPlaybacks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent searches")
                    .font(.title2.bold())
                Spacer()
                Button("Clear", action: player.clearSearchPlaybackHistory)
                    .buttonStyle(.plain)
                    .foregroundStyle(MusicStyle.accent)
            }

            SongCollection(
                player: player,
                songs: Array(player.searchPlaybackHistory.prefix(8)),
                context: .search
            )
        }
        .padding(.bottom, 8)
    }

    private var searchResults: some View {
        Group {
            if !player.searchResults.songs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Songs")
                    SongCollection(
                        player: player,
                        songs: player.searchResults.songs,
                        context: .search
                    )
                }
            }

            if !player.searchResults.albums.isEmpty {
                ResultShelf(title: "Albums") {
                    ForEach(player.searchResults.albums) { album in
                        AlbumCard(album: album) {
                            player.selectAlbum(album)
                        }
                    }
                }
            }

            if !player.searchResults.artists.isEmpty {
                ResultShelf(title: "Artists") {
                    ForEach(player.searchResults.artists) { artist in
                        ArtistCard(artist: artist) {
                            player.selectArtist(artist)
                        }
                    }
                }
            }

            if !player.searchResults.playlists.isEmpty {
                ResultShelf(title: "Playlists") {
                    ForEach(player.searchResults.playlists) { playlist in
                        PlaylistCard(playlist: playlist, size: 168) {
                            player.selectPlaylist(playlist)
                        }
                    }
                }
            }
        }
    }
}

struct PlaylistGridView: View {
    @ObservedObject var player: PlayerModel
    let createPlaylist: () -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 20)],
                alignment: .leading,
                spacing: 26
            ) {
                Button(action: createPlaylist) {
                    VStack(alignment: .leading, spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.quaternary)
                            Image(systemName: "plus")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(MusicStyle.accent)
                        }
                        .aspectRatio(1, contentMode: .fit)

                        Text("New Playlist")
                            .font(.callout.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)

                ForEach(player.playlists) { playlist in
                    PlaylistGridCard(
                        playlist: playlist,
                        isPinned: player.isPlaylistPinned(playlist),
                        action: { player.selectPlaylist(playlist) },
                        togglePin: { player.togglePinnedPlaylist(playlist) }
                    )
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 120)
        }
        .navigationTitle("My Playlists")
    }
}

struct PinnedPlaylistsView: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        Group {
            if player.pinnedPlaylists.isEmpty {
                ContentUnavailableView(
                    "No Pinned Playlists",
                    systemImage: "pin",
                    description: Text("Right-click a playlist to pin it here.")
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 20)],
                        alignment: .leading,
                        spacing: 26
                    ) {
                        ForEach(player.pinnedPlaylists) { playlist in
                            PlaylistGridCard(
                                playlist: playlist,
                                isPinned: true,
                                action: { player.selectPlaylist(playlist) },
                                togglePin: { player.togglePinnedPlaylist(playlist) }
                            )
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 26)
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle("Pinned Playlists")
    }
}

struct PlaylistDetailView: View {
    @ObservedObject var player: PlayerModel
    let playlist: SpotifyPlaylist

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                PlaylistHero(
                    player: player,
                    playlist: playlist
                )

                Divider()

                if player.isLoadingSongs {
                    ProgressView("Loading songs…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if player.songs.isEmpty {
                    ContentUnavailableView(
                        "No Songs",
                        systemImage: "music.note",
                        description: Text("Add songs from Search using the More menu.")
                    )
                    .frame(minHeight: 280)
                } else if displayedSongs.isEmpty {
                    ContentUnavailableView.search(text: player.playlistFilterQuery)
                        .frame(minHeight: 280)
                } else {
                    SongCollection(player: player, songs: displayedSongs, context: .playlist)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 120)
        }
        .navigationTitle(playlist.name)
    }

    private var displayedSongs: [SpotifySong] {
        let query = player.playlistFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? player.songs : player.songs.filter { song in
            song.name.localizedCaseInsensitiveContains(query)
                || song.artists.localizedCaseInsensitiveContains(query)
                || song.albumName?.localizedCaseInsensitiveContains(query) == true
        }

        switch player.playlistSortOrder {
        case .playlist:
            return filtered
        case .title:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .artist:
            return filtered.sorted { $0.artists.localizedCaseInsensitiveCompare($1.artists) == .orderedAscending }
        case .album:
            return filtered.sorted {
                ($0.albumName ?? "").localizedCaseInsensitiveCompare($1.albumName ?? "")
                    == .orderedAscending
            }
        case .duration:
            return filtered.sorted { ($0.durationMs ?? .max) < ($1.durationMs ?? .max) }
        }
    }
}

struct AlbumDetailView: View {
    @ObservedObject var player: PlayerModel
    let album: SpotifyAlbum

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom, spacing: 28) {
                    ArtworkView(url: album.artworkURL, size: 220, cornerRadius: 12)
                        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("ALBUM")
                            .font(.caption.bold())
                            .foregroundStyle(MusicStyle.accent)
                        Text(album.name)
                            .font(.system(size: 34, weight: .bold))
                        Text(album.artists)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text([album.releaseDate, album.songCount > 0 ? "\(album.songCount) songs" : nil]
                            .compactMap { $0 }
                            .joined(separator: "  •  "))
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button {
                            guard let first = player.albumSongs.first else { return }
                            player.play(first, in: player.albumSongs)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(player.albumSongs.isEmpty)
                        .padding(.top, 8)
                    }
                }

                Divider()

                if player.isLoadingSongs {
                    ProgressView("Loading album…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    SongCollection(player: player, songs: player.albumSongs, context: .general)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 120)
        }
        .navigationTitle(album.name)
    }
}

struct ArtistDetailView: View {
    @ObservedObject var player: PlayerModel
    let artist: SpotifyArtist

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .bottom, spacing: 28) {
                    ArtworkView(url: artist.artworkURL, size: 220, cornerRadius: 110)
                        .shadow(color: .black.opacity(0.22), radius: 20, y: 9)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("ARTIST")
                            .font(.caption.bold())
                            .foregroundStyle(MusicStyle.accent)
                        Text(artist.name)
                            .font(.system(size: 38, weight: .bold))
                            .lineLimit(2)
                    }
                }

                Divider()

                if player.isLoadingArtist {
                    ProgressView("Loading albums…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if player.artistAlbums.isEmpty {
                    ContentUnavailableView(
                        "No Albums Found",
                        systemImage: "music.note",
                        description: Text("Spotify did not return any releases for this artist.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle("Albums & Singles")

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 168), spacing: 20)],
                            alignment: .leading,
                            spacing: 24
                        ) {
                            ForEach(player.artistAlbums) { album in
                                AlbumCard(album: album) {
                                    player.selectAlbum(album)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 120)
        }
        .navigationTitle(artist.name)
    }
}

struct SavedSongsView: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom, spacing: 28) {
                    ZStack {
                        LinearGradient(
                            colors: [MusicStyle.accent, MusicStyle.deepGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "heart.fill")
                            .font(.system(size: 78, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 220, height: 220)
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(color: MusicStyle.accent.opacity(0.28), radius: 20, y: 8)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("PLAYLIST")
                            .font(.caption.bold())
                            .foregroundStyle(MusicStyle.accent)
                        Text("Favourite Songs")
                            .font(.system(size: 34, weight: .bold))
                        Text("\(player.savedSongs.count) songs")
                            .foregroundStyle(.secondary)

                        Button {
                            guard let first = player.savedSongs.first else { return }
                            player.play(first, in: player.savedSongs)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(player.savedSongs.isEmpty)
                        .padding(.top, 8)
                    }
                }

                Divider()

                if player.isLoadingSavedSongs {
                    ProgressView("Loading saved songs…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if player.savedSongs.isEmpty {
                    ContentUnavailableView(
                        "No Saved Songs",
                        systemImage: "heart",
                        description: Text("Save tracks from Search or a playlist.")
                    )
                    .frame(minHeight: 280)
                } else {
                    SongCollection(player: player, songs: player.savedSongs, context: .general)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 120)
        }
        .navigationTitle("Favourite Songs")
    }
}

private struct PlaylistHero: View {
    @ObservedObject var player: PlayerModel
    let playlist: SpotifyPlaylist

    var body: some View {
        HStack(alignment: .bottom, spacing: 28) {
            ArtworkView(url: playlist.artworkURL, size: 220, cornerRadius: 12)
                .shadow(color: .black.opacity(0.2), radius: 18, y: 8)

            VStack(alignment: .leading, spacing: 9) {
                Text("PLAYLIST")
                    .font(.caption.bold())
                    .foregroundStyle(MusicStyle.accent)
                Text(playlist.name)
                    .font(.system(size: 34, weight: .bold))
                    .lineLimit(2)
                if !playlist.description.isEmpty {
                    Text(playlist.description)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Text("\(playlist.ownerDisplayName)  •  \(playlist.songCount) songs")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                let isPlaylistDownloaded = player.isPlaylistDownloaded(player.songs)

                HStack(spacing: 10) {
                    Button {
                        guard let random = player.songs.randomElement() else { return }
                        if !player.isShuffleEnabled { player.toggleShuffle() }
                        player.play(random, in: player.songs)
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(player.songs.isEmpty)
                    .help("Shuffle Playlist")

                    Button {
                        guard let first = player.songs.first else { return }
                        player.play(first, in: player.songs)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 88, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular.tint(MusicStyle.accent).interactive(),
                        in: .capsule
                    )
                    .disabled(player.songs.isEmpty)
                    .help("Play Playlist")

                    if player.isDownloadingPlaylist {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .help("Downloading Playlist…")
                    } else if isPlaylistDownloaded {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .help("Downloaded")
                    } else if !player.songs.isEmpty {
                        Button {
                            player.downloadPlaylist(playlist)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .help("Download Playlist")
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

enum SongCollectionContext {
    case general
    case playlist
    case search
}

struct SongCollection: View {
    @ObservedObject var player: PlayerModel
    let songs: [SpotifySong]
    let context: SongCollectionContext

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongListRow(
                    player: player,
                    song: song,
                    number: index + 1,
                    context: context,
                    play: {
                        if context == .search {
                            player.playFromSearch(song, in: songs)
                        } else {
                            player.play(song, in: songs)
                        }
                    }
                )

                if index < songs.count - 1 {
                    Divider()
                        .padding(.leading, 62)
                }
            }
        }
    }
}

private struct SongListRow: View {
    @ObservedObject var player: PlayerModel
    let song: SpotifySong
    let number: Int
    let context: SongCollectionContext
    let play: () -> Void
    @AppStorage(AppPreferences.visualizersEnabledKey) private var visualizersEnabled = true

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 12) {
                    ZStack {
                        ArtworkView(url: song.artworkURL, size: 44, cornerRadius: 6)
                        if visualizersEnabled, player.currentSong?.id == song.id {
                            Rectangle()
                                .fill(.black.opacity(0.34))
                                .frame(width: 44, height: 44)
                                .clipShape(.rect(cornerRadius: 6))
                            AudioSpectrumView(spectrum: player.spectrum, isActive: player.isPlaying)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(song.name)
                                .font(.body.weight(player.currentSong?.id == song.id ? .semibold : .regular))
                                .foregroundStyle(player.currentSong?.id == song.id ? MusicStyle.accent : .primary)
                                .lineLimit(1)
                            if song.isExplicit {
                                Text("E")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(2)
                                    .background(.quaternary, in: .rect(cornerRadius: 2))
                            }
                        }
                        Text([song.artists, song.albumName]
                            .compactMap { $0?.nilIfEmpty }
                            .joined(separator: " — "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    if let durationMs = song.durationMs {
                        Text(formatDuration(durationMs))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            if player.downloadedTrackURIs.contains(song.uri) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
                    .help("Downloaded")
            }

            Button {
                player.toggleSaved(song)
            } label: {
                Image(systemName: player.isSaved(song) ? "star.fill" : "star")
                    .foregroundStyle(player.isSaved(song) ? MusicStyle.accent : .secondary)
            }
            .buttonStyle(.plain)
            .help(player.isSaved(song) ? "Remove from Favourite Songs" : "Add to Favourite Songs")

            SongOptionsMenu(
                player: player,
                song: song,
                allowsPlaylistRemoval: context == .playlist
                    && player.selectedPlaylist?.canModify(currentUserID: player.profile?.id) == true,
                labelWidth: 22,
                labelHeight: 22
            )
        }
        .contentShape(.rect)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            player.currentSong?.id == song.id
                ? MusicStyle.accent.opacity(0.07)
                : Color.clear,
            in: .rect(cornerRadius: 8)
        )
    }
}

private struct ResultShelf<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionTitle(title)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    content
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title2.bold())
    }
}

private struct PlaylistCard: View {
    let playlist: SpotifyPlaylist
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ArtworkView(url: playlist.artworkURL, size: size, cornerRadius: 12)
                    .shadow(color: .black.opacity(0.12), radius: 9, y: 4)
                Text(playlist.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(playlist.ownerDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: size, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct PlaylistGridCard: View {
    let playlist: SpotifyPlaylist
    let isPinned: Bool
    let action: () -> Void
    let togglePin: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                GeometryReader { geometry in
                    ArtworkView(
                        url: playlist.artworkURL,
                        size: geometry.size.width,
                        cornerRadius: 12
                    )
                    .shadow(color: .black.opacity(0.13), radius: 10, y: 4)
                }
                .aspectRatio(1, contentMode: .fit)

                Text(playlist.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text("\(playlist.songCount) songs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.46), in: .circle)
                    .padding(9)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            Button(action: togglePin) {
                Label(
                    isPinned ? "Unpin Playlist" : "Pin Playlist",
                    systemImage: isPinned ? "pin.slash" : "pin"
                )
            }
        }
    }
}

private struct SongCard: View {
    let song: SpotifySong
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ArtworkView(url: song.artworkURL, size: size, cornerRadius: 10)
                    .shadow(color: .black.opacity(0.1), radius: 7, y: 3)
                Text(song.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(song.artists)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: size, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct AlbumCard: View {
    let album: SpotifyAlbum
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ArtworkView(url: album.artworkURL, size: 168, cornerRadius: 10)
                Text(album.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(album.artists)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 168, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct ArtistCard: View {
    let artist: SpotifyArtist
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ArtworkView(url: artist.artworkURL, size: 154, cornerRadius: 77)
                Text(artist.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(width: 168)
        }
        .buttonStyle(.plain)
    }
}

private func formatDuration(_ milliseconds: Int) -> String {
    let seconds = max(milliseconds / 1_000, 0)
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
