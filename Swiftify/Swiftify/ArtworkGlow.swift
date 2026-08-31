import SwiftUI

extension View {
    func artworkBackdropGlow(
        colors: [Color],
        intensity: Double = 0.26,
        radius: CGFloat = 24
    ) -> some View {
        modifier(
            ArtworkBackdropGlowModifier(
                colors: colors,
                intensity: intensity,
                radius: radius
            )
        )
    }
}

private struct ArtworkBackdropGlowModifier: ViewModifier {
    let colors: [Color]
    let intensity: Double
    let radius: CGFloat

    func body(content: Content) -> some View {
        let primary = colors.first ?? MusicStyle.accent
        let secondary = colors.dropFirst().first ?? primary

        content
            .shadow(
                color: primary.opacity(intensity),
                radius: radius,
                x: -radius * 0.22,
                y: radius * 0.12
            )
            .shadow(
                color: secondary.opacity(intensity * 0.72),
                radius: radius * 0.82,
                x: radius * 0.24,
                y: -radius * 0.08
            )
    }
}
