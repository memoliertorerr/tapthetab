import AppKit
import SwiftUI
import TapTheTabCore

/// Settings → Appearance → Theme: a soft gradient with grain over the switcher's glass,
/// like Arc's (and Little Joan's) themes. Presets as swatches, up to three colors of your
/// own, and sliders for color, grain and strength.
struct ThemeSettingsSection: View {
    @Binding var theme: ColorTheme

    private static let swatchSide: CGFloat = 26

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Theme"))
                swatches
            }

            if theme.isEnabled {
                colorRow

                slider(L10n.tr("Color"), value: $theme.intensity)
                slider(L10n.tr("Grain"), value: $theme.grain)
                slider(L10n.tr("Strength"), value: $theme.opacity)
            }
        } footer: {
            Text(L10n.tr("A soft gradient with grain over the switcher's glass. Strength sets how much of the glass shows through."))
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
    }

    // MARK: - Swatches

    private var swatches: some View {
        // Wraps onto two rows in the Settings window's width.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.swatchSide + 6), spacing: 6)], alignment: .leading, spacing: 8) {
            swatchButton(selected: !theme.isEnabled, label: L10n.tr("None")) {
                theme.preset = ColorTheme.noneID
            } content: {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                    .overlay(
                        Rectangle()
                            .fill(Color.secondary.opacity(0.6))
                            .frame(width: 1, height: Self.swatchSide)
                            .rotationEffect(.degrees(45))
                    )
                    .clipShape(Circle())
            }
            ForEach(ThemePreset.all) { preset in
                swatchButton(selected: theme.preset == preset.id, label: Self.name(of: preset)) {
                    theme = theme.applying(preset)
                } content: {
                    Circle().fill(Self.swatchFill(preset.colors))
                }
            }
            swatchButton(selected: theme.preset == ColorTheme.customID, label: L10n.tr("Custom")) {
                theme.preset = ColorTheme.customID
            } content: {
                Circle()
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                    .opacity(0.75)
            }
        }
    }

    private func swatchButton<Content: View>(
        selected: Bool,
        label: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: Self.swatchSide, height: Self.swatchSide)
                .padding(3)
                .overlay(
                    Circle().strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private static func swatchFill(_ colors: [String]) -> LinearGradient {
        let swiftUIColors = colors.compactMap { SRGBColor(hex: $0).map { Color($0) } }
        return LinearGradient(colors: swiftUIColors.count == 1 ? swiftUIColors + swiftUIColors : swiftUIColors,
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Colors

    /// The theme's colors, each editable with the system color picker (which makes the
    /// theme custom), plus adding up to three and removing down to one.
    private var colorRow: some View {
        HStack(spacing: 10) {
            Text(L10n.tr("Colors"))
            Spacer(minLength: 8)
            ForEach(theme.colors.indices, id: \.self) { index in
                ColorPicker(selection: colorBinding(index), supportsOpacity: false) {
                    Text(L10n.tr("Color %lld", index + 1))
                }
                .labelsHidden()
            }
            Button {
                var colors = theme.colors
                colors.removeLast()
                theme.colors = colors
                theme.preset = ColorTheme.customID
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(theme.colors.count <= 1)
            .help(L10n.tr("Remove a color"))
            .accessibilityLabel(Text(L10n.tr("Remove a color")))
            Button {
                theme.colors.append(theme.colors.last ?? "#8c9bb5")
                theme.preset = ColorTheme.customID
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(theme.colors.count >= ColorTheme.maxColors)
            .help(L10n.tr("Add a color"))
            .accessibilityLabel(Text(L10n.tr("Add a color")))
        }
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding {
            guard theme.colors.indices.contains(index), let rgb = SRGBColor(hex: theme.colors[index]) else { return Color.gray }
            return Color(rgb)
        } set: { newValue in
            guard theme.colors.indices.contains(index),
                  let ns = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            let hex = SRGBColor(red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent)).hex
            guard hex != theme.colors[index] else { return }
            theme.colors[index] = hex
            theme.preset = ColorTheme.customID
        }
    }

    // MARK: - Sliders

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(minWidth: 70, alignment: .leading)
                .accessibilityHidden(true)
            Slider(value: value, in: 0...1)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(L10n.tr("%lld%%", Int((value.wrappedValue * 100).rounded()))))
            Text(L10n.tr("%lld%%", Int((value.wrappedValue * 100).rounded())))
                .font(.body.monospacedDigit())
                .frame(width: 48, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    /// The preset's name in the user's language.
    static func name(of preset: ThemePreset) -> String {
        switch preset.id {
        case "mist": return L10n.tr("Mist")
        case "sand": return L10n.tr("Sand")
        case "sage": return L10n.tr("Sage")
        case "lagoon": return L10n.tr("Lagoon")
        case "dusk": return L10n.tr("Dusk")
        case "ember": return L10n.tr("Ember")
        case "orchid": return L10n.tr("Orchid")
        case "glacier": return L10n.tr("Glacier")
        case "meadow": return L10n.tr("Meadow")
        case "berry": return L10n.tr("Berry")
        case "graphite": return L10n.tr("Graphite")
        default: return preset.name
        }
    }
}
