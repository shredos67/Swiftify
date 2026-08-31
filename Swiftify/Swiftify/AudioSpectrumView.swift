//
//  AudioSpectrumView.swift
//  Swiftify
//
//  Created by Codex on 2026-08-27.
//

import Combine
import Foundation
import SwiftUI

func bassExpandedSpectrumLevels(
    _ levels: [CGFloat],
    perSideCount: Int
) -> [CGFloat] {
    guard !levels.isEmpty, perSideCount > 0 else {
        return []
    }

    let bassBarFraction: CGFloat = 0.46
    let bassBandFraction: CGFloat = 0.30

    return (0 ..< perSideCount).map { index in
        let progress = perSideCount == 1
            ? CGFloat.zero
            : CGFloat(index) / CGFloat(perSideCount - 1)
        let sourceProgress: CGFloat

        if progress <= bassBarFraction {
            sourceProgress = progress / bassBarFraction * bassBandFraction
        } else {
            sourceProgress = bassBandFraction
                + (progress - bassBarFraction) / (1 - bassBarFraction)
                    * (1 - bassBandFraction)
        }

        let position = sourceProgress * CGFloat(levels.count - 1)
        let lowerIndex = min(max(Int(position.rounded(.down)), 0), levels.count - 1)
        let upperIndex = min(lowerIndex + 1, levels.count - 1)
        let blend = position - CGFloat(lowerIndex)
        let rawLevel = levels[lowerIndex] * (1 - blend) + levels[upperIndex] * blend
        let bassInfluence = max(0, 1 - sourceProgress / 0.42)
        let sensitivity = 1 + bassInfluence * 0.58
        let responseCurve = 0.92 - bassInfluence * 0.14
        return min(pow(max(rawLevel, 0), responseCurve) * sensitivity, 1)
    }
}

@MainActor
final class AudioSpectrumModel: ObservableObject {
    @Published private(set) var levels = Array(repeating: CGFloat.zero, count: 48)
    @Published private(set) var gradientColors: [Color] = [
        MusicStyle.accent,
        MusicStyle.accentSecondary,
    ]

    private var artworkURL: URL?
    private var paletteTask: Task<Void, Never>?

    func update(_ levels: [CGFloat]) {
        self.levels = levels
    }

    func setArtwork(_ url: URL?) {
        guard url != artworkURL else {
            return
        }

        artworkURL = url
        paletteTask?.cancel()
        gradientColors = [MusicStyle.accent, MusicStyle.accentSecondary]

        guard let url else {
            return
        }

        paletteTask = Task { [weak self] in
            do {
                let request = URLRequest(
                    url: url,
                    cachePolicy: .useProtocolCachePolicy,
                    timeoutInterval: 30
                )
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()

                guard
                    let response = response as? HTTPURLResponse,
                    (200 ..< 300).contains(response.statusCode),
                    let colors = ArtworkPalette.colors(from: data)
                else {
                    return
                }

                self?.gradientColors = colors
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func clear() {
        guard levels.contains(where: { $0 > 0 }) else {
            return
        }

        levels = Array(repeating: .zero, count: levels.count)
    }
}

struct AudioSpectrumView: View {
    @ObservedObject var spectrum: AudioSpectrumModel
    let isActive: Bool
    var width: CGFloat = 32
    var height: CGFloat = 38

    private let barSpacing: CGFloat = 2.6

    var body: some View {
        GeometryReader { geometry in
            let levels = compactLevels
            let barCount = levels.count
            let availableWidth = geometry.size.width - barSpacing * CGFloat(barCount - 1)
            let barWidth = max(1, availableWidth / CGFloat(barCount))
            let minimumBarHeight = min(4, max(2, geometry.size.height * 0.2))
            let bars = HStack(alignment: .center, spacing: barSpacing) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .frame(
                            width: barWidth,
                            height: max(
                                minimumBarHeight,
                                geometry.size.height
                                    * (0.08 + 0.92 * levels[index].clamped(to: 0...1))
                            )
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            let colors = spectrum.gradientColors.isEmpty
                ? [MusicStyle.accent, MusicStyle.accentSecondary]
                : spectrum.gradientColors
            let primaryColor = colors[0]

            LinearGradient(
                colors: colors,
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .mask { bars }
            .shadow(
                color: primaryColor.opacity(0.32),
                radius: 2
            )
        }
        .frame(width: width, height: height)
        .opacity(isActive ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isActive ? "Live audio spectrum" : "Paused")
    }

    private var compactLevels: [CGFloat] {
        let compactCount = 6
        guard !spectrum.levels.isEmpty else {
            return Array(repeating: .zero, count: compactCount)
        }

        return (0 ..< compactCount).map { compactIndex in
            let lowerBound = compactIndex * spectrum.levels.count / compactCount
            let upperBound = max(
                lowerBound + 1,
                (compactIndex + 1) * spectrum.levels.count / compactCount
            )
            let band = spectrum.levels[lowerBound ..< min(upperBound, spectrum.levels.count)]
            let peak = band.max() ?? 0
            let rootMeanSquare = sqrt(
                band.reduce(CGFloat.zero) { $0 + $1 * $1 } / CGFloat(max(band.count, 1))
            )
            return (rootMeanSquare * 0.72 + peak * 0.28).clamped(to: 0 ... 1)
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
