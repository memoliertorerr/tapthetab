import Foundation

// Color math for themes: hex ↔ sRGB ↔ OKLab ↔ OKLCH, fitting a color into the sRGB gamut and
// mixing in OKLab. Ported from Little Joan's `ui/lib/color.ts` (MIT, same author). Matrices:
// Björn Ottosson, "A perceptual color space for image processing" (2020).

/// sRGB color, components 0...1.
public struct RGBColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// "#rrggbb" or "rrggbb" or "#rgb", case-insensitive, whitespace trimmed; nil otherwise.
    public init?(hex: String) {
        guard let digits = RGBColor.hexDigits(hex) else { return nil }
        func channel(_ index: Int) -> Double { Double(digits[index] * 16 + digits[index + 1]) / 255 }
        self.init(red: channel(0), green: channel(2), blue: channel(4))
    }

    /// Lowercase "#rrggbb" (components clamped into 0...1 first).
    public var hex: String {
        let table = Array("0123456789abcdef")
        var text = "#"
        for value in [red, green, blue] {
            let byte = Int((clampToUnit(value) * 255).rounded())
            text.append(table[byte / 16])
            text.append(table[byte % 16])
        }
        return text
    }

    /// `hex` normalized to lowercase "#rrggbb", or nil when it is not a color.
    static func normalizedHex(_ hex: String) -> String? {
        RGBColor(hex: hex)?.hex
    }

    /// Six hex digit values for `text` (a 3-digit form expanded), or nil.
    private static func hexDigits(_ text: String) -> [Int]? {
        var scalars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars)
        let hasHash = scalars.first == "#"
        if hasHash { scalars.removeFirst() }
        // "#rgb" needs its "#": a bare "abc" is too likely to be something else.
        guard scalars.count == 6 || (hasHash && scalars.count == 3) else { return nil }
        var digits: [Int] = []
        for scalar in scalars {
            switch scalar.value {
            case 0x30...0x39: digits.append(Int(scalar.value - 0x30))
            case 0x41...0x46: digits.append(Int(scalar.value - 0x41 + 10))
            case 0x61...0x66: digits.append(Int(scalar.value - 0x61 + 10))
            default: return nil
            }
        }
        return digits.count == 3 ? digits.flatMap { [$0, $0] } : digits
    }

    /// Whether every component is within 0...1 (with a tiny tolerance).
    var isInGamut: Bool {
        let epsilon = 1e-6
        return [red, green, blue].allSatisfy { $0 >= -epsilon && $0 <= 1 + epsilon }
    }

    /// Components clamped into 0...1.
    var clamped: RGBColor {
        RGBColor(red: clampToUnit(red), green: clampToUnit(green), blue: clampToUnit(blue))
    }

    /// Rounded to the nearest 8-bit-per-channel color (what `hex` writes).
    var quantized: RGBColor {
        func step(_ x: Double) -> Double { (clampToUnit(x) * 255).rounded() / 255 }
        return RGBColor(red: step(red), green: step(green), blue: step(blue))
    }
}

/// OKLab: lightness 0...1 and two opponent axes.
struct OKLab: Equatable, Sendable {
    var l: Double
    var a: Double
    var b: Double

    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    init(_ rgb: RGBColor) {
        let r = srgbToLinear(rgb.red)
        let g = srgbToLinear(rgb.green)
        let b = srgbToLinear(rgb.blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        self.init(
            l: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        )
    }

    init(_ lch: OKLCH) {
        let angle = lch.h * .pi / 180
        self.init(l: lch.l, a: lch.c * cos(angle), b: lch.c * sin(angle))
    }

    /// The sRGB color; components fall outside 0...1 when sRGB can't show it.
    var rgb: RGBColor {
        let l = pow(self.l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(self.l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(self.l - 0.0894841775 * a - 1.291485548 * b, 3)
        return RGBColor(
            red: linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            green: linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            blue: linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s)
        )
    }

    /// The point `t` (0...1) of the way to `other`, in OKLab (no hue detours, no grey dip).
    func mixed(with other: OKLab, _ t: Double) -> OKLab {
        OKLab(l: l + (other.l - l) * t, a: a + (other.a - a) * t, b: b + (other.b - b) * t)
    }
}

/// OKLCH: lightness 0...1, chroma (0 = grey), hue in degrees 0..<360.
struct OKLCH: Equatable, Sendable {
    var l: Double
    var c: Double
    var h: Double

    init(l: Double, c: Double, h: Double) {
        self.l = l
        self.c = c
        self.h = h
    }

    init(_ lab: OKLab) {
        let c = hypot(lab.a, lab.b)
        // A grey has no hue; 0 keeps the result stable.
        let degrees = (atan2(lab.b, lab.a) * 180 / .pi).truncatingRemainder(dividingBy: 360)
        let h = c < 1e-7 ? 0 : (degrees + 360).truncatingRemainder(dividingBy: 360)
        self.init(l: lab.l, c: c, h: h)
    }

    init(_ rgb: RGBColor) {
        self.init(OKLab(rgb))
    }

    /// This color with its chroma lowered (lightness clamped to 0...1, hue kept) until sRGB can
    /// show it: CSS Color 4's idea, without the "just noticeable difference" shortcut.
    var fittedToGamut: OKLCH {
        let l = clampToUnit(self.l)
        let c = max(0, self.c)
        func fits(_ chroma: Double) -> Bool { OKLab(OKLCH(l: l, c: chroma, h: h)).rgb.isInGamut }
        if fits(c) { return OKLCH(l: l, c: c, h: h) }
        var low = 0.0
        var high = c
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if fits(mid) { low = mid } else { high = mid }
        }
        return OKLCH(l: l, c: low, h: h)
    }

    /// The sRGB color, fitted into the gamut first (so components are within 0...1).
    var rgb: RGBColor {
        OKLab(fittedToGamut).rgb.clamped
    }
}

@inline(__always)
func clampToUnit(_ x: Double) -> Double {
    min(1, max(0, x))
}

// The sRGB transfer curve, kept odd so out-of-gamut (negative) values survive a round trip.
func srgbToLinear(_ x: Double) -> Double {
    let magnitude = abs(x)
    let linear = magnitude <= 0.04045 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
    return x < 0 ? -linear : linear
}

func linearToSrgb(_ x: Double) -> Double {
    let magnitude = abs(x)
    let encoded = magnitude <= 0.0031308 ? 12.92 * magnitude : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
    return x < 0 ? -encoded : encoded
}
