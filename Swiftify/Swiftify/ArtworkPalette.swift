import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

enum ArtworkPalette {
    static func colors(from data: Data) -> [Color]? {
        let gridSize = 12
        var pixels = [UInt8](repeating: 0, count: gridSize * gridSize * 4)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: gridSize,
                  height: gridSize,
                  bitsPerComponent: 8,
                  bytesPerRow: gridSize * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize))

        var buckets: [Int: ColorBucket] = [:]

        for row in 0 ..< gridSize {
            for column in 0 ..< gridSize {
                let offset = (row * gridSize + column) * 4
                guard pixels[offset + 3] > 127 else { continue }

                let pixel = Pixel(
                    red: Double(pixels[offset]) / 255,
                    green: Double(pixels[offset + 1]) / 255,
                    blue: Double(pixels[offset + 2]) / 255
                )
                let key = pixel.quantizedKey
                buckets[key, default: ColorBucket()].add(pixel)
            }
        }

        let candidates = buckets.values
            .map { bucket in
                let pixel = bucket.average
                return Candidate(
                    pixel: pixel,
                    score: pixel.paletteScore * Double(bucket.count)
                )
            }
            .sorted { $0.score > $1.score }

        guard let primaryCandidate = candidates.first else {
            return nil
        }

        let primary = primaryCandidate.pixel.adjustedForDisplay
        let secondaryCandidate = candidates.dropFirst().max { left, right in
            secondaryScore(left, from: primaryCandidate.pixel)
                < secondaryScore(right, from: primaryCandidate.pixel)
        }
        var secondary = (secondaryCandidate?.pixel ?? primary.mixed(with: .white, amount: 0.4))
            .adjustedForDisplay

        if primary.distance(to: secondary) < 0.16 {
            secondary = primary.mixed(with: .white, amount: 0.42).adjustedForDisplay
        }

        return [primary.swiftUIColor, secondary.swiftUIColor]
    }

    private static func secondaryScore(_ candidate: Candidate, from primary: Pixel) -> Double {
        candidate.score * (0.35 + primary.distance(to: candidate.pixel) * 2.8)
    }
}

private struct Candidate {
    let pixel: Pixel
    let score: Double
}

private struct ColorBucket {
    private(set) var count = 0
    private var red = 0.0
    private var green = 0.0
    private var blue = 0.0

    mutating func add(_ pixel: Pixel) {
        count += 1
        red += pixel.red
        green += pixel.green
        blue += pixel.blue
    }

    var average: Pixel {
        let divisor = Double(max(count, 1))
        return Pixel(red: red / divisor, green: green / divisor, blue: blue / divisor)
    }
}

private struct Pixel {
    let red: Double
    let green: Double
    let blue: Double

    static let white = Pixel(red: 1, green: 1, blue: 1)

    var quantizedKey: Int {
        let redBucket = Int((red * 5).rounded(.down))
        let greenBucket = Int((green * 5).rounded(.down))
        let blueBucket = Int((blue * 5).rounded(.down))
        return redBucket << 16 | greenBucket << 8 | blueBucket
    }

    var paletteScore: Double {
        let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
        let chroma = max(red, green, blue) - min(red, green, blue)
        let balancedExposure = max(0.15, 1 - abs(luminance - 0.55) * 1.6)
        return (0.3 + chroma * 1.7) * (0.45 + balancedExposure)
    }

    var adjustedForDisplay: Pixel {
        let average = (red + green + blue) / 3
        var adjusted = Pixel(
            red: average + (red - average) * 1.25,
            green: average + (green - average) * 1.25,
            blue: average + (blue - average) * 1.25
        ).clamped

        let brightness = max(adjusted.red, adjusted.green, adjusted.blue)
        if brightness < 0.48 {
            adjusted = adjusted.mixed(with: .white, amount: (0.48 - brightness) * 0.8)
        } else if brightness > 0.94 {
            adjusted = adjusted.mixed(with: Pixel(red: 0.72, green: 0.72, blue: 0.72), amount: 0.2)
        }

        return adjusted.clamped
    }

    var clamped: Pixel {
        Pixel(
            red: red.clamped(to: 0 ... 1),
            green: green.clamped(to: 0 ... 1),
            blue: blue.clamped(to: 0 ... 1)
        )
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    func distance(to other: Pixel) -> Double {
        let redDistance = red - other.red
        let greenDistance = green - other.green
        let blueDistance = blue - other.blue
        return ((redDistance * redDistance + greenDistance * greenDistance + blueDistance * blueDistance) / 3)
            .squareRoot()
    }

    func mixed(with other: Pixel, amount: Double) -> Pixel {
        let amount = amount.clamped(to: 0 ... 1)
        return Pixel(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
