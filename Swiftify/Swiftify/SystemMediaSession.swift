import Foundation
import MediaPlayer

#if os(iOS)
import AVFAudio
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class SystemMediaSession {
    struct Handlers {
        let play: @MainActor () -> Void
        let pause: @MainActor () -> Void
        let togglePlayback: @MainActor () -> Void
        let nextTrack: @MainActor () -> Void
        let previousTrack: @MainActor () -> Void
        let seek: @MainActor (TimeInterval) -> Void
    }

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private let handlers: Handlers
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    #if os(iOS)
    private var notificationObservers: [NSObjectProtocol] = []
    private var wasPlayingBeforeInterruption = false
    #endif
    private var artworkTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?
    private var artworkURL: URL?
    private var currentSong: SpotifySong?
    private var currentIsPlaying = false
    private var currentPosition: TimeInterval = 0
    private var currentDuration: TimeInterval = 0
    private var currentQueueIndex: Int?
    private var currentQueueCount = 0
    private var lastPublishedPosition: TimeInterval = -.infinity

    init(handlers: Handlers) {
        self.handlers = handlers
        configureRemoteCommands()
        #if os(iOS)
        configureAudioSessionNotifications()
        #endif
    }

    deinit {
        artworkTask?.cancel()
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
        #if os(iOS)
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    func prepareForPlayback() throws {
        #if os(iOS)
        try configureAudioSession()
        try AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    func configureAudioSession() throws {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default, options: [])
        #endif
    }

    func update(
        song: SpotifySong?,
        isPlaying: Bool,
        position: TimeInterval,
        duration: TimeInterval,
        queueIndex: Int?,
        queueCount: Int,
        canSkipBackward: Bool,
        canSkipForward: Bool
    ) {
        let songChanged = currentSong?.uri != song?.uri
        let stateChanged = currentIsPlaying != isPlaying
        let durationChanged = abs(currentDuration - duration) > 0.5
        let queueChanged = currentQueueIndex != queueIndex || currentQueueCount != queueCount
        let positionChanged = abs(lastPublishedPosition - position) >= 1

        currentSong = song
        currentIsPlaying = isPlaying
        currentPosition = max(position, 0)
        currentDuration = max(duration, 0)
        currentQueueIndex = queueIndex
        currentQueueCount = queueCount

        updateCommandAvailability(
            hasSong: song != nil,
            isPlaying: isPlaying,
            canSkipBackward: canSkipBackward,
            canSkipForward: canSkipForward,
            canSeek: duration > 0
        )

        guard let song else {
            clear()
            return
        }

        if songChanged {
            loadArtwork(from: song.artworkURL)
        }

        guard songChanged || stateChanged || durationChanged || queueChanged || positionChanged else {
            return
        }
        publish()
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        artwork = nil
        artworkURL = nil
        currentSong = nil
        infoCenter.nowPlayingInfo = nil
        #if os(macOS)
        infoCenter.playbackState = .stopped
        #endif
        updateCommandAvailability(
            hasSong: false,
            isPlaying: false,
            canSkipBackward: false,
            canSkipForward: false,
            canSeek: false
        )
    }

    private func publish() {
        guard let song = currentSong else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artists,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPosition,
            MPNowPlayingInfoPropertyPlaybackRate: currentIsPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyExternalContentIdentifier: song.uri,
        ]

        if let albumName = song.albumName {
            info[MPMediaItemPropertyAlbumTitle] = albumName
        }
        if currentDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = currentDuration
        }
        if let currentQueueIndex, currentQueueCount > 0 {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = currentQueueIndex
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = currentQueueCount
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        infoCenter.nowPlayingInfo = info
        #if os(macOS)
        infoCenter.playbackState = currentIsPlaying ? .playing : .paused
        #endif
        lastPublishedPosition = currentPosition
    }

    private func loadArtwork(from url: URL?) {
        guard artworkURL != url else { return }
        artworkURL = url
        artwork = nil
        artworkTask?.cancel()

        guard let url else {
            publish()
            return
        }

        artworkTask = Task { @MainActor [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse,
                      (200 ..< 300).contains(response.statusCode),
                      let artwork = Self.makeArtwork(from: data) else {
                    return
                }
                guard self?.artworkURL == url else { return }
                self?.artwork = artwork
                self?.publish()
            } catch {
                return
            }
        }
    }

    private static func makeArtwork(from data: Data) -> MPMediaItemArtwork? {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #else
        return nil
        #endif
    }

    private func configureRemoteCommands() {
        addTarget(to: commandCenter.playCommand) { [weak self] _ in
            self?.perform(\Handlers.play)
            return .success
        }
        addTarget(to: commandCenter.pauseCommand) { [weak self] _ in
            self?.perform(\Handlers.pause)
            return .success
        }
        addTarget(to: commandCenter.togglePlayPauseCommand) { [weak self] _ in
            self?.perform(\Handlers.togglePlayback)
            return .success
        }
        addTarget(to: commandCenter.nextTrackCommand) { [weak self] _ in
            self?.perform(\Handlers.nextTrack)
            return .success
        }
        addTarget(to: commandCenter.previousTrackCommand) { [weak self] _ in
            self?.perform(\Handlers.previousTrack)
            return .success
        }
        addTarget(to: commandCenter.changePlaybackPositionCommand) { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.performSeek(positionEvent.positionTime)
            return .success
        }
    }

    #if os(iOS)
    private func configureAudioSessionNotifications() {
        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                Task { @MainActor [weak self] in
                    self?.handleAudioSessionInterruption(rawType, options: rawOptions)
                }
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    try? self?.configureAudioSession()
                }
            }
        )
    }

    private func handleAudioSessionInterruption(_ rawType: UInt?, options rawOptions: UInt?) {
        guard let rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = currentIsPlaying
            if currentIsPlaying {
                handlers.pause()
            }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
            if wasPlayingBeforeInterruption, options.contains(.shouldResume) {
                try? prepareForPlayback()
                handlers.play()
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            wasPlayingBeforeInterruption = false
        }
    }
    #endif

    private func addTarget(
        to command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget(handler: handler)
        commandTargets.append((command, target))
    }

    private func perform(_ action: KeyPath<Handlers, @MainActor () -> Void>) {
        let handler = handlers[keyPath: action]
        Task { @MainActor in handler() }
    }

    private func performSeek(_ position: TimeInterval) {
        let handler = handlers.seek
        Task { @MainActor in handler(position) }
    }

    private func updateCommandAvailability(
        hasSong: Bool,
        isPlaying: Bool,
        canSkipBackward: Bool,
        canSkipForward: Bool,
        canSeek: Bool
    ) {
        commandCenter.playCommand.isEnabled = hasSong && !isPlaying
        commandCenter.pauseCommand.isEnabled = hasSong && isPlaying
        commandCenter.togglePlayPauseCommand.isEnabled = hasSong
        commandCenter.nextTrackCommand.isEnabled = canSkipForward
        commandCenter.previousTrackCommand.isEnabled = canSkipBackward
        commandCenter.changePlaybackPositionCommand.isEnabled = hasSong && canSeek
    }
}
