import AppKit
import SwiftUI
import TapTheTabCore

/// What sits behind the switcher's main block and its preview card.
enum PanelBackdropStyle: Equatable {
    /// The dark heads-up-display material of earlier versions.
    case classic
    /// Liquid Glass in one of its two variations. macOS 26 and later draw the system's
    /// glass; earlier versions get a translucent blur with a glass-like rim.
    case glass(GlassStyle)

    init(_ appearance: Appearance) {
        self = appearance.liquidGlass ? .glass(appearance.glassStyle) : .classic
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
        if !drawsBackdrop {
            content
        } else {
            switch style {
            case .classic:
                content.background(VisualEffectBackdrop(material: .hudWindow, cornerRadius: cornerRadius))
            case .glass(let variation):
                glass(content, variation: variation)
            }
        }
    }

    #if compiler(>=6.2)
    @ViewBuilder
    private func glass(_ content: Content, variation: GlassStyle) -> some View {
        if #available(macOS 26.0, *) {
            systemGlass(content, variation: variation)
        } else {
            approximateGlass(content, variation: variation)
        }
    }

    /// The system's Liquid Glass. Clear lets the desktop show through; a light dimming
    /// layer keeps text readable over bright windows (Apple's advice for clear glass).
    /// Tinted is the frosted regular glass. Both follow Reduce Transparency and
    /// Increase Contrast on their own.
    @available(macOS 26.0, *)
    @ViewBuilder
    private func systemGlass(_ content: Content, variation: GlassStyle) -> some View {
        switch variation {
        case .clear:
            content
                .background(shape.fill(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06)))
                .glassEffect(.clear, in: shape)
        case .tinted:
            content
                .glassEffect(.regular, in: shape)
        }
    }
    #else
    /// Built with an SDK older than macOS 26: no system glass to use.
    private func glass(_ content: Content, variation: GlassStyle) -> some View {
        approximateGlass(content, variation: variation)
    }
    #endif

    /// Before macOS 26: a blur of the desktop with a thin bright rim, lighter than the
    /// classic panel. Clear uses a see-through material, Tinted a frosted one.
    private func approximateGlass(_ content: Content, variation: GlassStyle) -> some View {
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
        if case .glass = style {
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
