import XCTest
@testable import TapTheTabCore

final class GrainTextureTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(GrainTexture.defaultSide, 128)
        XCTAssertEqual(GrainTexture.pixels(side: GrainTexture.defaultSide, seed: GrainTexture.defaultSeed).count, 128 * 128)
    }

    func testIsDeterministicForASeed() {
        let a = GrainTexture.pixels(side: 64, seed: 42)
        XCTAssertEqual(GrainTexture.pixels(side: 64, seed: 42), a)
        XCTAssertEqual(GrainTexture.pixels(side: GrainTexture.defaultSide, seed: GrainTexture.defaultSeed),
                       GrainTexture.pixels(side: GrainTexture.defaultSide, seed: GrainTexture.defaultSeed))
    }

    func testIsStableAcrossVersionsAndPlatforms() {
        // SplitMix64's published outputs for seed 0 (0xe220a8397b1dcdaf, 0x6e789e6aa1b965f4), byte by byte.
        var generator = SplitMix64(seed: 0)
        XCTAssertEqual(generator.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(GrainTexture.pixels(side: 3, seed: 0), [0xAF, 0xCD, 0x1D, 0x7B, 0x39, 0xA8, 0x20, 0xE2, 0xF4])
    }

    func testDifferentSeedsDiffer() {
        let a = GrainTexture.pixels(side: 32, seed: 1)
        let b = GrainTexture.pixels(side: 32, seed: 2)
        XCTAssertNotEqual(a, b)
        let same = zip(a, b).filter { $0 == $1 }.count
        // Independent noise agrees on about 1 pixel in 256.
        XCTAssertLessThan(same, 32 * 32 / 50)
    }

    func testIsFullContrastNoise() {
        let pixels = GrainTexture.pixels(side: 128, seed: GrainTexture.defaultSeed)
        let values = pixels.map(Double.init)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        // Uniform over 0...255: mean 127.5, variance (256² − 1) / 12 ≈ 5461.
        XCTAssertEqual(mean, 127.5, accuracy: 2)
        XCTAssertEqual(variance, 5461, accuracy: 250)
        XCTAssertEqual(pixels.min(), 0)
        XCTAssertEqual(pixels.max(), 255)
        // Every gray level shows up, none much more often than the rest.
        var histogram = [Int](repeating: 0, count: 256)
        for pixel in pixels { histogram[Int(pixel)] += 1 }
        XCTAssertGreaterThan(histogram.min() ?? 0, 20)
        XCTAssertLessThan(histogram.max() ?? .max, 110)
    }

    func testNeighboursAreUncorrelated() {
        let side = 128
        let pixels = GrainTexture.pixels(side: side, seed: 9).map { Double($0) - 127.5 }
        func correlation(_ offset: (Int, Int)) -> Double {
            var sum = 0.0
            var energy = 0.0
            for y in 0..<side {
                for x in 0..<side {
                    let a = pixels[y * side + x]
                    let b = pixels[((y + offset.1) % side) * side + (x + offset.0) % side]
                    sum += a * b
                    energy += a * a
                }
            }
            return sum / energy
        }
        // Wrapping around the edge too: the tile has no seam.
        XCTAssertLessThan(abs(correlation((1, 0))), 0.05)
        XCTAssertLessThan(abs(correlation((0, 1))), 0.05)
        XCTAssertLessThan(abs(correlation((1, 1))), 0.05)
    }

    func testSideIsClamped() {
        XCTAssertEqual(GrainTexture.pixels(side: 0, seed: 1).count, 1)
        XCTAssertEqual(GrainTexture.pixels(side: -5, seed: 1).count, 1)
        XCTAssertEqual(GrainTexture.pixels(side: 1, seed: 1).count, 1)
        XCTAssertEqual(GrainTexture.pixels(side: 513, seed: 1).count, 512 * 512)
        XCTAssertEqual(GrainTexture.pixels(side: .max, seed: 1).count, 512 * 512)
        XCTAssertEqual(GrainTexture.pixels(side: 7, seed: 1).count, 49)
    }

    func testSmallerTilesStartLikeLargerOnes() {
        // The stream is laid out row-major, so a 4×4 tile is the first 16 pixels of an 8×8 one's stream.
        XCTAssertEqual(GrainTexture.pixels(side: 4, seed: 3), Array(GrainTexture.pixels(side: 8, seed: 3).prefix(16)))
    }
}
