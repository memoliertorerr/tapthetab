import AppKit
import SwiftUI
import TapTheTabCore

/// What sits behind the switcher's main block and its preview card: a material, with an
/// optional color theme (gradient and grain) between it and the content.
struct PanelBackdropStyle: Equatable {
    enum Material: Equatable {
        /// The dark heads-up-display material of earlier versions.
        case classic
        /// Liquid Glass in one of its two variations. macOS 26 and later draw the system's
        /// glass; earlier versions get a translucent blur with a glass-like rim.
        case glass(GlassStyle)
    }

    var material: Material
    /// Drawn only when enabled (`ColorTheme.isEnabled`).
    var theme: ColorTheme

    init(_ appearance: Appearance) {
        material = appearance.liquidGlass ? .glass(appearance.glassStyle) : .classic
        theme = appearance.colorTheme
    }
}

extension EnvironmentValues {
    /// False while `ScreenshotRenderer` draws the panel: it paints a stand-in for the
    /// backdrop itself, since blur and glass do not render offscreen.
    var switcherDrawsBackdrop: Bool {
        get { self[SwitcherDrawsBackdropKey.self] }
        set { self[SwitcherDrawsBackdropKey.self] = newValue }
    }
}

private struct SwitcherDrawsBackdropKey: EnvironmentKey {
    static let defaultValue = true
}

extension View {
    /// Puts `style`'s backdrop behind this view, clipped to a rounded rectangle.
    func switcherBackdrop(_ style: PanelBackdropStyle, cornerRadius: CGFloat) -> some View {
        modifier(SwitcherBackdropModifier(style: style, cornerRadius: cornerRadius))
    }
}

private struct SwitcherBackdropModifier: ViewModifier {
    let style: PanelBackdropStyle
    let cornerRadius: CGFloat

    @Environment(\.switcherDrawsBackdrop) private var drawsBackdrop
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        // The theme is plain SwiftUI drawing, so it shows in the screenshots too.
        let themed = content.background(ThemeBackground(theme: style.theme, cornerRadius: cornerRadius))
        if !drawsBackdrop {
            themed
        } else {
            switch style.material {
            case .classic:
                themed.background(VisualEffectBackdrop(material: .hudWindow, cornerRadius: cornerRadius))
            case .glass(let variation):
                glass(themed, variation: variation)
            }
        }
    }

    #if compiler(>=6.2)
    @ViewBuilder
    private func glass<V: View>(_ content: V, variation: GlassStyle) -> some View {
        if #available(macOS 26.0, *) {
            systemGlass(content, variation: variation)
        } else {
            approximateGlass(content, variation: variation)
        }
    }

    /// The system's Liquid Glass. Clear lets the desktop show through as much as the
    /// system allows (no dimming layer of our own); Tinted is the frosted regular glass.
    /// Both follow Reduce Transparency, Increase Contrast and the system's own Clear /
    /// Tinted setting.
    @available(macOS 26.0, *)
    @ViewBuilder
    private func systemGlass<V: View>(_ content: V, variation: GlassStyle) -> some View {
        switch variation {
        case .clear:
            content
                .glassEffect(.clear, in: shape)
        case .tinted:
            content
                .glassEffect(.regular, in: shape)
        }
    }
    #else
    /// Built with an SDK older than macOS 26: no system glass to use.
    private func glass<V: View>(_ content: V, variation: GlassStyle) -> some View {
        approximateGlass(content, variation: variation)
    }
    #endif

    /// Before macOS 26: a blur of the desktop with a thin bright rim, lighter than the
    /// classic panel. Clear uses a see-through material, Tinted a frosted one.
    private func approximateGlass<V: View>(_ content: V, variation: GlassStyle) -> some View {
        let material: NSVisualEffectView.Material = variation == .clear ? .fullScreenUI : .popover
        let rimTop: Double = colorScheme == .dark ? 0.32 : 0.75
        let rimBottom: Double = colorScheme == .dark ? 0.08 : 0.25
        return content
            .background(VisualEffectBackdrop(material: material, cornerRadius: cornerRadius))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(rimTop), Color.white.opacity(rimBottom)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            )
    }
}

/// An `NSVisualEffectView` blurring what is behind the window, masked to a rounded rectangle.
struct VisualEffectBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        if view.material != material { view.material = material }
        if view.maskImage?.capInsets.top != cornerRadius {
            view.maskImage = Self.roundedMask(radius: cornerRadius)
        }
    }

    /// Stretchable rounded-rect mask; `capInsets.top` doubles as the radius it was made for.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Groups the panel's glass shapes so the system renders them together (macOS 26), and
/// does nothing otherwise. The spacing is 0, so the preview card and the main block stay
/// two separate pieces of glass.
struct SwitcherGlassGroup<Content: View>: View {
    let style: PanelBackdropStyle
    @ViewBuilder let content: () -> Content

    #if compiler(>=6.2)
    var body: some View {
        if case .glass = style.material {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 0) {
                    content()
                }
            } else {
                content()
            }
        } else {
            content()
        }
    }
    #else
    var body: some View {
        content()
    }
    #endif
}

/// A color theme drawn like Little Joan's (and Arc's): a soft linear gradient with two
/// blurred color blobs and fine grain, at the theme's opacity, over the glass or blur.
/// Nothing when the theme is off. Colors come from `ThemeGradient` (the core), muted into
/// the light or dark band of the panel's current appearance.
struct ThemeBackground: View {
    let theme: ColorTheme
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if theme.isEnabled {
            let gradient = ThemeGradient(theme: theme, scheme: colorScheme == .dark ? .dark : .light)
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    base(gradient, size: size)
                    blob(gradient.bottomLeftBlob, strength: gradient.bottomLeftStrength,
                         center: ThemeGradient.bottomLeftBlobCenter, radii: ThemeGradient.bottomLeftBlobRadii, size: size)
                    blob(gradient.topRightBlob, strength: gradient.topRightStrength,
                         center: ThemeGradient.topRightBlobCenter, radii: ThemeGradient.topRightBlobRadii, size: size)
                    if gradient.grainOpacity > 0, let grain = GrainImage.image {
                        Image(decorative: grain, scale: max(1, displayScale))
                            .resizable(resizingMode: .tile)
                            .interpolation(.none)
                            .opacity(gradient.grainOpacity)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
            .compositingGroup()
            .opacity(theme.opacity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func base(_ gradient: ThemeGradient, size: CGSize) -> some View {
        let points = gradient.baseGradientPoints(width: Double(size.width), height: Double(size.height))
        return LinearGradient(
            stops: gradient.baseStops.map { Gradient.Stop(color: Color($0.color), location: CGFloat($0.location)) },
            startPoint: UnitPoint(x: points.start.x, y: points.start.y),
            endPoint: UnitPoint(x: points.end.x, y: points.end.y)
        )
    }

    /// A soft elliptical blob of `color` centred on a corner, fading out along
    /// `ThemeGradient.blobFalloff` (radii are fractions of the view's size).
    private func blob(
        _ color: SRGBColor,
        strength: Double,
        center: (x: Double, y: Double),
        radii: (width: Double, height: Double),
        size: CGSize
    ) -> some View {
        let stops = ThemeGradient.blobFalloff.map {
            Gradient.Stop(color: Color(color).opacity($0.alpha * strength), location: CGFloat($0.location))
        }
        return Rectangle()
            .fill(EllipticalGradient(stops: stops, center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
            .frame(width: 2 * radii.width * size.width, height: 2 * radii.height * size.height)
            .position(x: center.x * size.width, y: center.y * size.height)
    }
}

extension Color {
    init(_ color: SRGBColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 1)
    }
}

/// The grain tile, made once from the core's deterministic noise.
@MainActor
enum GrainImage {
    static let image: CGImage? = {
        let side = GrainTexture.defaultSide
        let pixels = GrainTexture.pixels(side: side, seed: GrainTexture.defaultSeed)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }()
}
