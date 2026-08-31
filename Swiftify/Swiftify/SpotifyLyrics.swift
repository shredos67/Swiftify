import Foundation

struct SpotifyLyrics: Decodable, Equatable {
    let language: String
    let provider: String
    let syncType: String
    let lines: [SpotifyLyricLine]
    let colors: SpotifyLyricsColors

    var isSynchronized: Bool {
        syncType == "lineSynced"
    }
}

struct SpotifyLyricLine: Decodable, Equatable, Identifiable {
    let startTimeMs: UInt32
    let endTimeMs: UInt32
    let words: String

    var id: String {
        "\(startTimeMs)-\(endTimeMs)-\(words)"
    }
}

struct SpotifyLyricsColors: Decodable, Equatable {
    let background: Int32
    let text: Int32
    let highlightText: Int32
}

enum PlaybackRepeatMode: CaseIterable, Equatable {
    case off
    case all
    case one

    var symbolName: String {
        switch self {
        case .off, .all:
            "repeat"
        case .one:
            "repeat.1"
        }
    }

    var helpText: String {
        switch self {
        case .off:
            "Repeat off"
        case .all:
            "Repeat queue"
        case .one:
            "Repeat song"
        }
    }

    var next: Self {
        switch self {
        case .off:
            .all
        case .all:
            .one
        case .one:
            .off
        }
    }
}
