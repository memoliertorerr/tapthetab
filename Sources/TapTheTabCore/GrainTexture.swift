import Foundation

/// Film grain for themes: a square tile of gray-level noise, drawn over the gradient at
/// `ThemeGradient.grainOpacity`. Every pixel is independent of its neighbours, so the tile
/// repeats without a seam.
public enum GrainTexture {
    public static let defaultSide = 128
    public static let defaultSeed: UInt64 = 0x7454_5442_6772_6E21
    static let sideRange = 1...512

    /// Gray-level noise pixels, `side × side`, row-major, one byte per pixel (0 = black speck,
    /// 255 = white), uniform over 0...255 and deterministic for a seed. `side` is clamped to 1...512.
    public static func pixels(side: Int, seed: UInt64) -> [UInt8] {
        let side = min(sideRange.upperBound, max(sideRange.lowerBound, side))
        var generator = SplitMix64(seed: seed)
        var pixels = [UInt8](repeating: 0, count: side * side)
        var index = 0
        // Eight pixels from each 64-bit draw.
        while index < pixels.count {
            var bits = generator.next()
            for _ in 0..<8 where index < pixels.count {
                pixels[index] = UInt8(truncatingIfNeeded: bits)
                bits >>= 8
                index += 1
            }
        }
        return pixels
    }
}

/// SplitMix64 (Steele, Lea & Flood): small, fast and the same on every platform.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
