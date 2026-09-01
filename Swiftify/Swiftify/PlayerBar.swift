#if os(macOS)
import AppKit
import Foundation
import SwiftUI

struct FloatingPlayerBar: View {
    @ObservedObject var player: PlayerModel
    let showFullscreen: () -> Void
    @Environment(\.appearsActive) private var appearsActive
    @State private var isVolumeExpanded = false
    @State private var isHoveringArtwork = false
    @State private var isProgressExpanded = false
    @State private var isShowingArtworkEasterEgg = false
    @State private var artworkEasterEggTask: Task<Void, Never>?
    @AppStorage(AppPreferences.visualizersEnabledKey) private var visualizersEnabled = true

    init(player: PlayerModel, showFullscreen: @escaping () -> Void = {}) {
        self.player = player
        self.showFullscreen = showFullscreen
    }

    var body: some View {
        HStack(spacing: 18) {
            transportControls
                .frame(width: 185)

            nowPlaying
                .frame(maxWidth: .infinity)

            utilityControls
                .frame(width: isVolumeExpanded ? 214 : 144, alignment: .trailing)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .opacity(appearsActive ? 1 : 0.76)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.16), radius: 18, y: 7)
        .overlay {
            if isShowingArtworkEasterEgg {
                EasterEggHUD()
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: appearsActive)
        .animation(.snappy, value: isVolumeExpanded)
        .onDisappear {
            artworkEasterEggTask?.cancel()
        }
    }

    private var transportControls: some View {
        HStack(spacing: 13) {
            transportButton(
                symbol: "shuffle",
                help: player.isShuffleEnabled ? "Disable shuffle" : "Enable shuffle",
                isActive: player.isShuffleEnabled,
                action: player.toggleShuffle
            )

            transportButton(
                symbol: "backward.fill",
                help: "Previous song",
                isDisabled: !player.canSkipBackward,
                action: player.skipBackward
            )

            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.08), value: player.isPlaying)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(MusicStyle.accent, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(player.currentSong == nil || !player.isConnected)
            .help(player.isPlaying ? "Pause" : "Play")

            transportButton(
                symbol: "forward.fill",
                help: "Next song",
                isDisabled: !player.canSkipForward,
                action: player.skipForward
            )

            transportButton(
                symbol: player.repeatMode.symbolName,
                help: player.repeatMode.helpText,
                isActive: player.repeatMode != .off,
                isDisabled: player.currentSong == nil,
                action: player.cycleRepeatMode
            )
        }
    }

    private var nowPlaying: some View {
        HStack(alignment: .center, spacing: 9) {
            VStack(spacing: 4) {
                HStack(spacing: 11) {
                    nowPlayingArtwork

                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.currentSong?.name ?? "Not Playing")
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(player.currentSong?.artists ?? "Choose something to play")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 5)
                }
                .blur(radius: isProgressExpanded ? 8 : 0)
                .animation(.easeOut(duration: 0.16), value: isProgressExpanded)

                PlayerProgressTrack(
                    player: player,
                    isExpanded: $isProgressExpanded
                )
            }

            if visualizersEnabled, player.currentSong != nil {
                AudioSpectrumView(
                    spectrum: player.spectrum,
                    isActive: player.isPlaying,
                    width: 30,
                    height: 34
                )
            }
        }
    }

    private var nowPlayingArtwork: some View {
        ZStack {
            ArtworkView(
                url: player.currentSong?.artworkURL,
                size: 36,
                cornerRadius: 6
            )
            .brightness(isHoveringArtwork ? -0.2 : 0)

            if player.currentSong != nil {
                Button {
                    if NSEvent.modifierFlags.contains(.option) {
                        revealArtworkEasterEgg()
                    } else {
                        showFullscreen()
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .opacity(isHoveringArtwork ? 1 : 0)
                .accessibilityLabel("Open Immersive Player")
                .help("Open Immersive Player")
            }
        }
        .frame(width: 36, height: 36)
        .contentShape(.rect(cornerRadius: 6))
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHoveringArtwork = isHovering
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isHoveringArtwork)
    }

    private func revealArtworkEasterEgg() {
        artworkEasterEggTask?.cancel()
        withAnimation(.snappy) {
            isShowingArtworkEasterEgg = true
        }
        artworkEasterEggTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                isShowingArtworkEasterEgg = false
            }
        }
    }

    private var utilityControls: some View {
        HStack(spacing: 13) {
            utilityButton(
                symbol: "quote.bubble",
                help: "Lyrics",
                isActive: player.isShowingLyrics,
                isDisabled: player.currentSong == nil,
                action: player.toggleLyricsPanel
            )

            utilityButton(
                symbol: "list.bullet",
                help: "Playing Next",
                isActive: player.isShowingQueue,
                isDisabled: player.currentSong == nil,
                action: player.toggleQueuePanel
            )

            if let song = player.currentSong {
                SongOptionsMenu(
                    player: player,
                    song: song,
                    labelWidth: 20,
                    labelHeight: 28
                )
            }

            Button {
                withAnimation(.snappy) {
                    isVolumeExpanded.toggle()
                }
            } label: {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isVolumeExpanded ? MusicStyle.accent : .primary)
            }
            .buttonStyle(.plain)
            .disabled(!player.isConnected)
            .help(isVolumeExpanded ? "Hide Volume" : "Show Volume")

            if isVolumeExpanded {
                VolumeTrack(player: player)
                    .frame(width: 66)
                    .disabled(!player.isConnected)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private func transportButton(
        symbol: String,
        help: String,
        isActive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? MusicStyle.accent : .primary)
                .frame(width: 20, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
    }

    private func utilityButton(
        symbol: String,
        help: String,
        isActive: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? MusicStyle.accent : .primary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
    }

    private var volumeSymbol: String {
        switch player.volume {
        case ...0.01: "speaker.slash.fill"
        case ...0.34: "speaker.wave.1.fill"
        case ...0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

private struct VolumeTrack: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)

            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.secondary)
                    .frame(width: width * player.volume)
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        player.setVolume(min(max(Double(value.location.x / width), 0), 1))
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int((player.volume * 100).rounded())) percent")
        }
        .frame(height: 14)
    }
}

private struct PlayerProgressTrack: View {
    @ObservedObject var player: PlayerModel
    @Binding var isExpanded: Bool
    @State private var scrubPosition: Double?

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: isExpanded ? 0 : 7) {
                Text(formattedTime(displayPosition))
                    .frame(width: isExpanded ? 0 : 31, alignment: .trailing)
                    .opacity(isExpanded ? 0 : 1)
                    .clipped()

                progressBar

                Text("−\(formattedTime(max(duration - displayPosition, 0)))")
                    .frame(width: isExpanded ? 0 : 36, alignment: .leading)
                    .opacity(isExpanded ? 0 : 1)
                    .clipped()
            }
            .font(.system(size: 9, design: .monospaced))

            HStack {
                Text(formattedTime(displayPosition))
                Spacer()
                Text("−\(formattedTime(max(duration - displayPosition, 0)))")
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .offset(y: -17)
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(false)
        }
        .foregroundStyle(.secondary)
        .opacity(player.currentSong == nil ? 0.45 : 1)
        .frame(height: 11)
        .contentShape(.rect)
        .zIndex(isExpanded ? 10 : 0)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isExpanded = isHovering
            }
        }
        .animation(.easeOut(duration: 0.14), value: isExpanded)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let progress = min(max(displayPosition / duration, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(isExpanded ? 0.36 : 0.14))
                Capsule()
                    .fill(MusicStyle.accent)
                    .frame(width: width * progress)
            }
            .frame(height: isExpanded ? 8 : 3)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canSeek else { return }
                        scrubPosition = position(for: value.location.x, width: width)
                    }
                    .onEnded { value in
                        guard canSeek else { return }
                        let position = position(for: value.location.x, width: width)
                        player.seek(to: UInt32(position.rounded()))
                        scrubPosition = nil
                    }
            )
        }
    }

    private var displayPosition: Double {
        scrubPosition ?? Double(player.playbackPositionMs)
    }

    private var duration: Double {
        max(Double(player.playbackDurationMs), 1)
    }

    private var canSeek: Bool {
        player.currentSong != nil && player.playbackDurationMs > 0
    }

    private func position(for x: CGFloat, width: CGFloat) -> Double {
        min(max(Double(x / width), 0), 1) * duration
    }

    private func formattedTime(_ milliseconds: Double) -> String {
        let seconds = max(Int(milliseconds / 1_000), 0)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

struct LyricsPanel: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        VStack(spacing: 0) {
            panelHeader(title: "Lyrics")
            lyricsContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    @ViewBuilder
    private var lyricsContent: some View {
        if player.isLoadingLyrics {
            ProgressView("Loading lyrics…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let lyrics = player.lyrics {
            synchronizedLyrics(lyrics)
        } else {
            ContentUnavailableView(
                "Lyrics Unavailable",
                systemImage: "quote.bubble",
                description: Text(player.lyricsMessage ?? "i guess bro")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func synchronizedLyrics(_ lyrics: SpotifyLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(lyrics.lines) { line in
                        lyricLine(line, synchronized: lyrics.isSynchronized)
                            .id(line.id)
                    }

                    Text("Lyrics provided by \(lyrics.provider)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .onChange(of: player.activeLyricLineID) { _, lineID in
                guard let lineID else { return }
                withAnimation(.smooth(duration: 0.35)) {
                    proxy.scrollTo(lineID, anchor: .center)
                }
            }
        }
    }

    private func lyricLine(_ line: SpotifyLyricLine, synchronized: Bool) -> some View {
        let isActive = !synchronized || player.activeLyricLineID == line.id
        let inactiveScale = 19.0 / 22.0

        return Text(line.words.isEmpty ? "♪" : line.words)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(isActive ? 1 : inactiveScale, anchor: .topLeading)
            .opacity(isActive ? 1 : 0.34)
            .contentShape(.rect)
            .onTapGesture {
                guard synchronized else { return }
                player.seek(to: line.startTimeMs)
            }
            .animation(.easeInOut(duration: 0.28), value: isActive)
    }
}

struct QueuePanel: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        VStack(spacing: 0) {
            panelHeader(title: "Playing Next")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let currentSong = player.currentSong {
                        Text("Now Playing")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        QueueSongRow(song: currentSong, isCurrent: true) {}
                    }

                    if !player.upNextSongs.isEmpty {
                        Text("Up Next")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)

                        ForEach(player.upNextSongs) { song in
                            QueueSongRow(song: song, isCurrent: false) {
                                player.playFromQueue(song)
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "Queue Empty",
                            systemImage: "text.line.last.and.arrowtriangle.forward",
                            description: Text(EasterEgg.phrase)
                        )
                        .padding(.top, 50)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(.container, edges: .top)
        }
    }
}

private struct QueueSongRow: View {
    let song: SpotifySong
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ArtworkView(url: song.artworkURL, size: 42, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.name)
                        .font(.callout.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? MusicStyle.accent : .primary)
                        .lineLimit(1)
                    Text(song.artists)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(.rect)
            .padding(6)
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }
}

private func panelHeader(title: String) -> some View {
    HStack {
        Text(title)
            .font(.title2.bold())
        Spacer()
    }
    .padding(18)
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.red)
                .textSelection(.enabled)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.red.opacity(0.18)), in: .rect(cornerRadius: 14))
        .padding(.horizontal, 18)
        .task(id: message) {
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            dismiss()
        }
    }
}
#endif
