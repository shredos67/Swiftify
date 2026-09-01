import SwiftUI

#if os(macOS)
import AppKit

@main
@MainActor
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(MusicStyle.accent)
        }
        .defaultSize(width: 1_280, height: 780)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            SwiftifySettingsView()
        }
    }
}
#endif

enum AppPreferences {
    static let visualizersEnabledKey = "visualizersEnabled"
    static let pinnedPlaylistIDsKey = "pinnedPlaylistIDs"
    static let searchPlaybackHistoryKey = "searchPlaybackHistory"
}

enum MusicStyle {
    static let accent = Color(red: 30 / 255, green: 215 / 255, blue: 96 / 255)
    static let accentSecondary = Color(red: 20 / 255, green: 168 / 255, blue: 76 / 255)
    static let deepGreen = Color(red: 5 / 255, green: 52 / 255, blue: 26 / 255)
}

enum EasterEgg {
    static let phrase = "i mean i guess bro"
    static let shortcutPhrase = "yoooo"
    static let versionPhrase = "no secret dev options here..."

    static func matches(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == phrase
    }
}

struct EasterEggHUD: View {
    var message = EasterEgg.phrase

    var body: some View {
        Label(message, systemImage: "sparkles")
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .glassEffect(
                .regular.tint(MusicStyle.accent.opacity(0.18)),
                in: .capsule
            )
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
            .allowsHitTesting(false)
    }
}

struct SpotifyStartupLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(MusicStyle.accent)
                .symbolEffect(.pulse)

            Text("Swiftify")
                .font(.title.bold())

            ProgressView()
                .controlSize(.large)
                .tint(MusicStyle.accent)

            Text("Checking your saved Spotify login…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RadialGradient(
                colors: [MusicStyle.accent.opacity(0.2), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 620
            )
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your saved Spotify login")
    }
}

#if os(macOS)
private struct SwiftifySettingsView: View {
    @AppStorage(AppPreferences.visualizersEnabledKey) private var visualizersEnabled = true
    @State private var isShowingEasterEgg = false

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("Show audio visualizers", isOn: $visualizersEnabled)
                Text("Turn this off to hide spectrum bars and stop audio spectrum polling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                Text("Swiftify \(appVersion)")
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.snappy) {
                            isShowingEasterEgg = true
                        }
                    }

                if isShowingEasterEgg {
                    Text(EasterEgg.versionPhrase)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(MusicStyle.accent)
                        .transition(.blurReplace.combined(with: .opacity))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 260)
        .padding()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }
}

@MainActor
struct ContentView: View {
    @StateObject private var player = PlayerModel()
    @State private var isShowingCreatePlaylist = false
    @State private var isShowingEditPlaylist = false
    @State private var isShowingFullscreenPlayer = false
    @State private var navigationHistory: [AppDestination] = []
    @State private var isRestoringNavigation = false
    @State private var isShowingEasterEgg = false
    @State private var easterEggTask: Task<Void, Never>?
    @AppStorage(AppPreferences.visualizersEnabledKey) private var visualizersEnabled = true

    var body: some View {
        rootContent
            .overlay {
            ZStack {
                if isShowingFullscreenPlayer {
                    FullscreenPlayerView(
                        player: player,
                        close: closeFullscreenPlayer
                    )
                    .ignoresSafeArea()
                    .clipped()
                    .transition(.opacity)
                    .zIndex(100)
                }

                if isShowingEasterEgg {
                    EasterEggHUD(message: EasterEgg.shortcutPhrase)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .zIndex(200)
                }
            }
        }
        .background {
            ZStack {
                EasterEggShortcutMonitor(action: revealEasterEgg)
                    .frame(width: 0, height: 0)

                TrailingToolbarConfigurator(
                    isEnabled: player.destination == .search || toolbarPlaylist != nil
                )
                .frame(width: 0, height: 0)
            }
        }
        .ignoresSafeArea(
            .container,
            edges: isShowingFullscreenPlayer ? .top : []
        )
        .animation(.smooth(duration: 0.42), value: isShowingFullscreenPlayer)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: navigateBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(navigationHistory.isEmpty)
                .help("Back")
            }
            .sharedBackgroundVisibility(.hidden)

            if player.destination == .search {
                ToolbarItem(placement: .automatic) {
                    globalSearchToolbar
                }
                .sharedBackgroundVisibility(.hidden)
            }

            if let playlist = toolbarPlaylist {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 10) {
                        playlistEditingToolbar(for: playlist)
                        playlistActionsToolbar(for: playlist)
                        playlistSearchToolbar
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .toolbarVisibility(
            isShowingFullscreenPlayer || player.isEvaluatingStoredLogin ? .hidden : .automatic,
            for: .windowToolbar
        )
        .windowToolbarFullScreenVisibility(.onHover)
        .onChange(of: player.destination) { oldDestination, newDestination in
            recordNavigation(from: oldDestination, to: newDestination)
        }
        .onChange(of: visualizersEnabled, initial: true) { _, isEnabled in
            player.setVisualizersEnabled(isEnabled)
        }
        .onDisappear {
            easterEggTask?.cancel()
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if player.isEvaluatingStoredLogin {
            SpotifyStartupLoadingView()
                .frame(minWidth: 1_100, minHeight: 700)
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        musicView
            .frame(minWidth: 1_100, minHeight: 700)
    }

    private var musicView: some View {
        NavigationSplitView {
            MusicSidebar(
                player: player,
                createPlaylist: beginCreatePlaylist
            )
        } detail: {
            playerWorkspace
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarRole(.editor)
        .background {
            ThinScrollerConfigurator()
                .frame(width: 0, height: 0)
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
            PlaylistEditorSheet(player: player, mode: .create)
        }
        .sheet(isPresented: $isShowingEditPlaylist) {
            if let playlist = player.selectedPlaylist {
                PlaylistEditorSheet(player: player, mode: .edit(playlist))
            }
        }
    }

    private var playerWorkspace: some View {
        HStack(spacing: 0) {
            centerStage

            if player.isShowingLyrics || player.isShowingQueue {
                Divider()
                    .ignoresSafeArea(.container, edges: .top)
                rightSidePanel
                    .frame(width: 250)
                    .ignoresSafeArea(.container, edges: .top)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: player.isShowingLyrics)
        .animation(.snappy, value: player.isShowingQueue)
    }

    private var centerStage: some View {
        detailView
            .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FloatingPlayerBar(
                    player: player,
                    showFullscreen: showFullscreenPlayer
                )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
            .overlay(alignment: .top) {
                if let errorMessage = player.errorMessage {
                    ErrorBanner(message: errorMessage)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: player.errorMessage)
            .clipped()
    }

    @ViewBuilder
    private var detailView: some View {
        if !player.isLibraryConnected {
            SpotifySetupView(player: player)
        } else {
            switch player.destination ?? .home {
            case .home:
                MusicHomeView(player: player)
            case .search:
                GlobalSearchView(player: player)
            case .songs:
                SavedSongsView(player: player)
            case .playlists:
                PlaylistGridView(
                    player: player,
                    createPlaylist: beginCreatePlaylist
                )
            case .pinnedPlaylists:
                PinnedPlaylistsView(player: player)
            case let .playlist(id):
                if let playlist = player.playlists.first(where: { $0.id == id }) {
                    PlaylistDetailView(
                        player: player,
                        playlist: playlist
                    )
                } else {
                    ContentUnavailableView("Playlist Unavailable", systemImage: "music.note.list")
                }
            case let .album(album):
                AlbumDetailView(player: player, album: album)
            case let .artist(artist):
                ArtistDetailView(player: player, artist: artist)
            }
        }
    }

    @ViewBuilder
    private var rightSidePanel: some View {
        if player.isShowingLyrics {
            LyricsPanel(player: player)
        } else if player.isShowingQueue {
            QueuePanel(player: player)
        }
    }

    private var toolbarPlaylist: SpotifyPlaylist? {
        guard let destination = player.destination,
              case .playlist = destination else {
            return nil
        }
        return player.selectedPlaylist
    }

    private func playlistEditingToolbar(for playlist: SpotifyPlaylist) -> some View {
        HStack(spacing: 4) {
            Button(action: beginCreatePlaylist) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .help("New Playlist")

            if playlist.canModify(currentUserID: player.profile?.id) {
                Button {
                    isShowingEditPlaylist = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .help("Edit Playlist")
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .buttonStyle(.plain)
        .controlSize(.regular)
    }

    private func playlistActionsToolbar(for playlist: SpotifyPlaylist) -> some View {
        HStack(spacing: 4) {
            if let playlistURL = spotifyURL(for: playlist) {
                ShareLink(item: playlistURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .help("Share Playlist")

                Menu {
                    if playlist.canModify(currentUserID: player.profile?.id) {
                        Button("Edit Playlist", systemImage: "pencil") {
                            isShowingEditPlaylist = true
                        }
                    }
                    Link(destination: playlistURL) {
                        Label("Open in Spotify", systemImage: "arrow.up.right.square")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .help("More")
            }

            Menu {
                Picker("Sort By", selection: $player.playlistSortOrder) {
                    ForEach(PlaylistSortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .help("Sort Options")
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .buttonStyle(.plain)
        .controlSize(.regular)
    }

    private var playlistSearchToolbar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find in Playlist", text: $player.playlistFilterQuery)
                .textFieldStyle(.plain)
                .font(.callout)

            if !player.playlistFilterQuery.isEmpty {
                Button {
                    player.playlistFilterQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 13)
        .frame(width: 220, height: 38)
        .glassEffect(.regular, in: .capsule)
        .buttonStyle(.plain)
        .controlSize(.regular)
    }

    private var globalSearchToolbar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search Spotify", text: $player.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit(player.scheduleSearch)

            if !player.searchQuery.isEmpty {
                Button {
                    player.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 13)
        .frame(width: 280, height: 38)
        .glassEffect(.regular, in: .capsule)
        .buttonStyle(.plain)
        .controlSize(.regular)
    }

    private func spotifyURL(for playlist: SpotifyPlaylist) -> URL? {
        URL(string: "https://open.spotify.com/playlist/\(playlist.id)")
    }

    private func beginCreatePlaylist() {
        if player.libraryNeedsAuthorizationUpgrade {
            player.beginLibraryLogin()
        } else {
            isShowingCreatePlaylist = true
        }
    }

    private func showFullscreenPlayer() {
        withAnimation(.smooth(duration: 0.42)) {
            isShowingFullscreenPlayer = true
        }
    }

    private func closeFullscreenPlayer() {
        withAnimation(.smooth(duration: 0.36)) {
            isShowingFullscreenPlayer = false
        }
    }

    private func revealEasterEgg() {
        easterEggTask?.cancel()
        withAnimation(.snappy) {
            isShowingEasterEgg = true
        }
        easterEggTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                isShowingEasterEgg = false
            }
        }
    }

    private func recordNavigation(
        from oldDestination: AppDestination?,
        to newDestination: AppDestination?
    ) {
        guard !isRestoringNavigation,
              let oldDestination,
              oldDestination != newDestination else {
            return
        }
        if navigationHistory.last != oldDestination {
            navigationHistory.append(oldDestination)
        }
    }

    private func navigateBack() {
        guard let destination = navigationHistory.popLast() else {
            return
        }

        isRestoringNavigation = true
        switch destination {
        case .home:
            player.showHome()
        case .search:
            player.showSearch()
        case .songs:
            player.showSavedSongs()
        case .playlists:
            player.showPlaylists()
        case .pinnedPlaylists:
            player.showPinnedPlaylists()
        case let .playlist(id):
            if let playlist = player.playlists.first(where: { $0.id == id }) {
                player.selectPlaylist(playlist)
            } else {
                player.showPlaylists()
            }
        case let .album(album):
            player.selectAlbum(album)
        case let .artist(artist):
            player.selectArtist(artist)
        }

        Task { @MainActor in
            await Task.yield()
            isRestoringNavigation = false
        }
    }
}

private struct EasterEggShortcutMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    @MainActor
    final class Coordinator {
        var action: () -> Void
        private var monitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard modifiers.contains([.command, .option]),
                      event.charactersIgnoringModifiers?.lowercased() == "g" else {
                    return event
                }
                self?.action()
                return nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

private struct ThinScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfigurationView {
        ConfigurationView()
    }

    func updateNSView(_ nsView: ConfigurationView, context: Context) {
        nsView.scheduleConfiguration()
    }

    final class ConfigurationView: NSView {
        private var lastConfigured = Date.distantPast

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleConfiguration()
        }

        func scheduleConfiguration() {
            guard window != nil else { return }
            guard Date.now.timeIntervalSince(lastConfigured) > 1 else { return }
            lastConfigured = Date.now

            Task { @MainActor [weak self] in
                guard let rootView = self?.window?.contentView else {
                    return
                }
                Self.configureScrollers(in: rootView)
            }
        }

        @MainActor
        private static func configureScrollers(in view: NSView) {
            if let scrollView = view as? NSScrollView {
                scrollView.verticalScroller?.controlSize = .small
                scrollView.horizontalScroller?.controlSize = .small
            }
            view.subviews.forEach(configureScrollers)
        }
    }
}

private struct TrailingToolbarConfigurator: NSViewRepresentable {
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled)
    }

    func makeNSView(context: Context) -> ConfigurationView {
        let view = ConfigurationView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ConfigurationView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.scheduleConfiguration(from: nsView)
    }

    final class ConfigurationView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.scheduleConfiguration(from: self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSToolbarDelegate {
        static let spacerItemIdentifier = NSToolbarItem.Identifier("Swiftify.SidebarReservedSpace")
        let reservedWidth: CGFloat = 250

        var isEnabled: Bool
        private var managedSpacerItem: NSToolbarItem?
        private weak var managedToolbar: NSToolbar?
        private weak var previousDelegate: (any NSToolbarDelegate)?
        private var configurationGeneration = 0

        init(isEnabled: Bool) {
            self.isEnabled = isEnabled
            super.init()
        }

        func scheduleConfiguration(from view: NSView) {
            configurationGeneration += 1
            let generation = configurationGeneration

            Task { @MainActor [weak self, weak view] in
                await Task.yield()
                guard let self,
                      generation == configurationGeneration else {
                    return
                }
                configure(toolbar: view?.window?.toolbar)
            }
        }

        private func configure(toolbar: NSToolbar?) {
            guard isEnabled else {
                removeManagedSpacerItem()
                return
            }

            guard let toolbar, !toolbar.items.isEmpty else { return }

            if managedToolbar === toolbar,
               let managedSpacerItem,
               let index = toolbar.items.firstIndex(where: { $0 === managedSpacerItem }),
               index == max(toolbar.items.count - 1, 0) {
                return
            }

            removeManagedSpacerItem()

            installDelegate(for: toolbar)

            let insertionIndex = max(toolbar.items.count - 1, 0)
            toolbar.insertItem(withItemIdentifier: Self.spacerItemIdentifier, at: insertionIndex)
            managedToolbar = toolbar
            managedSpacerItem = toolbar.items[insertionIndex]
        }

        private func installDelegate(for toolbar: NSToolbar) {
            guard toolbar.delegate !== self else { return }
            previousDelegate = toolbar.delegate
            toolbar.delegate = self
        }

        private func removeManagedSpacerItem() {
            guard let managedToolbar else {
                return
            }

            if let managedSpacerItem,
               let index = managedToolbar.items.firstIndex(where: { $0 === managedSpacerItem }) {
                managedToolbar.removeItem(at: index)
            }

            if managedToolbar.delegate === self {
                managedToolbar.delegate = previousDelegate
            }
            previousDelegate = nil
            self.managedToolbar = nil
            self.managedSpacerItem = nil
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            if itemIdentifier == Self.spacerItemIdentifier {
                let spacer = NSToolbarItem(itemIdentifier: itemIdentifier)
                let view = NSView(frame: NSRect(x: 0, y: 0, width: reservedWidth, height: 28))
                spacer.view = view
                return spacer
            }
            return previousDelegate?.toolbar?(toolbar, itemForItemIdentifier: itemIdentifier, willBeInsertedIntoToolbar: flag)
        }
    }
}

private struct MusicSidebar: View {
    @ObservedObject var player: PlayerModel
    let createPlaylist: () -> Void

    var body: some View {
        List(selection: $player.destination) {
            destinationRow("Search", systemImage: "magnifyingglass", destination: .search)
            destinationRow("Home", systemImage: "house.fill", destination: .home)

            Section("Library") {
                destinationRow("Songs", systemImage: "music.note", destination: .songs)
            }

            Section {
                destinationRow(
                    "All Playlists",
                    systemImage: "square.grid.2x2.fill",
                    destination: .playlists
                )
                destinationRow(
                    "Pinned Playlists",
                    systemImage: "pin.fill",
                    destination: .pinnedPlaylists
                )

                ForEach(player.playlists) { playlist in
                    let destination = AppDestination.playlist(playlist.id)
                    HStack(spacing: 8) {
                        ArtworkView(
                            url: playlist.artworkURL,
                            size: 24,
                            cornerRadius: 5
                        )
                        Text(playlist.name)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if player.isPlaylistPinned(playlist) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(MusicStyle.accent)
                        }
                    }
                    .tag(destination)
                    .contextMenu {
                        Button {
                            player.togglePinnedPlaylist(playlist)
                        } label: {
                            Label(
                                player.isPlaylistPinned(playlist)
                                    ? "Unpin Playlist"
                                    : "Pin Playlist",
                                systemImage: player.isPlaylistPinned(playlist)
                                    ? "pin.slash"
                                    : "pin"
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button(action: createPlaylist) {
                        Image(systemName: "plus")
                            .foregroundStyle(MusicStyle.accent)
                    }
                    .buttonStyle(.plain)
                    .help("New playlist")
                }
            }
        }
        .listStyle(.sidebar)
        .tint(Color(nsColor: .controlAccentColor))
        .navigationSplitViewColumnWidth(min: 205, ideal: 220, max: 270)
        .onChange(of: player.destination) { _, destination in
            guard let destination else {
                return
            }
            switch destination {
            case .home:
                player.showHome()
            case .search:
                player.showSearch()
            case .songs:
                player.showSavedSongs()
            case .playlists:
                player.showPlaylists()
            case .pinnedPlaylists:
                player.showPinnedPlaylists()
            case let .playlist(id):
                if player.selectedPlaylistID != id,
                   let playlist = player.playlists.first(where: { $0.id == id }) {
                    player.selectPlaylist(playlist)
                }
            case .album, .artist:
                break
            }
        }
        .safeAreaInset(edge: .bottom) {
            accountFooter
        }
    }

    private func destinationRow(
        _ title: String,
        systemImage: String,
        destination: AppDestination
    ) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(MusicStyle.accent)
        }
        .tag(destination)
    }

    private var accountFooter: some View {
        HStack(spacing: 10) {
            profileImage

            VStack(alignment: .leading, spacing: 1) {
                Text(player.profile?.displayName ?? "Spotify")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(accountStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Menu {
                Button("Connect Playback", action: player.beginPlaybackLogin)
                Button("Reconnect Library", action: player.beginLibraryLogin)
                Divider()
                Button(
                    "Log Out",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    role: .destructive,
                    action: player.logOut
                )
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar, in: .rect(cornerRadius: 10))
        .padding(8)
    }

    private var accountStatus: String {
        if player.libraryNeedsAuthorizationUpgrade {
            return "Reconnect for editing"
        }
        return player.isConnected ? "Playback connected" : "Playback offline"
    }

    @ViewBuilder
    private var profileImage: some View {
        if let url = player.profile?.artworkURL {
            ArtworkView(url: url, size: 30, cornerRadius: 15)
            .fixedSize(horizontal: true, vertical: true)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
        }
    }
}

struct SpotifySetupView: View {
    @ObservedObject var player: PlayerModel
    private let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(MusicStyle.accent)

            Text("Connect Your Music")
                .font(.largeTitle.bold())

            Text("Swiftify needs a Client ID from your own Spotify developer app. You only have to set this up once.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            VStack(alignment: .leading, spacing: 14) {
                setupStep(
                    number: 1,
                    title: "Create a Spotify app",
                    detail: "Open the Spotify Developer Dashboard, choose Create app, and select Web API if Spotify asks."
                )

                Link(destination: dashboardURL) {
                    Label("Open Spotify Developer Dashboard", systemImage: "arrow.up.right.square")
                }
                .padding(.leading, 38)

                setupStep(
                    number: 2,
                    title: "Add Swiftify's redirect URI",
                    detail: "In the app settings, add this exact address under Redirect URIs, then save:"
                )

                Text(SpotifyOAuthFlow.redirectURI.absoluteString)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                    .padding(.leading, 38)

                setupStep(
                    number: 3,
                    title: "Paste your Client ID",
                    detail: "Copy the Client ID from the app settings. You do not need the Client Secret."
                )
            }
            .frame(maxWidth: 560, alignment: .leading)

            TextField("Spotify Client ID", text: $player.libraryClientID)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 460)
                .onSubmit(player.beginLibraryLogin)

            HStack(spacing: 12) {
                Button("Connect Library", action: player.beginLibraryLogin)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(player.libraryClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Connect Playback", action: player.beginPlaybackLogin)
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }

            Text("Connect Library first, then Connect Playback so Swiftify can play music.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RadialGradient(
                colors: [MusicStyle.accent.opacity(0.14), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 430
            )
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PlaylistEditorSheet: View {
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

    init(player: PlayerModel, mode: Mode) {
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
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.bold())

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description", text: $description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3 ... 6)

            Toggle("Public playlist", isOn: $isPublic)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    if player.isCreatingPlaylist {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 440)
    }

    private var title: String {
        switch mode {
        case .create: "New Playlist"
        case .edit: "Edit Playlist"
        }
    }

    private func save() {
        Task {
            let saved: Bool
            switch mode {
            case .create:
                saved = await player.createPlaylist(
                    name: name,
                    description: description,
                    isPublic: isPublic
                )
            case .edit:
                saved = await player.updateSelectedPlaylist(
                    name: name,
                    description: description,
                    isPublic: isPublic
                )
            }
            if saved {
                dismiss()
            }
        }
    }
}

#Preview {
    ContentView()
}
#endif
