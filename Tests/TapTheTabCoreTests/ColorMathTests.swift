import XCTest
@testable import TapTheTabCore

final class ColorMathTests: XCTestCase {
    // MARK: Hex

    func testHexParsesSixAndThreeDigitFormsInAnyCase() {
        XCTAssertEqual(SRGBColor(hex: "#ABC")?.hex, "#aabbcc")
        XCTAssertEqual(SRGBColor(hex: " #A1b2C3 ")?.hex, "#a1b2c3")
        XCTAssertEqual(SRGBColor(hex: "a1b2c3")?.hex, "#a1b2c3")
        XCTAssertEqual(SRGBColor(hex: "\n#ffffff\t"), SRGBColor(red: 1, green: 1, blue: 1))
        XCTAssertEqual(SRGBColor(hex: "#000"), SRGBColor(red: 0, green: 0, blue: 0))
        let color = SRGBColor(hex: "#ff8000")
        XCTAssertEqual(color?.red, 1)
        XCTAssertEqual(color?.green ?? 0, 128 / 255, accuracy: 1e-12)
        XCTAssertEqual(color?.blue, 0)
    }

    func testHexRejectsAnythingElse() {
        for bad in ["abc", "#abcd", "#12345g", "", "#", "red", "#1234567", "##abcdef", "# abcdef", "#ab cdef", "0xabcdef", "#ａｂｃ", "+12345"] {
            XCTAssertNil(SRGBColor(hex: bad), bad)
        }
    }

    func testHexRoundTripsEveryThreeDigitColor() {
        let digits = Array("0123456789abcdef")
        for r in digits {
            for g in digits {
                for b in digits {
                    let hex = "#\(r)\(r)\(g)\(g)\(b)\(b)"
                    XCTAssertEqual(SRGBColor(hex: hex)?.hex, hex)
                }
            }
        }
    }

    func testHexClampsAndRoundsComponents() {
        XCTAssertEqual(SRGBColor(red: 1.2, green: -0.1, blue: 0.5).hex, "#ff0080")
        XCTAssertEqual(SRGBColor(red: 0.5, green: 0.5, blue: 0.5).quantized.hex, "#808080")
        XCTAssertEqual(SRGBColor.normalizedHex(" #ABC"), "#aabbcc")
        XCTAssertNil(SRGBColor.normalizedHex("nope"))
    }

    // MARK: OKLab / OKLCH

    func testKnownOKLabValues() {
        // Björn Ottosson's reference values (and CSS Color 4's) for the sRGB primaries.
        let known: [(String, Double, Double, Double)] = [
            ("#ff0000", 0.627955, 0.224863, 0.125846),
            ("#00ff00", 0.86644, -0.233888, 0.179498),
            ("#0000ff", 0.452014, -0.032457, -0.311528),
            ("#ffffff", 1, 0, 0),
            ("#000000", 0, 0, 0),
        ]
        for (hex, l, a, b) in known {
            let lab = OKLab(SRGBColor(hex: hex)!)
            XCTAssertEqual(lab.l, l, accuracy: 5e-5, hex)
            XCTAssertEqual(lab.a, a, accuracy: 5e-5, hex)
            XCTAssertEqual(lab.b, b, accuracy: 5e-5, hex)
        }
        let red = OKLCH(SRGBColor(hex: "#ff0000")!)
        XCTAssertEqual(red.c, 0.257683, accuracy: 5e-5)
        XCTAssertEqual(red.h, 29.2339, accuracy: 5e-4)
        // A grey has no hue: 0, not NaN.
        let grey = OKLCH(SRGBColor(hex: "#808080")!)
        XCTAssertEqual(grey.h, 0)
        XCTAssertEqual(grey.c, 0, accuracy: 1e-6)
    }

    func testHueIsInZeroToThreeSixty() {
        // Blue sits at a negative atan2 angle; the hue must wrap into 0..<360.
        let blue = OKLCH(SRGBColor(hex: "#0000ff")!)
        XCTAssertEqual(blue.h, 264.052, accuracy: 1e-3)
        for hex in ["#ff0000", "#00ff00", "#0000ff", "#ff00ff", "#00ffff", "#ffff00", "#123456"] {
            let h = OKLCH(SRGBColor(hex: hex)!).h
            XCTAssertTrue((0..<360).contains(h), hex)
        }
    }

    func testEveryThreeDigitColorRoundTripsThroughOKLabAndOKLCH() {
        let digits = Array("0123456789abcdef")
        for r in digits {
            for g in digits {
                for b in digits {
                    let hex = "#\(r)\(r)\(g)\(g)\(b)\(b)"
                    let lab = OKLab(SRGBColor(hex: hex)!)
                    XCTAssertEqual(lab.rgb.hex, hex)
                    XCTAssertEqual(OKLCH(lab).rgb.hex, hex)
                }
            }
        }
    }

    func testOKLabAndOKLCHGoBothWays() {
        let lab = OKLab(l: 0.7, a: -0.05, b: 0.08)
        let back = OKLab(OKLCH(lab))
        XCTAssertEqual(back.l, lab.l, accuracy: 1e-9)
        XCTAssertEqual(back.a, lab.a, accuracy: 1e-9)
        XCTAssertEqual(back.b, lab.b, accuracy: 1e-9)
        let rgb = SRGBColor(red: 0.2, green: 0.4, blue: 0.6)
        let again = OKLab(rgb).rgb
        XCTAssertEqual(again.red, rgb.red, accuracy: 1e-6)
        XCTAssertEqual(again.green, rgb.green, accuracy: 1e-6)
        XCTAssertEqual(again.blue, rgb.blue, accuracy: 1e-6)
    }

    func testTransferCurveIsOddAndInvertible() {
        for x in [-1.5, -0.5, -0.01, 0, 0.002, 0.04, 0.3, 0.9, 1, 1.3] {
            XCTAssertEqual(linearToSrgb(srgbToLinear(x)), x, accuracy: 1e-12)
            XCTAssertEqual(srgbToLinear(-x), -srgbToLinear(x))
        }
    }

    // MARK: Gamut and mixing

    func testFittingLowersChromaUntilSRGBCanShowTheColor() {
        let wild = OKLCH(l: 0.9, c: 0.3, h: 260)
        XCTAssertFalse(OKLab(wild).rgb.isInGamut)
        let fitted = wild.fittedToGamut
        XCTAssertTrue(OKLab(fitted).rgb.isInGamut)
        XCTAssertEqual(fitted.l, 0.9)
        XCTAssertEqual(fitted.h, 260)
        XCTAssertLessThan(fitted.c, 0.3)
        XCTAssertGreaterThan(fitted.c, 0.01)
        let tame = OKLCH(l: 0.6, c: 0.05, h: 120)
        XCTAssertEqual(tame.fittedToGamut, tame)
    }

    func testFittingClampsLightnessAndNegativeChroma() {
        XCTAssertEqual(OKLCH(l: 1.4, c: 0, h: 10).fittedToGamut.l, 1)
        XCTAssertEqual(OKLCH(l: -0.2, c: 0, h: 10).fittedToGamut.l, 0)
        XCTAssertEqual(OKLCH(l: 0.5, c: -0.1, h: 10).fittedToGamut.c, 0)
    }

    func testFittedColorsStayInsideTheGamut() {
        var generator = SplitMix64(seed: 3)
        for _ in 0..<500 {
            let lch = OKLCH(
                l: Double.random(in: -0.1...1.1, using: &generator),
                c: Double.random(in: 0...0.5, using: &generator),
                h: Double.random(in: 0..<360, using: &generator)
            )
            let rgb = OKLab(lch.fittedToGamut).rgb
            XCTAssertTrue(rgb.isInGamut, "\(lch)")
            let clamped = lch.rgb
            for value in [clamped.red, clamped.green, clamped.blue] {
                XCTAssertTrue((0...1).contains(value), "\(lch)")
            }
        }
    }

    func testMixesInOKLab() {
        let a = OKLab(l: 0.2, a: 0.1, b: -0.1)
        let b = OKLab(l: 0.8, a: -0.1, b: 0.1)
        XCTAssertEqual(a.mixed(with: b, 0), a)
        XCTAssertEqual(a.mixed(with: b, 1), b)
        let mid = a.mixed(with: b, 0.5)
        XCTAssertEqual(mid.l, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mid.a, 0, accuracy: 1e-9)
        XCTAssertEqual(mid.b, 0, accuracy: 1e-9)
    }
}
