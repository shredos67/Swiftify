import Foundation
import SwiftUI

struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    var cornerRadius: CGFloat = 8

    private var request: URLRequest? {
        guard let url else {
            return nil
        }

        return URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 30
        )
    }

    var body: some View {
        AsyncImage(
            request: request,
            transaction: Transaction(animation: .easeInOut(duration: 0.2))
        ) { phase in
            Group {
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MusicStyle.accent.opacity(0.24),
                    MusicStyle.deepGreen.opacity(0.2),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "music.note")
                .font(.system(size: size * 0.3, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
