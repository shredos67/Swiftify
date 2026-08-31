#if os(macOS)
import AppKit
import SwiftUI

struct FullscreenPlayerView: View {
    @ObservedObject var player: PlayerModel
    let close: () -> Void
    @State private var wantsLyrics = true
    @State private var reservesLyricsLayout: Bool
    @FocusState private var acceptsKeyboardInput: Bool
    @AppStorage(AppPreferences.visualizersEnabledKey) private var visualizersEnabled = true

    init(player: PlayerModel, close: @escaping () -> Void) {
        self.player = player
        self.close = close
        _reservesLyricsLayout = State(
            initialValue: player.lyrics != nil || player.isLoadingLyrics
        )
    }

    private var usesLyricsLayout: Bool {
        wantsLyrics && reservesLyricsLayout
    }

    var body: some View {
        GeometryReader { geometry in
            let visualizerHeight = max(80, min(150, geometry.size.height * 0.17))
            let artworkWidth = usesLyricsLayout
                ? geometry.size.width * 0.27
                : geometry.size.width * 0.38
            let artworkHeight = geometry.size.height * (usesLyricsLayout ? 0.32 : 0.38)
            let artworkSize = max(170, min(min(artworkWidth, artworkHeight), 380))

            ZStack {
                if visualizersEnabled {
                    ReactiveArtworkBackdrop(
                        spectrum: player.spectrum,
                        isPlaying: player.isPlaying
                    )
                } else {
                    StaticArtworkBackdrop(colors: player.spectrum.gradientColors)
                }

                VStack(spacing: 0) {
                    topBar

                    Spacer(minLength: 12)

                    if let song = player.currentSong {
                        HStack(
                            spacing: usesLyricsLayout
                                ? max(32, min(72, geometry.size.width * 0.055))
                                : 0
                        ) {
                            FullscreenNowPlaying(
                                player: player,
                                song: song,
                                artworkSize: artworkSize
                            )
                            .frame(maxWidth: usesLyricsLayout ? 500 : 620)

                            if usesLyricsLayout {
                                Group {
                                    if let lyrics = player.lyrics {
                                        FullscreenLyrics(player: player, lyrics: lyrics)
                                            .transition(.opacity)
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(
                                    minWidth: 360,
                                    idealWidth: 470,
                                    maxWidth: 540,
                                    maxHeight: min(520, geometry.size.height * 0.62)
                                )
                            }
                        }
                        .frame(maxWidth: 1_250, maxHeight: .infinity)
                        .padding(
                            .horizontal,
                            max(28, min(64, geometry.size.width * 0.05))
                        )
                    } else {
                        ContentUnavailableView(
                            "Nothing Playing",
                            systemImage: "music.note",
                            description: Text("Choose a song to open the immersive player.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if visualizersEnabled {
                        CAVASpectrumView(
                            spectrum: player.spectrum,
                            isActive: player.isPlaying
                        )
                        .frame(height: visualizerHeight)
                        .padding(.horizontal, 42)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .clipped()
        .background(.black)
        .preferredColorScheme(.dark)
        .focusable()
        .focused($acceptsKeyboardInput)
        .focusEffectDisabled()
        .onAppear {
            acceptsKeyboardInput = true
        }
        .onKeyPress(.space) {
            player.togglePlayback()
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            seek(by: -10_000)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            seek(by: 10_000)
            return .handled
        }
        .onKeyPress(.upArrow) {
            player.setVolume(min(player.volume + 0.05, 1))
            return .handled
        }
        .onKeyPress(.downArrow) {
            player.setVolume(max(player.volume - 0.05, 0))
            return .handled
        }
        .onExitCommand(perform: close)
        .onChange(of: player.isLoadingLyrics) { _, isLoading in
            guard !isLoading else { return }
            resolveLyricsLayout()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: .circle)
            .help("Close Immersive Player")

            Spacer()

            if player.isLoadingLyrics {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 8)
            } else if player.lyrics != nil {
                Button(action: toggleLyrics) {
                    Label(
                        wantsLyrics ? "Hide Lyrics" : "Show Lyrics",
                        systemImage: "quote.bubble"
                    )
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular.tint(player.spectrum.gradientColors.first?.opacity(0.16) ?? .clear),
                    in: .capsule
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private func toggleLyrics() {
        let shouldShow = !wantsLyrics
        withAnimation(.smooth(duration: 0.45)) {
            wantsLyrics = shouldShow
            reservesLyricsLayout = shouldShow && player.lyrics != nil
        }
    }

    private func resolveLyricsLayout() {
        let shouldReserve = wantsLyrics && player.lyrics != nil
        guard shouldReserve != reservesLyricsLayout else { return }
        withAnimation(.smooth(duration: 0.45)) {
            reservesLyricsLayout = shouldReserve
        }
    }

    private func seek(by offset: Int64) {
        guard player.currentSong != nil,
              player.playbackDurationMs > 0 else {
            return
        }
        let currentPosition = Int64(player.playbackPositionMs)
        let duration = Int64(player.playbackDurationMs)
        let destination = min(max(currentPosition + offset, 0), duration)
        player.seek(to: UInt32(destination))
    }
}

private struct StaticArtworkBackdrop: View {
    let colors: [Color]

    var body: some View {
        let palette = colors.isEmpty
            ? [MusicStyle.accent, MusicStyle.accentSecondary]
            : colors
        let primary = palette[0]
        let secondary = palette[palette.count > 1 ? 1 : 0]

        ZStack {
            Color.black
            RadialGradient(
                colors: [primary.opacity(0.28), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 620
            )
            RadialGradient(
                colors: [secondary.opacity(0.22), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 680
            )
            Color.black.opacity(0.22)
        }
        .ignoresSafeArea()
    }
}

private struct FullscreenNowPlaying: View {
    @ObservedObject var player: PlayerModel
    let song: SpotifySong
    let artworkSize: CGFloat
    @State private var isShowingArtworkEasterEgg = false
    @State private var artworkEasterEggTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                ArtworkView(
                    url: song.artworkURL,
                    size: artworkSize,
                    cornerRadius: max(18, artworkSize * 0.055)
                )

                if isShowingArtworkEasterEgg {
                    EasterEggHUD()
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .frame(width: artworkSize, height: artworkSize)
            .contentShape(.rect)
            .onTapGesture {
                guard NSEvent.modifierFlags.contains(.option) else { return }
                revealArtworkEasterEgg()
            }
            .artworkBackdropGlow(
                colors: player.spectrum.gradientColors,
                intensity: 0.58,
                radius: 52
            )

            ZStack(alignment: .trailing) {
                VStack(spacing: 5) {
                    Text(song.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(song.artists)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let albumName = song.albumName {
                        Text(albumName)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)

                SongOptionsMenu(
                    player: player,
                    song: song,
                    labelWidth: 38,
                    labelHeight: 38
                )
            }
            .frame(maxWidth: artworkSize)
            .artworkBackdropGlow(
                colors: player.spectrum.gradientColors,
                intensity: 0.2,
                radius: 22
            )

            FullscreenProgressTrack(player: player)
                .frame(maxWidth: min(artworkSize + 80, 500))

            FullscreenTransportControls(player: player)
        }
        .onDisappear {
            artworkEasterEggTask?.cancel()
        }
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
}

private struct FullscreenTransportControls: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        HStack(spacing: 28) {
            controlButton(
                symbol: "shuffle",
                isActive: player.isShuffleEnabled,
                disabled: player.currentSong == nil,
                action: player.toggleShuffle
            )

            controlButton(
                symbol: "backward.fill",
                size: 19,
                disabled: !player.canSkipBackward,
                action: player.skipBackward
            )

            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.08), value: player.isPlaying)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 56, height: 56)
                    .background(.white, in: .circle)
                    .artworkBackdropGlow(
                        colors: player.spectrum.gradientColors,
                        intensity: 0.5,
                        radius: 18
                    )
            }
            .buttonStyle(.plain)
            .disabled(player.currentSong == nil || !player.isConnected)

            controlButton(
                symbol: "forward.fill",
                size: 19,
                disabled: !player.canSkipForward,
                action: player.skipForward
            )

            controlButton(
                symbol: player.repeatMode.symbolName,
                isActive: player.repeatMode != .off,
                disabled: player.currentSong == nil,
                action: player.cycleRepeatMode
            )
        }
    }

    private func controlButton(
        symbol: String,
        size: CGFloat = 16,
        isActive: Bool = false,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isActive ? MusicStyle.accent : .white)
                .frame(width: 24, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct FullscreenProgressTrack: View {
    @ObservedObject var player: PlayerModel
    @State private var scrubPosition: Double?

    var body: some View {
        let colors = player.spectrum.gradientColors.isEmpty
            ? [MusicStyle.accent, MusicStyle.accentSecondary]
            : player.spectrum.gradientColors
        let primaryColor = colors[0]

        HStack(spacing: 12) {
            Text(formattedTime(displayPosition))
                .frame(width: 42, alignment: .trailing)

            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let progress = min(max(displayPosition / duration, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.black.opacity(0.52))
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.2), lineWidth: 0.75)
                        }
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: colors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * progress)
                        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                        .shadow(color: primaryColor.opacity(0.42), radius: 5)
                }
                .frame(height: 6)
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
                            let target = position(for: value.location.x, width: width)
                            player.seek(to: UInt32(target.rounded()))
                            scrubPosition = nil
                        }
                )
            }
            .frame(height: 18)

            Text("−\(formattedTime(max(duration - displayPosition, 0)))")
                .frame(width: 48, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.78))
        .shadow(color: .black.opacity(0.9), radius: 2, y: 1)
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

private struct FullscreenLyrics: View {
    @ObservedObject var player: PlayerModel
    let lyrics: SpotifyLyrics

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(lyrics.lines) { line in
                        let isActive = !lyrics.isSynchronized
                            || player.activeLyricLineID == line.id

                        Text(line.words.isEmpty ? "♪" : line.words)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(isActive ? 1 : 0.28)
                            .shadow(
                                color: isActive
                                    ? player.spectrum.gradientColors.first?.opacity(0.5) ?? .clear
                                    : .clear,
                                radius: 12
                            )
                            .contentShape(.rect)
                            .onTapGesture {
                                guard lyrics.isSynchronized else { return }
                                player.seek(to: line.startTimeMs)
                            }
                            .animation(.easeInOut(duration: 0.32), value: isActive)
                            .id(line.id)
                    }

                    Text("Lyrics provided by \(lyrics.provider)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 20)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 30)
            }
            .scrollIndicators(.hidden)
            .onChange(of: player.activeLyricLineID) { _, lineID in
                guard let lineID else { return }
                withAnimation(.smooth(duration: 0.45)) {
                    proxy.scrollTo(lineID, anchor: .center)
                }
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.08),
                    .init(color: .white, location: 0.92),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct CAVASpectrumView: View {
    @ObservedObject var spectrum: AudioSpectrumModel
    let isActive: Bool

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 3
            let oneSide = bassExpandedSpectrumLevels(
                spectrum.levels,
                perSideCount: spectrum.levels.count
            )
            let levels = oneSide + oneSide.reversed()
            let count = max(levels.count, 1)
            let availableWidth = geometry.size.width - spacing * CGFloat(count - 1)
            let barWidth = max(2, availableWidth / CGFloat(count))
            let bars = HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, rawLevel in
                    let level = min(max(rawLevel, 0), 1)
                    let height = max(
                        3,
                        geometry.size.height * (0.025 + 0.975 * pow(level, 0.78))
                    )

                    Capsule(style: .continuous)
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.smooth(duration: 0.12), value: spectrum.levels)

            let colors = spectrum.gradientColors.isEmpty
                ? [MusicStyle.accent, MusicStyle.accentSecondary]
                : spectrum.gradientColors
            let primaryColor = colors[0]
            let secondaryColor = colors[colors.count > 1 ? 1 : 0]
            let gradient = LinearGradient(
                stops: [
                    .init(color: primaryColor, location: 0),
                    .init(color: secondaryColor, location: 0.42),
                    .init(color: secondaryColor, location: 0.58),
                    .init(color: primaryColor, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            gradient
                .mask { bars }
                .saturation(1.38)
                .contrast(1.08)
                .shadow(color: primaryColor.opacity(0.72), radius: 5)
                .shadow(color: secondaryColor.opacity(0.52), radius: 12, y: 3)
                .opacity(isActive ? 1 : 0.4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isActive ? "Immersive live audio spectrum" : "Audio spectrum paused")
    }
}

private struct ReactiveArtworkBackdrop: View {
    @ObservedObject var spectrum: AudioSpectrumModel
    let isPlaying: Bool

    private var bass: CGFloat {
        energy(from: 0, to: spectrum.levels.count * 3 / 16)
    }

    private var midrange: CGFloat {
        energy(
            from: spectrum.levels.count * 3 / 16,
            to: spectrum.levels.count * 10 / 16
        )
    }

    private var treble: CGFloat {
        energy(from: spectrum.levels.count * 10 / 16, to: spectrum.levels.count)
    }

    private var frequencyEnergies: [CGFloat] {
        let count = spectrum.levels.count
        return (0 ..< 5).map { index in
            energy(from: index * count / 5, to: (index + 1) * count / 5)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            GeometryReader { geometry in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let artworkColors = spectrum.gradientColors.isEmpty
                    ? [MusicStyle.accent, MusicStyle.accentSecondary]
                    : spectrum.gradientColors
                let firstArtworkColor = artworkColors[0]
                let secondArtworkColor = artworkColors[artworkColors.count > 1 ? 1 : 0]
                let blobColors = [
                    firstArtworkColor,
                    secondArtworkColor,
                    firstArtworkColor,
                    secondArtworkColor,
                    firstArtworkColor,
                ]
                let reactiveEnergies = frequencyEnergies

                ZStack {
                    Color(red: 0.009, green: 0.009, blue: 0.012)

                    MeshGradient(
                        width: 4,
                        height: 4,
                        points: meshPoints(time: time),
                        colors: [
                            .black, firstArtworkColor.opacity(0.2), .black, secondArtworkColor.opacity(0.18),
                            secondArtworkColor.opacity(0.16), firstArtworkColor.opacity(0.42), secondArtworkColor.opacity(0.38), .black,
                            .black, secondArtworkColor.opacity(0.4), firstArtworkColor.opacity(0.38), firstArtworkColor.opacity(0.18),
                            firstArtworkColor.opacity(0.16), .black, secondArtworkColor.opacity(0.2), .black,
                        ],
                        background: Color(red: 0.009, green: 0.009, blue: 0.012),
                        smoothsColors: true
                    )
                    .scaleEffect(1.16)
                    .blur(radius: 44)
                    .saturation(0.96 + bass * (isPlaying ? 0.22 : 0.04))
                    .opacity(isPlaying ? 0.82 : 0.62)

                    ForEach(0 ..< 5, id: \.self) { index in
                        ReactiveArtworkBlob(
                            index: index,
                            time: time,
                            energy: reactiveEnergies[index],
                            isPlaying: isPlaying,
                            containerSize: geometry.size,
                            color: blobColors[index],
                            companionColor: blobColors[(index + 1) % blobColors.count]
                        )
                    }

                    RadialGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        center: .center,
                        startRadius: min(geometry.size.width, geometry.size.height) * 0.2,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.68
                    )

                    LinearGradient(
                        colors: [.black.opacity(0.16), .clear, .black.opacity(0.42)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    Color.black.opacity(0.08)
                }
                .drawingGroup(opaque: true, colorMode: .extendedLinear)
            }
        }
        .ignoresSafeArea()
    }

    private func energy(from lowerBound: Int, to upperBound: Int) -> CGFloat {
        guard !spectrum.levels.isEmpty else { return 0 }
        let lowerBound = min(max(lowerBound, 0), spectrum.levels.count)
        let upperBound = min(max(upperBound, lowerBound), spectrum.levels.count)
        guard lowerBound < upperBound else { return 0 }
        let values = spectrum.levels[lowerBound ..< upperBound]
        let rootMeanSquare = sqrt(
            values.reduce(CGFloat.zero) { $0 + $1 * $1 } / CGFloat(values.count)
        )
        let peak = values.max() ?? 0
        return pow(min(1, rootMeanSquare * 0.58 + peak * 0.68), 0.62)
    }

    private func meshPoints(time: TimeInterval) -> [SIMD2<Float>] {
        let activity = Float(isPlaying ? 1 : 0.25)
        let bassMotion = Float(bass) * 0.11 * activity
        let midMotion = Float(midrange) * 0.085 * activity
        let trebleMotion = Float(treble) * 0.065 * activity

        return [
            SIMD2(0, 0), SIMD2(0.33, 0), SIMD2(0.67, 0), SIMD2(1, 0),
            SIMD2(0, 0.33),
            SIMD2(
                0.33 + Float(sin(time * 0.07)) * 0.04 + Float(sin(time * 0.28)) * bassMotion,
                0.33 + Float(cos(time * 0.06)) * 0.045 + Float(cos(time * 0.34)) * midMotion
            ),
            SIMD2(
                0.67 + Float(cos(time * 0.05 + 1.4)) * 0.05 + Float(cos(time * 0.31)) * midMotion,
                0.33 + Float(sin(time * 0.07 + 0.8)) * 0.04 + Float(sin(time * 0.4)) * trebleMotion
            ),
            SIMD2(1, 0.33),
            SIMD2(0, 0.67),
            SIMD2(
                0.33 + Float(cos(time * 0.055 + 2.1)) * 0.045 + Float(cos(time * 0.37)) * trebleMotion,
                0.67 + Float(sin(time * 0.065 + 1.9)) * 0.045 + Float(sin(time * 0.29)) * bassMotion
            ),
            SIMD2(
                0.67 + Float(sin(time * 0.052 + 2.8)) * 0.05 + Float(sin(time * 0.3)) * bassMotion,
                0.67 + Float(cos(time * 0.075 + 1.1)) * 0.04 + Float(cos(time * 0.33)) * midMotion
            ),
            SIMD2(1, 0.67),
            SIMD2(0, 1), SIMD2(0.33, 1), SIMD2(0.67, 1), SIMD2(1, 1),
        ]
    }
}

private struct ReactiveArtworkBlob: View {
    let index: Int
    let time: TimeInterval
    let energy: CGFloat
    let isPlaying: Bool
    let containerSize: CGSize
    let color: Color
    let companionColor: Color

    var body: some View {
        OrganicBlob(
            phase: blobPhase,
            lobes: 4 + index % 4,
            distortion: 0.12 + reaction * 0.34
        )
        .fill(
            RadialGradient(
                colors: [
                    color.opacity(0.32 + Double(reaction) * 0.16),
                    companionColor.opacity(0.12 + Double(reaction) * 0.12),
                    .clear,
                ],
                center: .center,
                startRadius: 0,
                endRadius: max(blobSize.width, blobSize.height) * 0.52
            )
        )
        .frame(width: blobSize.width, height: blobSize.height)
        .scaleEffect(0.96 + reaction * 0.4)
        .rotationEffect(.degrees(rotation))
        .position(blobPosition)
        .blur(radius: 72 + CGFloat(index) * 8)
        .saturation(1 + reaction * 0.24)
        .brightness(reaction * 0.02)
        .opacity(0.82)
        .blendMode(.screen)
    }

    private var phase: Double {
        Double(index) * 1.67
    }

    private var reaction: CGFloat {
        energy * (isPlaying ? 1 : 0.12)
    }

    private var blobSize: CGSize {
        CGSize(
            width: containerSize.width * (0.7 + CGFloat(index % 3) * 0.1),
            height: containerSize.height * (0.74 + CGFloat((index + 1) % 3) * 0.09)
        )
    }

    private var blobPosition: CGPoint {
        let horizontalDrift = CGFloat(
            sin(time * (0.026 + Double(index) * 0.004) + phase)
        ) * 0.18
        let horizontalReaction = CGFloat(sin(time * 0.28 + phase)) * reaction * 0.07
        let verticalDrift = CGFloat(
            cos(time * (0.022 + Double(index) * 0.0035) + phase * 0.83)
        ) * 0.16
        let verticalReaction = CGFloat(cos(time * 0.34 + phase * 1.2)) * reaction * 0.065
        return CGPoint(
            x: containerSize.width * (0.5 + horizontalDrift + horizontalReaction),
            y: containerSize.height * (0.5 + verticalDrift + verticalReaction)
        )
    }

    private var blobPhase: CGFloat {
        let idleMotion = time * (0.042 + Double(index) * 0.006) + phase
        return CGFloat(idleMotion + Double(reaction) * 2.2)
    }

    private var rotation: Double {
        let idleSpeed = index.isMultiple(of: 2) ? 0.28 : -0.23
        let reactionDirection = index.isMultiple(of: 2) ? 1.0 : -1.0
        return time * idleSpeed
            + Double(index * 29)
            + Double(reaction) * reactionDirection * 28
    }
}

private struct OrganicBlob: Shape {
    let phase: CGFloat
    let lobes: Int
    let distortion: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width * 0.5
        let radiusY = rect.height * 0.5
        let pointCount = 16
        let points = (0 ..< pointCount).map { index in
            let angle = CGFloat(index) / CGFloat(pointCount) * .pi * 2
            let radialOffset = 1
                + distortion * sin(angle * CGFloat(lobes) + phase)
                + distortion * 0.46 * sin(angle * CGFloat(lobes + 3) - phase * 1.31)
            return CGPoint(
                x: center.x + cos(angle) * radiusX * radialOffset,
                y: center.y + sin(angle) * radiusY * radialOffset
            )
        }

        var path = Path()
        guard let lastPoint = points.last, let firstPoint = points.first else {
            return path
        }
        path.move(to: midpoint(lastPoint, firstPoint))

        for index in points.indices {
            let point = points[index]
            let nextPoint = points[(index + 1) % points.count]
            path.addQuadCurve(to: midpoint(point, nextPoint), control: point)
        }
        path.closeSubpath()
        return path
    }

    private func midpoint(_ left: CGPoint, _ right: CGPoint) -> CGPoint {
        CGPoint(x: (left.x + right.x) * 0.5, y: (left.y + right.y) * 0.5)
    }
}
#endif
