import SwiftUI

struct SongOptionsMenu: View {
    @ObservedObject var player: PlayerModel
    let song: SpotifySong
    var allowsPlaylistRemoval = false
    var labelWidth: CGFloat = 32
    var labelHeight: CGFloat = 40
    var labelForegroundColor: Color = .primary
    var onNavigate: (() -> Void)?

    var body: some View {
        Menu {
            Button(
                player.isSaved(song) ? "Remove from Songs" : "Save to Songs",
                systemImage: player.isSaved(song) ? "star.slash" : "star"
            ) {
                player.toggleSaved(song)
            }

            let downloaded = player.isDownloaded(song)
            Button(
                downloaded ? "Remove Download" : "Download",
                systemImage: downloaded ? "arrow.down.circle.fill" : "arrow.down.circle"
            ) {
                if downloaded {
                    player.removeDownloadedTrack(song)
                } else {
                    player.downloadTrack(song)
                }
            }

            Divider()

            if song.albumName != nil {
                Button("Go to Album", systemImage: "square.stack") {
                    onNavigate?()
                    player.goToAlbum(for: song)
                }
            }

            if !song.artists.isEmpty {
                Button("Go to Artist", systemImage: "person.crop.circle") {
                    onNavigate?()
                    player.goToArtist(for: song)
                }
            }

            Divider()

            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext(song)
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.playLast(song)
            }

            if !player.editablePlaylists.isEmpty {
                Menu("Add to Playlist", systemImage: "text.badge.plus") {
                    ForEach(player.editablePlaylists) { playlist in
                        Button(playlist.name) {
                            Task { await player.add(song, to: playlist) }
                        }
                    }
                }
            }

            if allowsPlaylistRemoval {
                Divider()
                Button("Remove from Playlist", systemImage: "trash", role: .destructive) {
                    Task { await player.removeFromSelectedPlaylist(song) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(labelForegroundColor)
                .frame(width: labelWidth, height: labelHeight)
                .contentShape(.rect)
        }
        .menuIndicator(.hidden)
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .help("More")
        #endif
    }
}
