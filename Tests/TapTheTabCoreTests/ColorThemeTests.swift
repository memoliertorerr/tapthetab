import Foundation
import XCTest
@testable import TapTheTabCore

final class ColorThemeTests: XCTestCase {
    private let epsilon = 1e-9

    private func randomHex(_ generator: inout SplitMix64) -> String {
        SRGBColor(
            red: Double.random(in: 0...1, using: &generator),
            green: Double.random(in: 0...1, using: &generator),
            blue: Double.random(in: 0...1, using: &generator)
        ).hex
    }

    private func decode(_ json: String) throws -> ColorTheme {
        try JSONDecoder().decode(ColorTheme.self, from: Data(json.utf8))
    }

    // MARK: Presets

    func testPresetsAreLittleJoansElevenInOrder() {
        XCTAssertEqual(ThemePreset.all.map(\.id), [
            "mist", "sand", "sage", "lagoon", "dusk", "ember", "orchid", "glacier", "meadow", "berry", "graphite",
        ])
        XCTAssertEqual(ThemePreset.all.map(\.name), [
            "Mist", "Sand", "Sage", "Lagoon", "Dusk", "Ember", "Orchid", "Glacier", "Meadow", "Berry", "Graphite",
        ])
        XCTAssertEqual(ThemePreset.named("glacier")?.colors, ["#94bce2", "#a9d8d2", "#c7bfe8"])
        XCTAssertEqual(ThemePreset.named("graphite")?.intensity, 0.2)
        XCTAssertNil(ThemePreset.named("none"))
        XCTAssertNil(ThemePreset.named("custom"))
        XCTAssertNil(ThemePreset.named("Mist"))
    }

    func testPresetsAreValid() {
        XCTAssertEqual(Set(ThemePreset.all.map(\.id)).count, ThemePreset.all.count)
        for preset in ThemePreset.all {
            XCTAssertTrue((1...ColorTheme.maxColors).contains(preset.colors.count), preset.id)
            for color in preset.colors {
                XCTAssertEqual(SRGBColor.normalizedHex(color), color, preset.id)
            }
            XCTAssertTrue((0...1).contains(preset.intensity), preset.id)
            XCTAssertTrue((0...1).contains(preset.grain), preset.id)
        }
    }

    // MARK: The theme value

    func testNoneIsMistWithoutATheme() {
        let none = ColorTheme.none
        XCTAssertEqual(none.preset, "none")
        XCTAssertFalse(none.isEnabled)
        XCTAssertEqual(none.colors, ["#8c9bb5"])
        XCTAssertEqual(none.intensity, 0.45)
        XCTAssertEqual(none.grain, 0.15)
        XCTAssertEqual(none.opacity, 0.55)
        XCTAssertEqual(ColorTheme.defaultOpacity, 0.55)
        XCTAssertEqual(ColorTheme.maxColors, 3)
        XCTAssertEqual(none.validated(), none)
    }

    func testApplyingAPresetKeepsOpacity() {
        var theme = ColorTheme.none
        theme.opacity = 0.8
        let dusk = theme.applying(ThemePreset.named("dusk")!)
        XCTAssertEqual(dusk, ColorTheme(preset: "dusk", colors: ["#9d8fd0", "#e0a2a0"], intensity: 0.6, grain: 0.3, opacity: 0.8))
        XCTAssertTrue(dusk.isEnabled)
        XCTAssertTrue(ColorTheme(preset: "custom", colors: ["#123456"], intensity: 1, grain: 0).isEnabled)
    }

    func testValidatedFixesEveryValueOnItsOwn() {
        let theme = ColorTheme(
            preset: " Sand ",
            colors: ["#ABC", "nope", "#123456", "#654321", "#111111"],
            intensity: 2, grain: -1, opacity: .nan
        ).validated()
        XCTAssertEqual(theme, ColorTheme(
            preset: "sand", colors: ["#aabbcc", "#123456", "#654321"], intensity: 1, grain: 0, opacity: 0.55
        ))
        XCTAssertEqual(ColorTheme(preset: "sepia", colors: [], intensity: .infinity, grain: -.infinity, opacity: 3).validated(),
                       ColorTheme(preset: "custom", colors: ["#8c9bb5"], intensity: 0.45, grain: 0.15, opacity: 1))
        XCTAssertEqual(ColorTheme(preset: "", colors: ["x"], intensity: 0, grain: 1, opacity: 0).validated().preset, "custom")
        XCTAssertEqual(ColorTheme(preset: "NONE", colors: ["#fff"], intensity: 0, grain: 1).validated().preset, "none")
    }

    func testValidatedIsIdempotent() {
        var generator = SplitMix64(seed: 5)
        let presets = ["none", "custom", "mist", "Berry", "bogus", "", " glacier"]
        let numbers = [-1, 0, 0.3, 1, 7, .nan, .infinity]
        for _ in 0..<300 {
            let count = Int.random(in: 0...5, using: &generator)
            let colors = (0..<count).map { _ in
                Bool.random(using: &generator) ? randomHex(&generator).uppercased() : "nope"
            }
            let theme = ColorTheme(
                preset: presets.randomElement(using: &generator)!,
                colors: colors,
                intensity: numbers.randomElement(using: &generator)!,
                grain: numbers.randomElement(using: &generator)!,
                opacity: numbers.randomElement(using: &generator)!
            )
            let once = theme.validated()
            XCTAssertEqual(once.validated(), once)
            XCTAssertTrue((1...3).contains(once.colors.count))
        }
    }

    // MARK: Decoding

    func testDecodesAFullTheme() throws {
        let theme = try decode(##"{"preset":"lagoon","colors":["#6fa8c4","#7fc2ab"],"intensity":0.6,"grain":0.25,"opacity":0.7}"##)
        XCTAssertEqual(theme, ColorTheme(preset: "lagoon", colors: ["#6fa8c4", "#7fc2ab"], intensity: 0.6, grain: 0.25, opacity: 0.7))
    }

    func testEncodingRoundTrips() throws {
        let theme = ColorTheme(preset: "custom", colors: ["#123456", "#abcdef"], intensity: 0.3, grain: 0.9, opacity: 0.4)
        let data = try JSONEncoder().encode(theme)
        XCTAssertEqual(try JSONDecoder().decode(ColorTheme.self, from: data), theme)
        let keys = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(Set(keys?.keys.map { $0 } ?? []), ["preset", "colors", "intensity", "grain", "opacity"])
    }

    func testMissingKeysFallBackToNone() throws {
        XCTAssertEqual(try decode("{}"), .none)
        XCTAssertEqual(try decode(##"{"preset":"ember"}"##), ColorTheme(
            preset: "ember", colors: ["#8c9bb5"], intensity: 0.45, grain: 0.15, opacity: 0.55
        ))
        XCTAssertEqual(try decode(##"{"opacity":0.2}"##).opacity, 0.2)
    }

    func testABadValueFallsBackForThatKeyOnly() throws {
        let theme = try decode(##"{"preset":7,"colors":"red","intensity":"x","grain":null,"opacity":true}"##)
        XCTAssertEqual(theme, .none)
        let mixed = try decode(##"{"preset":"custom","colors":["#123456"],"intensity":"x","grain":0.5,"opacity":[1]}"##)
        XCTAssertEqual(mixed, ColorTheme(preset: "custom", colors: ["#123456"], intensity: 0.45, grain: 0.5, opacity: 0.55))
    }

    func testNumbersAreClamped() throws {
        let theme = try decode(##"{"intensity":2,"grain":-1,"opacity":1e300}"##)
        XCTAssertEqual(theme.intensity, 1)
        XCTAssertEqual(theme.grain, 0)
        XCTAssertEqual(theme.opacity, 1)
    }

    func testUnknownPresetBecomesCustom() throws {
        XCTAssertEqual(try decode(##"{"preset":"sepia","colors":["#123456"]}"##).preset, "custom")
        XCTAssertEqual(try decode(##"{"preset":"custom"}"##).preset, "custom")
        XCTAssertEqual(try decode(##"{"preset":"none"}"##).preset, "none")
        XCTAssertEqual(try decode(##"{"preset":"Graphite"}"##).preset, "graphite")
    }

    func testColorsAreFilteredNormalizedAndTrimmed() throws {
        let theme = try decode(##"{"colors":["#ABC","nope",3,null,"#123456","654321","#111111"]}"##)
        XCTAssertEqual(theme.colors, ["#aabbcc", "#123456", "#654321"])
        XCTAssertEqual(try decode(##"{"colors":[]}"##).colors, ["#8c9bb5"])
        XCTAssertEqual(try decode(##"{"colors":["bad", 1]}"##).colors, ["#8c9bb5"])
    }

    func testANonObjectDecodesAsNone() throws {
        XCTAssertEqual(try decode(##""dark""##), .none)
        XCTAssertEqual(try decode("[1,2]"), .none)
    }

    func testDecodesInsideAnEnclosingObject() throws {
        struct Wrapper: Decodable { var colorTheme: ColorTheme }
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: Data(##"{"colorTheme":{"preset":"berry","opacity":0.3}}"##.utf8))
        XCTAssertEqual(wrapper.colorTheme.preset, "berry")
        XCTAssertEqual(wrapper.colorTheme.opacity, 0.3)
    }

    // MARK: Muting

    func testMuteKeepsEveryBackgroundInTheBandAndUnderTheChromaCap() {
        var generator = SplitMix64(seed: 7)
        var picks = ["#000000", "#ffffff", "#ff0000", "#00ff00", "#0000ff", "#ffff00"]
        for _ in 0..<200 { picks.append(randomHex(&generator)) }
        for scheme in ThemeScheme.allCases {
            let band = scheme.lightnessBand
            for pick in picks {
                for intensity in [0, 0.3, 0.6, 1.0] {
                    let muted = ThemeGradient.mute(pick, scheme: scheme, intensity: intensity)
                    XCTAssertGreaterThanOrEqual(muted.l, band.lowerBound - epsilon)
                    XCTAssertLessThanOrEqual(muted.l, band.upperBound + epsilon)
                    XCTAssertLessThanOrEqual(muted.c, ThemeGradient.maxChroma * intensity + epsilon)
                }
            }
        }
        XCTAssertEqual(ThemeScheme.light.lightnessBand, 0.86...0.93)
        XCTAssertEqual(ThemeScheme.dark.lightnessBand, 0.22...0.32)
        XCTAssertEqual(ThemeGradient.maxChroma, 0.12)
    }

    func testMuteKeepsHueAndOrdersLighterPicksLighter() {
        let teal = ThemeGradient.mute("#2a9d8f", scheme: .light, intensity: 1)
        XCTAssertEqual(teal.h, OKLCH(SRGBColor(hex: "#2a9d8f")!).h, accuracy: 1e-6)
        // Little Joan's values for the same pick.
        XCTAssertEqual(teal.l, 0.9041290650662406, accuracy: 1e-9)
        XCTAssertEqual(teal.c, 0.1013056949106884, accuracy: 1e-6)
        XCTAssertGreaterThan(ThemeGradient.mute("#eeeeee", scheme: .dark, intensity: 0.5).l,
                             ThemeGradient.mute("#222222", scheme: .dark, intensity: 0.5).l)
        // Intensity 0 is grey.
        XCTAssertEqual(ThemeGradient.mute("#ff0000", scheme: .light, intensity: 0).c, 0)
        // Black and white land on the band's ends.
        XCTAssertEqual(ThemeGradient.mute("#000000", scheme: .light, intensity: 0.7).l, 0.86, accuracy: 1e-9)
        XCTAssertEqual(ThemeGradient.mute("#ffffff", scheme: .dark, intensity: 1).l, 0.32, accuracy: 1e-6)
        // An unreadable color counts as Mist's.
        XCTAssertEqual(ThemeGradient.mute("nope", scheme: .dark, intensity: 0.5),
                       ThemeGradient.mute("#8c9bb5", scheme: .dark, intensity: 0.5))
    }

    // MARK: Deriving the backgrounds

    func testOneColorGetsTwoSiblings() {
        let bgs = ThemeGradient.backgrounds(colors: ["#8c9bb5"], intensity: 0.5, scheme: .light)
        XCTAssertEqual(bgs.count, 3)
        let base = ThemeGradient.mute("#8c9bb5", scheme: .light, intensity: 0.5)
        XCTAssertEqual(bgs[0], base)
        // One lighter and warmer (hue +24), one darker and cooler (hue −30), same chroma or less.
        XCTAssertGreaterThan(bgs[1].l, base.l)
        XCTAssertLessThan(bgs[2].l, base.l)
        XCTAssertEqual(bgs[1].h, (base.h + 24).truncatingRemainder(dividingBy: 360), accuracy: 1e-9)
        XCTAssertEqual(bgs[2].h, (base.h - 30 + 360).truncatingRemainder(dividingBy: 360), accuracy: 1e-9)
        XCTAssertLessThanOrEqual(bgs[1].c, base.c + epsilon)
        XCTAssertLessThanOrEqual(bgs[2].c, base.c + epsilon)
    }

    func testTwoColorsGetTheirMidpoint() {
        let bgs = ThemeGradient.backgrounds(colors: ["#9d8fd0", "#e0a2a0"], intensity: 0.6, scheme: .dark)
        let first = ThemeGradient.mute("#9d8fd0", scheme: .dark, intensity: 0.6)
        let second = ThemeGradient.mute("#e0a2a0", scheme: .dark, intensity: 0.6)
        XCTAssertEqual(bgs[0], first)
        XCTAssertEqual(bgs[1], second)
        let mid = OKLab(first).mixed(with: OKLab(second), 0.5)
        let between = OKLab(bgs[2])
        XCTAssertEqual(between.l, mid.l, accuracy: 1e-6)
        // Chroma can only go down when fitting; the hue stays.
        XCTAssertEqual(bgs[2].h, OKLCH(mid).h, accuracy: 1e-6)
    }

    func testThreeColorsAreUsedAsTheyAre() {
        let colors = ["#94bce2", "#a9d8d2", "#c7bfe8"]
        let bgs = ThemeGradient.backgrounds(colors: colors, intensity: 0.5, scheme: .light)
        XCTAssertEqual(bgs, colors.map { ThemeGradient.mute($0, scheme: .light, intensity: 0.5) })
        // More than three: the rest are ignored.
        XCTAssertEqual(ThemeGradient.backgrounds(colors: colors + ["#000000"], intensity: 0.5, scheme: .light), bgs)
        // None: Mist's color.
        XCTAssertEqual(ThemeGradient.backgrounds(colors: [], intensity: 0.5, scheme: .light),
                       ThemeGradient.backgrounds(colors: ["#8c9bb5"], intensity: 0.5, scheme: .light))
    }

    // MARK: The gradient

    /// Little Joan's output (palette().backgrounds and gradientStops()) for every preset.
    private let littleJoan: [(String, ThemeScheme, [String], [String], Double)] = [
        ("mist", .light, ["#dae1ee", "#e6e6f4", "#ccdae2"], ["#dae1ee", "#dbe2ef", "#dce2ef", "#dee3f0", "#dfe3f0"], 0.021),
        ("mist", .dark, ["#262b35", "#32323c", "#182329"], ["#262b35", "#272c36", "#282c36", "#2a2d37", "#2b2e38"], 0.021),
        ("sand", .light, ["#f4ddc9", "#eee3cc", "#f1e0ca"], ["#f4ddc9", "#f3dec9", "#f3deca", "#f2dfca", "#f2dfca"], 0.042),
        ("sand", .dark, ["#392818", "#362d1b", "#382b19"], ["#392818", "#392918", "#382919", "#382a19", "#382a19"], 0.042),
        ("sage", .light, ["#d5e7d9", "#e4e5cc", "#dde6d2"], ["#d5e7d9", "#d7e7d8", "#d8e7d6", "#dae6d5", "#dbe6d4"], 0.035),
        ("sage", .dark, ["#223025", "#2f2e1a", "#292f20"], ["#223025", "#233024", "#253023", "#262f22", "#282f21"], 0.035),
        ("lagoon", .light, ["#c5e7f9", "#c5edde", "#c5eaec"], ["#c5e7f9", "#c5e8f6", "#c5e8f4", "#c5e9f1", "#c5e9ee"], 0.035),
        ("lagoon", .dark, ["#112f3d", "#10342a", "#103234"], ["#112f3d", "#11303b", "#113039", "#103138", "#103136"], 0.035),
        ("dusk", .light, ["#e2dbff", "#ffd8d6", "#f1daeb"], ["#e2dbff", "#e5dbfb", "#e8dbf7", "#ebdaf3", "#eedaef"], 0.042),
        ("dusk", .dark, ["#2d2545", "#412423", "#372535"], ["#2d2545", "#2f2542", "#31253f", "#33253b", "#352638"], 0.042),
        ("ember", .light, ["#ffd7c9", "#f5e0b9", "#fadcc1"], ["#ffd7c9", "#fed8c7", "#fdd9c6", "#fcdac4", "#fbdbc3"], 0.049),
        ("ember", .dark, ["#422216", "#3b2a05", "#3f260f"], ["#422216", "#412315", "#412413", "#402512", "#3f2510"], 0.049),
        ("orchid", .light, ["#f1d7f9", "#d5e1ff", "#e4dcfc"], ["#f1d7f9", "#eed8fa", "#ecd9fa", "#e9dafb", "#e6dbfb"], 0.028),
        ("orchid", .dark, ["#37233d", "#222b44", "#2e2740"], ["#37233d", "#35243e", "#33253e", "#31263f", "#302740"], 0.028),
        ("glacier", .light, ["#d1e6f9", "#d3eae7", "#e4e1f6"], ["#d1e6f9", "#d1e6f7", "#d1e7f5", "#d2e7f4", "#d2e8f2"], 0.028),
        ("glacier", .dark, ["#1f2f3e", "#203331", "#2f2c3c"], ["#1f2f3e", "#1f2f3d", "#1f303b", "#1f303a", "#1f3139"], 0.028),
        ("meadow", .light, ["#d8eac3", "#c8ebe0", "#f0e4bd"], ["#d8eac3", "#d6eac6", "#d5eac9", "#d3eacc", "#d2eacf"], 0.042),
        ("meadow", .dark, ["#253211", "#14332b", "#382e0a"], ["#253211", "#243214", "#223217", "#21321a", "#1f331d"], 0.042),
        ("berry", .light, ["#ffd3e4", "#dfdbff", "#ffdacb"], ["#ffd3e4", "#fcd4e7", "#f9d5e9", "#f6d6ec", "#f3d6ef"], 0.042),
        ("berry", .dark, ["#411e2e", "#2b2446", "#41261b"], ["#411e2e", "#3f1f31", "#3d2033", "#3b2135", "#392138"], 0.042),
        ("graphite", .light, ["#dedfe1", "#e7e6e9", "#d4d6d7"], ["#dedfe1", "#dfe0e2", "#e0e0e3", "#e1e1e3", "#e2e2e4"], 0.049),
        ("graphite", .dark, ["#28292b", "#313133", "#1e2021"], ["#28292b", "#292a2c", "#2a2b2d", "#2b2b2d", "#2c2c2e"], 0.049),
    ]

    func testPresetsMatchLittleJoanExactly() {
        XCTAssertEqual(littleJoan.count, ThemePreset.all.count * 2)
        for (id, scheme, backgrounds, stops, grain) in littleJoan {
            let theme = ColorTheme.none.applying(ThemePreset.named(id)!)
            let gradient = ThemeGradient(theme: theme, scheme: scheme)
            let label = "\(id) \(scheme)"
            XCTAssertEqual(gradient.backgrounds.map(\.hex), backgrounds, label)
            XCTAssertEqual(gradient.baseStops.map(\.color.hex), stops, label)
            XCTAssertEqual(gradient.grainOpacity, grain, accuracy: 1e-12, label)
        }
    }

    func testCustomColorsMatchLittleJoanExactly() {
        let cases: [([String], ThemeScheme, [String], [String])] = [
            (["#ff0000"], .light, ["#ffd4cc", "#ffe0ce", "#f3c9d5"], ["#ffd4cc", "#ffd5cc", "#ffd6cc", "#ffd8cd", "#ffd9cd"]),
            (["#ff0000"], .dark, ["#4f0e09", "#512400", "#40011f"], ["#4f0e09", "#4f1108", "#501308", "#501607", "#501806"]),
            (["#123456", "#abcdef"], .light, ["#bddcfe", "#d0e7ff", "#c6e1ff"], ["#bddcfe", "#bfddfe", "#c1defe", "#c3dffe", "#c5e0fe"]),
            (["#123456", "#abcdef"], .dark, ["#09233d", "#1a3146", "#122a41"], ["#09233d", "#0b243e", "#0d263f", "#0e2740", "#102941"]),
            (["#ff0000", "#00ff00", "#0000ff"], .light, ["#ffd4cc", "#c0f6bb", "#cadcff"], ["#ffd4cc", "#fad8ca", "#f4dbc9", "#eedfc7", "#e9e2c5"]),
            (["#ff0000", "#00ff00", "#0000ff"], .dark, ["#4f0e09", "#073b06", "#0c2153"], ["#4f0e09", "#4b1609", "#471c09", "#432208", "#3e2608"]),
        ]
        for (colors, scheme, backgrounds, stops) in cases {
            let theme = ColorTheme(preset: "custom", colors: colors, intensity: 0.8, grain: 0.5)
            let gradient = ThemeGradient(theme: theme, scheme: scheme)
            XCTAssertEqual(gradient.backgrounds.map(\.hex), backgrounds, "\(colors) \(scheme)")
            XCTAssertEqual(gradient.baseStops.map(\.color.hex), stops, "\(colors) \(scheme)")
        }
    }

    func testEveryPresetStaysInGamutAndInTheBand() {
        for preset in ThemePreset.all {
            for scheme in ThemeScheme.allCases {
                let gradient = ThemeGradient(theme: ColorTheme.none.applying(preset), scheme: scheme)
                assertDrawable(gradient, scheme: scheme, label: "\(preset.id) \(scheme)")
            }
        }
    }

    func testAnyColorsStayInGamutAndInTheBand() {
        var generator = SplitMix64(seed: 11)
        for _ in 0..<150 {
            let count = Int.random(in: 1...3, using: &generator)
            let theme = ColorTheme(
                preset: "custom",
                colors: (0..<count).map { _ in randomHex(&generator) },
                intensity: Double.random(in: 0...1, using: &generator),
                grain: Double.random(in: 0...1, using: &generator)
            )
            for scheme in ThemeScheme.allCases {
                let gradient = ThemeGradient(theme: theme, scheme: scheme)
                assertDrawable(gradient, scheme: scheme, label: "\(theme.colors) \(scheme)")
                for bg in ThemeGradient.backgrounds(colors: theme.colors, intensity: theme.intensity, scheme: scheme) {
                    XCTAssertLessThanOrEqual(bg.c, ThemeGradient.maxChroma * theme.intensity + epsilon)
                }
            }
        }
    }

    private func assertDrawable(_ gradient: ThemeGradient, scheme: ThemeScheme, label: String, line: UInt = #line) {
        XCTAssertEqual(gradient.backgrounds.count, 3, label, line: line)
        XCTAssertEqual(gradient.baseStops.map(\.location), [0, 0.25, 0.5, 0.75, 1], label, line: line)
        let colors = gradient.backgrounds + gradient.baseStops.map(\.color) + [gradient.topRightBlob, gradient.bottomLeftBlob]
        for color in colors {
            for value in [color.red, color.green, color.blue] {
                XCTAssertTrue((0...1).contains(value), label, line: line)
            }
        }
        // Rounding to 8 bits moves a color by at most half a step per channel.
        let band = scheme.lightnessBand
        for color in gradient.backgrounds + gradient.baseStops.map(\.color) {
            let l = OKLCH(color).l
            XCTAssertGreaterThanOrEqual(l, band.lowerBound - 0.005, label, line: line)
            XCTAssertLessThanOrEqual(l, band.upperBound + 0.005, label, line: line)
        }
    }

    func testGradientShape() {
        let theme = ColorTheme.none.applying(ThemePreset.named("dusk")!)
        let gradient = ThemeGradient(theme: theme, scheme: .light)
        XCTAssertEqual(gradient.angleDegrees, 160)
        XCTAssertEqual(gradient.baseStops.first?.color, gradient.backgrounds[0])
        XCTAssertEqual(gradient.topRightBlob, gradient.backgrounds[1])
        XCTAssertEqual(gradient.topRightStrength, 0.9)
        XCTAssertEqual(gradient.bottomLeftBlob, gradient.backgrounds[2])
        XCTAssertEqual(gradient.bottomLeftStrength, 0.8)
        let falloff = ThemeGradient.blobFalloff
        XCTAssertEqual(falloff.map(\.location), [0, 0.2, 0.4, 0.6, 0.8, 1])
        XCTAssertEqual(falloff.map(\.alpha), [1, 0.9, 0.62, 0.3, 0.08, 0])
        XCTAssertTrue(ThemeGradient.topRightBlobCenter == (1, 0))
        XCTAssertTrue(ThemeGradient.topRightBlobRadii == (1.2, 0.95))
        XCTAssertTrue(ThemeGradient.bottomLeftBlobCenter == (0, 1))
        XCTAssertTrue(ThemeGradient.bottomLeftBlobRadii == (1.1, 0.9))
    }

    func testGradientIsDeterministicAndDiffersPerColorCount() {
        let themes = [
            ColorTheme(preset: "custom", colors: ["#8c9bb5"], intensity: 0.5, grain: 0),
            ColorTheme(preset: "custom", colors: ["#9d8fd0", "#e0a2a0"], intensity: 0.6, grain: 0.4),
            ColorTheme(preset: "custom", colors: ["#94bce2", "#a9d8d2", "#c7bfe8"], intensity: 0.5, grain: 0.2),
        ]
        var seen: [ThemeGradient] = []
        for theme in themes {
            let gradient = ThemeGradient(theme: theme, scheme: .dark)
            XCTAssertEqual(ThemeGradient(theme: theme, scheme: .dark), gradient)
            XCTAssertFalse(seen.contains(gradient))
            seen.append(gradient)
            XCTAssertNotEqual(ThemeGradient(theme: theme, scheme: .light), gradient)
        }
    }

    func testGradientIgnoresPresetIdAndOpacityAndValidatesFirst() {
        let custom = ColorTheme(preset: "custom", colors: ["#c294cf", "#8ea3dc"], intensity: 0.55, grain: 0.2, opacity: 0.1)
        let orchid = ColorTheme.none.applying(ThemePreset.named("orchid")!)
        XCTAssertEqual(ThemeGradient(theme: custom, scheme: .light), ThemeGradient(theme: orchid, scheme: .light))
        let messy = ColorTheme(preset: "x", colors: ["nope", "#C294CF", "#8EA3DC"], intensity: 0.55, grain: 0.2)
        XCTAssertEqual(ThemeGradient(theme: messy, scheme: .light), ThemeGradient(theme: orchid, scheme: .light))
        // An unusable theme draws as Mist.
        let empty = ColorTheme(preset: "custom", colors: [], intensity: .nan, grain: .nan)
        XCTAssertEqual(ThemeGradient(theme: empty, scheme: .dark), ThemeGradient(theme: .none, scheme: .dark))
    }

    func testGrainOpacity() {
        XCTAssertEqual(ThemeGradient.grainOpacity(grain: 0), 0)
        XCTAssertEqual(ThemeGradient.grainOpacity(grain: 0.4), 0.056, accuracy: 1e-12)
        XCTAssertEqual(ThemeGradient.grainOpacity(grain: 1), 0.14)
        XCTAssertEqual(ThemeGradient.grainOpacity(grain: 7), 0.14)
        XCTAssertEqual(ThemeGradient.grainOpacity(grain: -1), 0)
        // Rounded to three decimals: 0.333 × 0.14 = 0.04662.
        XCTAssertEqual(ThemeGradient.grainOpacity(grain: 0.333), 0.047, accuracy: 1e-12)
    }

    // MARK: CSS angle → unit points

    private func assertPoints(_ angle: Double, _ width: Double, _ height: Double,
                              start: (Double, Double), end: (Double, Double), line: UInt = #line) {
        let points = ThemeGradient.cssLinearGradientPoints(angleDegrees: angle, width: width, height: height)
        XCTAssertEqual(points.start.x, start.0, accuracy: 1e-9, line: line)
        XCTAssertEqual(points.start.y, start.1, accuracy: 1e-9, line: line)
        XCTAssertEqual(points.end.x, end.0, accuracy: 1e-9, line: line)
        XCTAssertEqual(points.end.y, end.1, accuracy: 1e-9, line: line)
    }

    func testCSSAnglesMapToUnitPoints() {
        assertPoints(180, 300, 200, start: (0.5, 0), end: (0.5, 1))
        assertPoints(0, 300, 200, start: (0.5, 1), end: (0.5, 0))
        assertPoints(90, 300, 200, start: (0, 0.5), end: (1, 0.5))
        // In a square, 135° runs corner to corner.
        assertPoints(135, 100, 100, start: (0, 0), end: (1, 1))
        // In any box, the CSS gradient line's ends lie on the perpendiculars through opposite corners.
        for (width, height) in [(640.0, 400.0), (400.0, 640.0), (1000.0, 120.0)] {
            let points = ThemeGradient.cssLinearGradientPoints(angleDegrees: 160, width: width, height: height)
            let dx = (points.end.x - points.start.x) * width
            let dy = (points.end.y - points.start.y) * height
            // The end projects onto the bottom-right corner (160° points down and a little right).
            let along = { (x: Double, y: Double) in ((x - points.start.x * width) * dx + (y - points.start.y * height) * dy) / (dx * dx + dy * dy) }
            XCTAssertEqual(along(width, height), 1, accuracy: 1e-9)
            XCTAssertEqual(along(0, 0), 0, accuracy: 1e-9)
        }
        let gradient = ThemeGradient(theme: .none, scheme: .light)
        let points = gradient.baseGradientPoints(width: 640, height: 400)
        XCTAssertEqual(points.end.x, 0.6589, accuracy: 1e-3)
        XCTAssertEqual(points.end.y, 1.1987, accuracy: 1e-3)
        // A degenerate box does not produce NaN.
        let zero = ThemeGradient.cssLinearGradientPoints(angleDegrees: 160, width: 0, height: .nan)
        XCTAssertTrue(zero.start.x.isFinite && zero.end.y.isFinite)
    }
}
