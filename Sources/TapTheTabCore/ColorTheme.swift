import Foundation

// Arc-style themes for the switcher panel, ported from Little Joan's `ui/lib/theme.ts` and
// `presets.ts` (MIT, same author). One to three colors, an intensity and a grain become a soft,
// muted gradient. Harmony comes from the derivation, not from the picks: each pick keeps its
// hue, its lightness is mapped into a narrow band (light 0.86–0.93, dark 0.22–0.32) and its
// chroma capped at 0.12 × intensity, so any three picks blend and the system's label colors
// stay readable on top.

/// Light or dark, which a theme is drawn for (the panel's resolved appearance).
public enum ThemeScheme: String, Sendable, CaseIterable {
    case light, dark

    /// The backgrounds' OKLCH lightness band.
    public var lightnessBand: ClosedRange<Double> {
        switch self {
        case .light: return 0.86...0.93
        case .dark: return 0.22...0.32
        }
    }
}

/// A built-in theme: colors, intensity and grain.
public struct ThemePreset: Equatable, Sendable, Identifiable {
    public let id: String
    /// English name; the app localizes.
    public let name: String
    /// "#rrggbb".
    public let colors: [String]
    public let intensity: Double
    public let grain: Double

    public init(id: String, name: String, colors: [String], intensity: Double, grain: Double) {
        self.id = id
        self.name = name
        self.colors = colors
        self.intensity = intensity
        self.grain = grain
    }

    /// Little Joan's presets, in its order. The first is the default look.
    public static let all: [ThemePreset] = [
        ThemePreset(id: "mist", name: "Mist", colors: ["#8c9bb5"], intensity: 0.45, grain: 0.15),
        ThemePreset(id: "sand", name: "Sand", colors: ["#c9a27e", "#d8c49a"], intensity: 0.55, grain: 0.3),
        ThemePreset(id: "sage", name: "Sage", colors: ["#8fae96", "#b9b98c"], intensity: 0.55, grain: 0.25),
        ThemePreset(id: "lagoon", name: "Lagoon", colors: ["#6fa8c4", "#7fc2ab"], intensity: 0.6, grain: 0.25),
        ThemePreset(id: "dusk", name: "Dusk", colors: ["#9d8fd0", "#e0a2a0"], intensity: 0.6, grain: 0.3),
        ThemePreset(id: "ember", name: "Ember", colors: ["#d98f74", "#d6b067"], intensity: 0.55, grain: 0.35),
        ThemePreset(id: "orchid", name: "Orchid", colors: ["#c294cf", "#8ea3dc"], intensity: 0.55, grain: 0.2),
        ThemePreset(id: "glacier", name: "Glacier", colors: ["#94bce2", "#a9d8d2", "#c7bfe8"], intensity: 0.5, grain: 0.2),
        ThemePreset(id: "meadow", name: "Meadow", colors: ["#a3c27a", "#78b8a6", "#dcc67d"], intensity: 0.55, grain: 0.3),
        ThemePreset(id: "berry", name: "Berry", colors: ["#cf86a5", "#958acf", "#e8ae96"], intensity: 0.6, grain: 0.3),
        ThemePreset(id: "graphite", name: "Graphite", colors: ["#7d828c"], intensity: 0.2, grain: 0.35),
    ]

    public static func named(_ id: String) -> ThemePreset? {
        all.first { $0.id == id }
    }

    static let mist = all[0]
}

/// The switcher's color theme. Stored in config.json as `appearance.colorTheme`.
public struct ColorTheme: Codable, Equatable, Sendable {
    /// "none" (no theme: the backdrop alone), a preset id, or "custom".
    public var preset: String
    /// 1–3 colors "#rrggbb" (used for "custom"; for a preset, the preset's colors are stored too).
    public var colors: [String]
    /// 0–1: how much color (chroma) the gradient gets.
    public var intensity: Double
    /// 0–1: grain strength.
    public var grain: Double
    /// 0–1: how much the gradient covers the glass/blur behind it (0 = invisible, 1 = opaque).
    public var opacity: Double

    public static let noneID = "none"
    public static let customID = "custom"
    public static let defaultOpacity: Double = 0.55
    public static let maxColors = 3

    /// No theme; Mist's colors, intensity and grain are kept for when one is turned on.
    public static let none = ColorTheme(
        preset: noneID,
        colors: ThemePreset.mist.colors,
        intensity: ThemePreset.mist.intensity,
        grain: ThemePreset.mist.grain,
        opacity: defaultOpacity
    )

    public init(preset: String, colors: [String], intensity: Double, grain: Double, opacity: Double = ColorTheme.defaultOpacity) {
        self.preset = preset
        self.colors = colors
        self.intensity = intensity
        self.grain = grain
        self.opacity = opacity
    }

    public var isEnabled: Bool { preset != Self.noneID }

    /// A theme from a preset (opacity kept from `self`).
    public func applying(_ preset: ThemePreset) -> ColorTheme {
        ColorTheme(preset: preset.id, colors: preset.colors, intensity: preset.intensity, grain: preset.grain, opacity: opacity)
    }

    /// Copy with every value made valid (the same rules as decoding); idempotent.
    public func validated() -> ColorTheme {
        let fallback = ColorTheme.none
        let id = preset.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let knownID = id == Self.noneID || id == Self.customID || ThemePreset.named(id) != nil
        let hexes = colors.compactMap(RGBColor.normalizedHex).prefix(Self.maxColors)
        func unit(_ value: Double, _ fallback: Double) -> Double {
            value.isFinite ? clampToUnit(value) : fallback
        }
        return ColorTheme(
            preset: knownID ? id : Self.customID,
            colors: hexes.isEmpty ? fallback.colors : Array(hexes),
            intensity: unit(intensity, fallback.intensity),
            grain: unit(grain, fallback.grain),
            opacity: unit(opacity, fallback.opacity)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case preset, colors, intensity, grain, opacity
    }

    /// Lenient: every key is optional and a bad value falls back to `.none`'s value for that
    /// key only; then the result is `validated()`.
    public init(from decoder: Decoder) throws {
        let fallback = ColorTheme.none
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = fallback
            return
        }
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }
        let colors = value([LossyString].self, .colors)?.compactMap(\.value)
        self = ColorTheme(
            preset: value(String.self, .preset) ?? fallback.preset,
            colors: colors ?? fallback.colors,
            intensity: value(Double.self, .intensity) ?? fallback.intensity,
            grain: value(Double.self, .grain) ?? fallback.grain,
            opacity: value(Double.self, .opacity) ?? fallback.opacity
        ).validated()
    }
}

/// A string array element that may be something else (then nil instead of a failure).
private struct LossyString: Decodable {
    let value: String?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(String.self)
    }
}

/// One stop of a gradient: a color at a location 0...1.
public struct ThemeGradientStop: Equatable, Sendable {
    public var color: RGBColor
    public var location: Double

    public init(color: RGBColor, location: Double) {
        self.color = color
        self.location = location
    }
}

/// A theme drawn for one scheme, as plain values the SwiftUI layer turns into gradients.
///
/// Layers, bottom to top: the base linear gradient, the bottom-left blob, the top-right blob,
/// then the grain at `grainOpacity`. Colors are sRGB, already rounded to 8 bits per channel
/// exactly as Little Joan writes them (so `hex` matches its CSS).
public struct ThemeGradient: Equatable, Sendable {
    /// The three backgrounds (Little Joan's --lj-bg-0..2).
    public var backgrounds: [RGBColor]
    /// The base linear gradient's stops: from backgrounds[0] toward backgrounds[1], mixed in OKLab.
    public var baseStops: [ThemeGradientStop]
    /// The base gradient's angle in degrees, CSS convention (0 = up, 90 = right).
    public var angleDegrees: Double
    /// Soft radial blob at the top right: backgrounds[1].
    public var topRightBlob: RGBColor
    public var topRightStrength: Double
    /// Soft radial blob at the bottom left: backgrounds[2].
    public var bottomLeftBlob: RGBColor
    public var bottomLeftStrength: Double
    /// Grain overlay opacity (grain × 0.14, rounded to 3 decimals).
    public var grainOpacity: Double

    /// The backgrounds' chroma at full intensity, at most.
    static let maxChroma = 0.12
    /// The grain overlay's opacity at grain 1.
    static let fullGrainOpacity = 0.14
    static let baseStopLocations: [Double] = [0, 0.25, 0.5, 0.75, 1]
    /// The base gradient ends this far from backgrounds[0] toward backgrounds[1].
    static let baseReach = 0.4

    /// Alpha falloff of a blob along its radius (multiply by the blob's strength). A smooth
    /// curve, so the edge never shows as a ring.
    public static let blobFalloff: [(location: Double, alpha: Double)] = [
        (0, 1), (0.2, 0.9), (0.4, 0.62), (0.6, 0.3), (0.8, 0.08), (1, 0),
    ]

    /// Blob ellipses as CSS writes them: radii as fractions of the panel's width and height,
    /// centered on a corner (unit coordinates, y down). "120% 95% at 100% 0%".
    public static let topRightBlobCenter = (x: 1.0, y: 0.0)
    public static let topRightBlobRadii = (width: 1.2, height: 0.95)
    /// "110% 90% at 0% 100%".
    public static let bottomLeftBlobCenter = (x: 0.0, y: 1.0)
    public static let bottomLeftBlobRadii = (width: 1.1, height: 0.9)

    public init(theme: ColorTheme, scheme: ThemeScheme) {
        let theme = theme.validated()
        let backgrounds = Self.backgrounds(colors: theme.colors, intensity: theme.intensity, scheme: scheme)
            .map { $0.rgb.quantized }
        let from = OKLab(backgrounds[0])
        let end = from.mixed(with: OKLab(backgrounds[1]), Self.baseReach)
        self.backgrounds = backgrounds
        baseStops = Self.baseStopLocations.map { t in
            ThemeGradientStop(color: OKLCH(from.mixed(with: end, t)).rgb.quantized, location: t)
        }
        angleDegrees = 160
        topRightBlob = backgrounds[1]
        topRightStrength = 0.9
        bottomLeftBlob = backgrounds[2]
        bottomLeftStrength = 0.8
        grainOpacity = Self.grainOpacity(grain: theme.grain)
    }

    /// The grain overlay's opacity for `grain` (0–1).
    static func grainOpacity(grain: Double) -> Double {
        ((clampToUnit(grain) * fullGrainOpacity) * 1000).rounded() / 1000
    }

    /// Start and end of the base gradient in unit coordinates (y down) for a `width × height`
    /// box, the way CSS places a `linear-gradient(<angle>deg, …)`: the line runs through the
    /// center and is long enough that the first and last stops touch opposite corners.
    /// Points can lie outside 0...1. Feed them to SwiftUI's `LinearGradient` as `UnitPoint`s.
    public func baseGradientPoints(width: Double, height: Double) -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        Self.cssLinearGradientPoints(angleDegrees: angleDegrees, width: width, height: height)
    }

    public static func cssLinearGradientPoints(
        angleDegrees: Double, width: Double, height: Double
    ) -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        let w = width > 0 && width.isFinite ? width : 1
        let h = height > 0 && height.isFinite ? height : 1
        let angle = angleDegrees * .pi / 180
        let dx = sin(angle)
        let dy = -cos(angle)
        let half = (abs(w * dx) + abs(h * dy)) / 2
        let ux = dx * half / w
        let uy = dy * half / h
        return (start: (x: 0.5 - ux, y: 0.5 - uy), end: (x: 0.5 + ux, y: 0.5 + uy))
    }

    // MARK: Derivation

    /// A pick as a background: its hue kept, its lightness mapped into the scheme's band
    /// (lighter picks stay lighter), its chroma at most maxChroma × intensity, fitted into sRGB.
    static func mute(_ color: String, scheme: ThemeScheme, intensity: Double) -> OKLCH {
        let rgb = RGBColor(hex: color) ?? RGBColor(hex: ThemePreset.mist.colors[0])!
        let pick = OKLCH(rgb)
        let band = scheme.lightnessBand
        return OKLCH(
            l: band.lowerBound + (band.upperBound - band.lowerBound) * clampToUnit(pick.l),
            c: min(pick.c, maxChroma) * clampToUnit(intensity),
            h: pick.h
        ).fittedToGamut
    }

    /// The three backgrounds: one pick plus two neighbours (one lighter and warmer, one darker
    /// and cooler), two picks and the OKLab point between them, or three picks.
    static func backgrounds(colors: [String], intensity: Double, scheme: ThemeScheme) -> [OKLCH] {
        var muted = colors.prefix(ColorTheme.maxColors).map { mute($0, scheme: scheme, intensity: intensity) }
        if muted.isEmpty {
            muted = [mute(ThemePreset.mist.colors[0], scheme: scheme, intensity: intensity)]
        }
        let base = muted[0]
        switch muted.count {
        case 1:
            return [
                base,
                sibling(of: base, scheme: scheme, lightness: 0.35, hue: 24),
                sibling(of: base, scheme: scheme, lightness: -0.4, hue: -30),
            ]
        case 2:
            var between = OKLCH(OKLab(base).mixed(with: OKLab(muted[1]), 0.5))
            between.l = inBand(between.l, scheme)
            return [base, muted[1], between.fittedToGamut]
        default:
            return Array(muted.prefix(3))
        }
    }

    /// A neighbour of `base` for themes with fewer picks: lightness and hue nudged, kept in the band.
    private static func sibling(of base: OKLCH, scheme: ThemeScheme, lightness: Double, hue: Double) -> OKLCH {
        let band = scheme.lightnessBand
        return OKLCH(
            l: inBand(base.l + (band.upperBound - band.lowerBound) * lightness, scheme),
            c: base.c,
            h: (base.h + hue + 360).truncatingRemainder(dividingBy: 360)
        ).fittedToGamut
    }

    private static func inBand(_ l: Double, _ scheme: ThemeScheme) -> Double {
        let band = scheme.lightnessBand
        return min(band.upperBound, max(band.lowerBound, l))
    }
}
