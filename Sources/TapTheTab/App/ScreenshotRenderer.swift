import AppKit
import ImageIO
import SwiftUI
import TapTheTabCore
import UniformTypeIdentifiers

// `TapTheTab --render-screenshots <dir>` (see TapTheTabMain): draws the real switcher and
// Settings views from built-in sample data into PNGs for the README. Everything shown is
// made up: fictional window titles, icons of apps that ship with macOS, and synthetic
// window previews drawn below. Nothing is read from the screen, the window list, the
// config file or the network, and no permission is needed. Output is deterministic for
// a given macOS version.
//
// `TapTheTab --render-demo <file>` (same rules) draws a short animation of the switcher
// from the same sample data into an animated PNG for the README and the website.

/// Light or dark version of a screenshot.
enum ScreenshotMode: CaseIterable {
    case light
    case dark

    var suffix: String {
        switch self {
        case .light: return "light"
        case .dark: return "dark"
        }
    }

    var theme: Theme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// An sRGB colour for the drawings.
struct ScreenshotColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let blue = ScreenshotColor(red: 0.04, green: 0.52, blue: 1.00)
    static let green = ScreenshotColor(red: 0.20, green: 0.78, blue: 0.35)
    static let yellow = ScreenshotColor(red: 1.00, green: 0.78, blue: 0.04)
    static let red = ScreenshotColor(red: 1.00, green: 0.27, blue: 0.23)
    static let orange = ScreenshotColor(red: 1.00, green: 0.58, blue: 0.00)
    static let pink = ScreenshotColor(red: 1.00, green: 0.22, blue: 0.37)
    static let purple = ScreenshotColor(red: 0.69, green: 0.32, blue: 0.87)
    static let teal = ScreenshotColor(red: 0.19, green: 0.69, blue: 0.78)
    static let indigo = ScreenshotColor(red: 0.35, green: 0.34, blue: 0.84)
    static let graphite = ScreenshotColor(red: 0.56, green: 0.56, blue: 0.58)

    /// For avatars, photo tiles and settings icons.
    static let palette: [ScreenshotColor] = [blue, green, orange, pink, purple, teal, yellow, indigo, red]
}

/// One made-up window of the sample data.
struct SampleWindow {
    /// What the synthetic preview looks like.
    enum Content {
        case terminal, browser, mail, notes, calendar, pdf, finder, music, chat, photos, settings, document
    }

    let title: String
    let appName: String
    /// An app that ships with macOS, for a real icon.
    let bundleID: String
    /// Not a real process; only keys the icon.
    let pid: Int32
    let windowNumber: UInt32
    let content: Content
    let accent: ScreenshotColor
    var isMinimized: Bool = false
    var isAppHidden: Bool = false

    var item: SwitcherItem {
        SwitcherItem(
            id: .window(windowNumber),
            pid: pid,
            appName: appName,
            bundleID: bundleID,
            title: title,
            isMinimized: isMinimized,
            isAppHidden: isAppHidden
        )
    }
}

/// A switcher panel drawn from sample data, before it is composed onto a desktop.
private struct RenderedPanel {
    let panel: CGImage
    let layout: SwitcherLayout
    let previewCard: CGSize
    let backdrop: PanelBackdropStyle
}

@MainActor
enum ScreenshotRenderer {
    struct Result {
        var written: [URL] = []
        var failures: [String] = []
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    enum Shot: CaseIterable {
        case grid, search, previews, themed, settings

        var name: String {
            switch self {
            case .grid: return "switcher-grid"
            case .themed: return "switcher-themed"
            case .search: return "switcher-search"
            case .previews: return "switcher-previews"
            case .settings: return "settings-general"
            }
        }
    }

    /// The pretend screen's visible frame, in points (a 14-inch MacBook Pro at its default
    /// resolution, below the menu bar). The panel is laid out for it like on a real screen.
    static let screenSize = CGSize(width: 1512, height: 945)
    /// Pixels per point of the PNGs.
    static let scale: CGFloat = 2

    /// Desktop visible around the panel or window.
    private static let margin: CGFloat = 64
    private static let panelCornerRadius: CGFloat = SwitcherLayout.panelCornerRadius
    private static let previewCardCornerRadius: CGFloat = SwitcherLayout.previewCardCornerRadius
    private static let windowCornerRadius: CGFloat = 10
    private static let titleBarHeight: CGFloat = 28
    /// Same as `SettingsWindowController`'s window.
    private static let settingsContentSize = CGSize(width: 640, height: 520)

    /// Most recently used first, as the switcher would list them. Item 1 (selected on open)
    /// has a preview; one window is minimized and one app hidden, to show the badges.
    static let samples: [SampleWindow] = [
        SampleWindow(title: "~/code/tapthetab — zsh", appName: "Terminal", bundleID: "com.apple.Terminal",
                     pid: 70_001, windowNumber: 4_101, content: .terminal, accent: .green),
        SampleWindow(title: "Pull request #42 — tapthetab", appName: "Safari", bundleID: "com.apple.Safari",
                     pid: 70_002, windowNumber: 4_102, content: .browser, accent: .blue),
        SampleWindow(title: "Inbox — 3 unread", appName: "Mail", bundleID: "com.apple.mail",
                     pid: 70_003, windowNumber: 4_103, content: .mail, accent: .blue),
        SampleWindow(title: "Project notes", appName: "Notes", bundleID: "com.apple.Notes",
                     pid: 70_004, windowNumber: 4_104, content: .notes, accent: .yellow),
        SampleWindow(title: "Design review — Thursday", appName: "Calendar", bundleID: "com.apple.iCal",
                     pid: 70_005, windowNumber: 4_105, content: .calendar, accent: .red),
        SampleWindow(title: "Q4 roadmap.pdf", appName: "Preview", bundleID: "com.apple.Preview",
                     pid: 70_006, windowNumber: 4_106, content: .pdf, accent: .orange),
        SampleWindow(title: "Release checklist", appName: "Notes", bundleID: "com.apple.Notes",
                     pid: 70_004, windowNumber: 4_107, content: .notes, accent: .yellow),
        SampleWindow(title: "Downloads", appName: "Finder", bundleID: "com.apple.finder",
                     pid: 70_007, windowNumber: 4_108, content: .finder, accent: .blue),
        SampleWindow(title: "Focus playlist", appName: "Music", bundleID: "com.apple.Music",
                     pid: 70_008, windowNumber: 4_109, content: .music, accent: .pink, isAppHidden: true),
        SampleWindow(title: "Weekend recipes", appName: "Safari", bundleID: "com.apple.Safari",
                     pid: 70_002, windowNumber: 4_110, content: .browser, accent: .green),
        SampleWindow(title: "launch-post-draft.txt", appName: "TextEdit", bundleID: "com.apple.TextEdit",
                     pid: 70_009, windowNumber: 4_111, content: .document, accent: .graphite, isMinimized: true),
        SampleWindow(title: "Team standup", appName: "Messages", bundleID: "com.apple.MobileSMS",
                     pid: 70_010, windowNumber: 4_112, content: .chat, accent: .blue),
        SampleWindow(title: "Trip to Lisbon", appName: "Photos", bundleID: "com.apple.Photos",
                     pid: 70_011, windowNumber: 4_113, content: .photos, accent: .teal),
        SampleWindow(title: "Keyboard", appName: "System Settings", bundleID: "com.apple.systempreferences",
                     pid: 70_012, windowNumber: 4_114, content: .settings, accent: .blue),
    ]

    /// Renders every shot in light and dark into `directory` (created if needed). A failed
    /// shot is reported and the others are still written.
    static func renderAll(to directory: URL) -> Result {
        var result = Result()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            result.failures.append("cannot create \(directory.path): \(error.localizedDescription)")
            return result
        }
        for mode in ScreenshotMode.allCases {
            let icons = loadIcons(mode: mode)
            for shot in Shot.allCases {
                let url = directory.appendingPathComponent("\(shot.name)-\(mode.suffix).png")
                do {
                    let image = try render(shot, mode: mode, icons: icons)
                    try writePNG(image, to: url)
                    result.written.append(url)
                } catch {
                    result.failures.append("\(url.lastPathComponent): \(error)")
                }
            }
        }
        return result
    }

    // MARK: - Shots

    private static func render(_ shot: Shot, mode: ScreenshotMode, icons: [Int32: NSImage]) throws -> CGImage {
        switch shot {
        case .grid:
            return try switcherShot(style: .grid, query: "", previews: false, mode: mode, icons: icons)
        case .search:
            return try switcherShot(style: .list, query: "re", previews: false, mode: mode, icons: icons)
        case .previews:
            return try switcherShot(style: .grid, query: "", previews: true, mode: mode, icons: icons)
        case .themed:
            // The list with window thumbnails on a theme (Dusk), no large preview.
            let theme = ThemePreset.named("dusk").map { ColorTheme.none.applying($0) } ?? ColorTheme.none
            // Eight windows: a scrolling list does not render offscreen.
            return try switcherShot(style: .list, query: "", previews: true, largePreview: false, theme: theme,
                                    sampleLimit: 8, mode: mode, icons: icons)
        case .settings:
            return try settingsShot(mode: mode)
        }
    }

    /// The switcher as `SwitcherPanelController` would show it for the sample windows.
    private static func switcherShot(
        style: LayoutStyle,
        query: String,
        previews: Bool,
        largePreview: Bool = true,
        theme: ColorTheme = .none,
        sampleLimit: Int? = nil,
        mode: ScreenshotMode,
        icons: [Int32: NSImage]
    ) throws -> CGImage {
        let rendered = try switcherPanel(
            style: style, query: query, previews: previews, largePreview: largePreview,
            theme: theme, sampleLimit: sampleLimit, mode: mode, icons: icons
        )
        return try composeSwitcher(
            panel: rendered.panel,
            layout: rendered.layout,
            previewCard: rendered.previewCard,
            backdrop: rendered.backdrop,
            mode: mode
        )
    }

    /// The panel's content for the sample windows, before it is put on a desktop. `inputs`
    /// are applied to the opened (and searched) session, like keys pressed in the switcher.
    private static func switcherPanel(
        style: LayoutStyle,
        query: String,
        previews: Bool,
        largePreview: Bool = true,
        theme: ColorTheme = .none,
        sampleLimit: Int? = nil,
        inputs: [SwitcherInput] = [],
        mode: ScreenshotMode,
        icons: [Int32: NSImage]
    ) throws -> RenderedPanel {
        var appearance = Appearance()
        appearance.style = style
        appearance.size = .medium
        appearance.showPreviews = previews
        appearance.showLargePreview = largePreview
        appearance.colorTheme = theme
        appearance.showAppName = true
        appearance.theme = mode.theme
        let behavior = Behavior()

        let shown = sampleLimit.map { Array(samples.prefix($0)) } ?? samples
        var session = SwitcherSession(
            items: shown.map { $0.item },
            startsOnPrevious: behavior.startOnPrevious,
            wrapsAround: behavior.wrapAround
        )
        for character in query {
            session.handle(.type(String(character)))
        }
        func layoutForSession() -> SwitcherLayout {
            SwitcherPanelController.layout(
                for: session,
                appearance: appearance,
                showsPreview: appearance.showPreviews && appearance.showLargePreview && session.selectedItem != nil,
                screenSize: screenSize
            )
        }
        var layout = layoutForSession()
        session.columns = layout.columns
        if !inputs.isEmpty {
            // Arrow keys need the column count of the layout, so they come after it.
            for input in inputs {
                session.handle(input)
            }
            layout = layoutForSession()
            session.columns = layout.columns
        }

        let model = SwitcherViewModel()
        model.iconOverrides = icons
        model.present(session: session, appearance: appearance, behavior: behavior, layout: layout)
        if previews {
            // Like the real app, minimized windows and hidden apps have no preview.
            for sample in shown where !sample.isMinimized && !sample.isAppHidden {
                guard let image = WindowArt.image(for: sample, mode: mode, scale: scale) else {
                    throw Failure("could not draw the preview for \(sample.appName)")
                }
                model.setThumbnail(image, for: sample.item.id)
            }
        }

        let panel = try renderPanel(model: model, size: layout.boundingSize, mode: mode)
        return RenderedPanel(
            panel: panel,
            layout: layout,
            previewCard: model.previewCardSize,
            backdrop: PanelBackdropStyle(appearance)
        )
    }

    /// Settings → General with the default configuration and both permissions granted.
    private static func settingsShot(mode: ScreenshotMode) throws -> CGImage {
        let model = SettingsViewModel(
            configuration: Configuration(),
            permissions: SamplePermissions(),
            launchAtLogin: SampleLaunchAtLogin(),
            configFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("config.json"),
            onChange: { _ in }
        )
        let hostingView = NSHostingView(rootView: SettingsView(model: model))
        hostingView.sizingOptions = []
        let content = try captureInWindow(hostingView, size: settingsContentSize, mode: mode, titled: true)
        return try composeSettings(content: content, mode: mode)
    }

    // MARK: - Rendering views

    /// The panel's SwiftUI content (transparent where the panel's material would be).
    /// `ImageRenderer` draws it at exactly `scale` whatever the runner's display is;
    /// should it produce nothing, the same view is captured from an offscreen window.
    private static func renderPanel(model: SwitcherViewModel, size: CGSize, mode: ScreenshotMode) throws -> CGImage {
        let content = SwitcherRootView(model: model)
            .environment(\.switcherDrawsBackdrop, false)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, mode.colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        var rendered: CGImage?
        drawing(in: mode) {
            rendered = renderer.cgImage
        }
        if let rendered, !looksBlank(rendered) {
            return rendered
        }
        let hostingView = NSHostingView(rootView: SwitcherRootView(model: model).environment(\.switcherDrawsBackdrop, false))
        hostingView.sizingOptions = []
        return try captureInWindow(hostingView, size: size, mode: mode, titled: false)
    }

    /// Hosts `view` in a window that is never shown and draws it into a `scale`× bitmap.
    private static func captureInWindow(_ view: NSView, size: CGSize, mode: ScreenshotMode, titled: Bool) throws -> CGImage {
        let styleMask: NSWindow.StyleMask = titled ? [.titled, .closable, .miniaturizable] : [.borderless]
        let window = ScreenshotWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = mode.appearance
        if !titled {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        view.appearance = mode.appearance
        view.frame = NSRect(origin: .zero, size: size)
        window.contentView = view
        window.setContentSize(size)
        settle(view)

        let bounds = view.bounds
        let pixelsWide = Int((bounds.width * scale).rounded())
        let pixelsHigh = Int((bounds.height * scale).rounded())
        guard pixelsWide > 0, pixelsHigh > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else {
            throw Failure("could not allocate a \(pixelsWide)×\(pixelsHigh) bitmap")
        }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        withExtendedLifetime(window) {}

        guard let image = rep.cgImage else {
            throw Failure("could not read back the offscreen window")
        }
        if looksBlank(image) {
            throw Failure("the offscreen window drew nothing")
        }
        return image
    }

    /// Lets SwiftUI and AppKit finish building the views without running the app.
    /// Bounded: returns after a fixed 0.3 s even if nothing is scheduled.
    private static func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        let deadline = Date(timeIntervalSinceNow: 0.3)
        while Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: deadline)
        }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    /// Runs `body` with `mode`'s appearance as the current drawing appearance, so system
    /// colours and icons resolve to light or dark.
    private static func drawing(in mode: ScreenshotMode, _ body: () -> Void) {
        guard let appearance = mode.appearance else {
            body()
            return
        }
        withoutActuallyEscaping(body) { block in
            appearance.performAsCurrentDrawingAppearance(block)
        }
    }

    // MARK: - Composition

    /// The panel on a desktop: the main block (and the preview card floating above it, if
    /// any), each with a shadow, a translucent fill over the desktop (stands in for the
    /// behind-window blur or glass, which do not render offscreen) and a hairline; then the
    /// content on top.
    private static func composeSwitcher(
        panel: CGImage,
        layout: SwitcherLayout,
        previewCard: CGSize,
        backdrop: PanelBackdropStyle,
        mode: ScreenshotMode,
        canvasSize: CGSize? = nil
    ) throws -> CGImage {
        let size = layout.boundingSize
        // The panel sits in the middle of the canvas: `margin` all around by default, or
        // a larger fixed canvas (the demo's frames, which differ in size, share one).
        let canvas = canvasSize ?? CGSize(width: size.width + margin * 2, height: size.height + margin * 2)
        let origin = CGPoint(
            x: ((canvas.width - size.width) / 2).rounded(),
            y: ((canvas.height - size.height) / 2).rounded()
        )
        let context = try canvasContext(size: canvas)
        drawDesktop(in: context, size: canvas, mode: mode)

        // Core Graphics counts y upwards: the main block is at the bottom of the panel.
        let mainFrame = CGRect(x: origin.x + ((size.width - layout.mainSize.width) / 2).rounded(),
                               y: origin.y, width: layout.mainSize.width, height: layout.mainSize.height)
        var pieces: [(frame: CGRect, radius: CGFloat)] = [(mainFrame, panelCornerRadius)]
        if previewCard.width > 0, previewCard.height > 0 {
            let cardFrame = CGRect(
                x: origin.x + ((size.width - previewCard.width) / 2).rounded(),
                y: mainFrame.maxY + SwitcherLayout.previewGap,
                width: previewCard.width,
                height: previewCard.height
            )
            pieces.append((cardFrame, previewCardCornerRadius))
        }

        let material: CGColor
        let shadowFill: CGColor
        switch backdrop.material {
        case .classic:
            material = mode == .light ? gray(0.97, 0.80) : gray(0.13, 0.80)
            shadowFill = mode == .light ? gray(0.93) : gray(0.16)
        case .glass(.clear):
            material = mode == .light ? gray(1, 0.45) : gray(0.10, 0.45)
            shadowFill = mode == .light ? gray(0.96, 0.6) : gray(0.20, 0.6)
        case .glass(.tinted):
            material = mode == .light ? gray(0.98, 0.70) : gray(0.16, 0.70)
            shadowFill = mode == .light ? gray(0.95) : gray(0.18)
        }

        for piece in pieces {
            drawShadow(of: roundedPath(piece.frame, radius: piece.radius), fill: shadowFill, in: context, mode: mode)
        }
        for piece in pieces {
            context.saveGState()
            context.addPath(roundedPath(piece.frame, radius: piece.radius))
            context.clip()
            drawDesktop(in: context, size: canvas, mode: mode)
            context.setFillColor(material)
            context.fill(piece.frame)
            context.restoreGState()
        }
        // Like the real backdrops, the shapes clip the content at their rounded corners.
        context.saveGState()
        for piece in pieces {
            context.addPath(roundedPath(piece.frame, radius: piece.radius))
        }
        context.clip()
        context.draw(panel, in: CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height))
        context.restoreGState()
        for piece in pieces {
            strokeHairline(around: piece.frame, radius: piece.radius, in: context, mode: mode)
        }
        guard let image = context.makeImage() else { throw Failure("could not finish the switcher image") }
        return image
    }

    /// The Settings content in a window frame (title bar, traffic lights, title) on a desktop.
    private static func composeSettings(content: CGImage, mode: ScreenshotMode) throws -> CGImage {
        let contentSize = settingsContentSize
        let windowSize = CGSize(width: contentSize.width, height: contentSize.height + titleBarHeight)
        let canvas = CGSize(width: windowSize.width + margin * 2, height: windowSize.height + margin * 2)
        let context = try canvasContext(size: canvas)
        drawDesktop(in: context, size: canvas, mode: mode)

        let frame = CGRect(origin: CGPoint(x: margin, y: margin), size: windowSize)
        let shape = roundedPath(frame, radius: windowCornerRadius)
        let background = mode == .light ? gray(0.925) : gray(0.196)
        drawShadow(of: shape, fill: background, in: context, mode: mode)

        let titleBar = CGRect(x: frame.minX, y: frame.maxY - titleBarHeight, width: frame.width, height: titleBarHeight)
        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.setFillColor(background)
        context.fill(frame)
        context.draw(content, in: CGRect(origin: frame.origin, size: contentSize))
        context.setFillColor(mode == .light ? gray(0, 0.10) : gray(0, 0.55))
        context.fill(CGRect(x: titleBar.minX, y: titleBar.minY - 1 / scale, width: titleBar.width, height: 1 / scale))
        context.restoreGState()

        drawTrafficLights(in: context, titleBar: titleBar)
        drawTitle(L10n.tr("TapTheTab Settings"), in: titleBar, context: context, mode: mode)
        strokeHairline(around: frame, radius: windowCornerRadius, in: context, mode: mode)
        guard let image = context.makeImage() else { throw Failure("could not finish the settings image") }
        return image
    }

    /// A `scale`× bitmap context drawn in points.
    private static func canvasContext(size: CGSize) throws -> CGContext {
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard let context = makeBitmapContext(width: width, height: height) else {
            throw Failure("could not allocate a \(width)×\(height) canvas")
        }
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        return context
    }

    /// A soft diagonal gradient with a glow, standing in for a wallpaper.
    private static func drawDesktop(in context: CGContext, size: CGSize, mode: ScreenshotMode) {
        let colors: [CGColor]
        let glow: CGColor
        switch mode {
        case .light:
            colors = [rgb(0.78, 0.86, 0.97), rgb(0.88, 0.84, 0.97), rgb(0.98, 0.88, 0.85)]
            glow = gray(1, 0.45)
        case .dark:
            colors = [rgb(0.09, 0.12, 0.25), rgb(0.19, 0.12, 0.30), rgb(0.30, 0.13, 0.24)]
            glow = rgb(0.50, 0.40, 0.95, 0.28)
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let locations: [CGFloat] = [0, 0.55, 1]
        if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: size.width, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        let fade = glow.copy(alpha: 0) ?? glow
        let glowLocations: [CGFloat] = [0, 1]
        if let gradient = CGGradient(colorsSpace: space, colors: [glow, fade] as CFArray, locations: glowLocations) {
            let center = CGPoint(x: size.width * 0.78, y: size.height * 0.85)
            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: max(size.width, size.height) * 0.6,
                options: []
            )
        }
    }

    private static func drawShadow(of shape: CGPath, fill: CGColor, in context: CGContext, mode: ScreenshotMode) {
        context.saveGState()
        // Shadow offset and blur are in pixels: the scale transform does not apply to them.
        context.setShadow(
            offset: CGSize(width: 0, height: -14 * scale),
            blur: 40 * scale,
            color: gray(0, mode == .light ? 0.30 : 0.60)
        )
        context.addPath(shape)
        context.setFillColor(fill)
        context.fillPath()
        context.restoreGState()
    }

    private static func strokeHairline(around frame: CGRect, radius: CGFloat, in context: CGContext, mode: ScreenshotMode) {
        context.saveGState()
        context.addPath(roundedPath(frame.insetBy(dx: 0.5, dy: 0.5), radius: radius - 0.5))
        context.setStrokeColor(mode == .light ? gray(0, 0.12) : gray(1, 0.16))
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawTrafficLights(in context: CGContext, titleBar: CGRect) {
        let fills = [rgb(1.00, 0.37, 0.34), rgb(1.00, 0.74, 0.18), rgb(0.16, 0.78, 0.25)]
        let strokes = [rgb(0.88, 0.27, 0.24), rgb(0.87, 0.63, 0.14), rgb(0.10, 0.67, 0.16)]
        for index in 0..<fills.count {
            let center = CGPoint(x: titleBar.minX + 14 + CGFloat(index) * 20, y: titleBar.midY)
            let dot = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
            context.setFillColor(fills[index])
            context.fillEllipse(in: dot)
            context.setStrokeColor(strokes[index])
            context.setLineWidth(0.5)
            context.strokeEllipse(in: dot.insetBy(dx: 0.25, dy: 0.25))
        }
    }

    private static func drawTitle(_ title: String, in titleBar: CGRect, context: CGContext, mode: ScreenshotMode) {
        let color: NSColor = mode == .light
            ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.85)
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.titleBarFont(ofSize: 13),
            .foregroundColor: color,
        ]
        let string = NSAttributedString(string: title, attributes: attributes)
        let size = string.size()
        let origin = CGPoint(x: (titleBar.midX - size.width / 2).rounded(), y: titleBar.midY - size.height / 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Icons and files

    private static func loadIcons(mode: ScreenshotMode) -> [Int32: NSImage] {
        var icons: [Int32: NSImage] = [:]
        for sample in samples where icons[sample.pid] == nil {
            icons[sample.pid] = appIcon(bundleID: sample.bundleID, mode: mode)
        }
        return icons
    }

    /// The installed app's icon, or the generic app icon when it isn't installed.
    private static func appIcon(bundleID: String, mode: ScreenshotMode) -> NSImage {
        let workspace = NSWorkspace.shared
        let source: NSImage
        if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            source = workspace.icon(forFile: url.path)
        } else {
            source = workspace.icon(for: UTType.application)
        }
        var flattened: NSImage?
        drawing(in: mode) {
            flattened = rasterize(source, pixels: 512)
        }
        return flattened ?? source
    }

    /// One large bitmap, so the icon is equally sharp however SwiftUI scales it.
    private static func rasterize(_ image: NSImage, pixels: Int) -> NSImage? {
        guard let context = makeBitmapContext(width: pixels, height: pixels) else { return nil }
        let side = CGFloat(pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 128, height: 128))
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        // Points, so the file says it is a 2× (144 dpi) image.
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw Failure("PNG encoding failed")
        }
        try data.write(to: url, options: .atomic)
    }

    /// True when an image is (almost) empty: nearly fully transparent, or one flat colour.
    private static func looksBlank(_ image: CGImage) -> Bool {
        let side = 64
        guard let context = makeBitmapContext(width: side, height: side) else { return false }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return false }
        let bytesPerRow = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * side)
        var covered = 0
        var darkest = 255
        var lightest = 0
        for y in 0..<side {
            for x in 0..<side {
                let offset = y * bytesPerRow + x * 4
                guard pixels[offset + 3] > 16 else { continue }
                covered += 1
                let luma = (Int(pixels[offset]) * 3 + Int(pixels[offset + 1]) * 6 + Int(pixels[offset + 2])) / 10
                darkest = min(darkest, luma)
                lightest = max(lightest, luma)
            }
        }
        return covered < side * side / 100 || lightest - darkest < 12
    }
}

// MARK: - Demo animation

/// One frame of the demo: the switcher opened on a scene, searched, and then fed some keys.
private struct DemoFrame {
    enum Scene {
        /// All fourteen windows in the grid, with thumbnails and the large preview.
        case grid
        /// A plain list of the first ten windows (a list this long still fits without scrolling).
        case list
        /// A list on the Dusk theme with window thumbnails.
        case themedList
    }

    let scene: Scene
    var query: String = ""
    var inputs: [SwitcherInput] = []
    /// How long the frame stays on screen, in seconds.
    let seconds: TimeInterval
}

extension ScreenshotRenderer {
    /// The animation, in order: the selection stepping through the grid, a search narrowing
    /// the list, and the selection moving on a themed list.
    private static let demoFrames: [DemoFrame] = [
        DemoFrame(scene: .grid, seconds: 1.0),
        DemoFrame(scene: .grid, inputs: [.next], seconds: 0.5),
        DemoFrame(scene: .grid, inputs: [.next, .next], seconds: 0.5),
        DemoFrame(scene: .grid, inputs: [.next, .next, .next], seconds: 0.5),
        DemoFrame(scene: .grid, inputs: [.next, .next, .next, .moveDown], seconds: 1.0),
        DemoFrame(scene: .list, seconds: 0.8),
        DemoFrame(scene: .list, query: "r", seconds: 0.6),
        DemoFrame(scene: .list, query: "re", seconds: 0.8),
        DemoFrame(scene: .list, query: "re", inputs: [.next], seconds: 1.0),
        DemoFrame(scene: .themedList, seconds: 0.8),
        DemoFrame(scene: .themedList, inputs: [.next], seconds: 0.5),
        DemoFrame(scene: .themedList, inputs: [.next, .next], seconds: 0.5),
        DemoFrame(scene: .themedList, inputs: [.next, .next, .next], seconds: 1.4),
    ]

    /// Widest the animation may be, in pixels.
    private static let demoMaxWidth = 1600
    /// The encoded file should stay below this; frames are scaled down until it does.
    private static let demoMaxBytes = 3_000_000
    /// Rows in the themed list (a list that scrolls does not render offscreen).
    private static let demoThemedRows = 7

    /// Renders the demo (light appearance) into the animated PNG `url`. The parent folder is
    /// created if needed.
    static func renderDemo(to url: URL) -> Result {
        var result = Result()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try writeDemo(to: url)
            result.written.append(url)
        } catch {
            result.failures.append("\(url.lastPathComponent): \(error)")
        }
        return result
    }

    private static func writeDemo(to url: URL) throws {
        let mode = ScreenshotMode.light
        let icons = loadIcons(mode: mode)
        let dusk = ThemePreset.named("dusk").map { ColorTheme.none.applying($0) } ?? ColorTheme.none

        // First every panel, since the frames differ in size and share the largest canvas.
        var panels: [RenderedPanel] = []
        for frame in demoFrames {
            switch frame.scene {
            case .grid:
                panels.append(try switcherPanel(
                    style: .grid, query: frame.query, previews: true,
                    inputs: frame.inputs, mode: mode, icons: icons
                ))
            case .list:
                panels.append(try switcherPanel(
                    style: .list, query: frame.query, previews: false, sampleLimit: 10,
                    inputs: frame.inputs, mode: mode, icons: icons
                ))
            case .themedList:
                panels.append(try switcherPanel(
                    style: .list, query: frame.query, previews: true, largePreview: false, theme: dusk,
                    sampleLimit: demoThemedRows, inputs: frame.inputs, mode: mode, icons: icons
                ))
            }
        }
        let canvas = CGSize(
            width: (panels.map { $0.layout.boundingSize.width }.max() ?? 0) + margin * 2,
            height: (panels.map { $0.layout.boundingSize.height }.max() ?? 0) + margin * 2
        )
        var images: [CGImage] = []
        for panel in panels {
            images.append(try composeSwitcher(
                panel: panel.panel,
                layout: panel.layout,
                previewCard: panel.previewCard,
                backdrop: panel.backdrop,
                mode: mode,
                canvasSize: canvas
            ))
        }

        guard let firstWidth = images.first?.width else { throw Failure("no frames") }
        var factor = min(1, CGFloat(demoMaxWidth) / CGFloat(firstWidth))
        var data = Data()
        for attempt in 1...4 {
            let sized = try images.map { try resized($0, by: factor) }
            data = try encodeAnimatedPNG(sized, delays: demoFrames.map { $0.seconds })
            if data.count <= demoMaxBytes { break }
            if attempt < 4 {
                factor *= 0.75
            } else {
                FileHandle.standardError.write(Data(
                    "note: the animation is \(data.count) bytes, above the \(demoMaxBytes) target\n".utf8
                ))
            }
        }
        try data.write(to: url, options: .atomic)
    }

    /// `image` scaled by `factor` (1 returns it as is).
    private static func resized(_ image: CGImage, by factor: CGFloat) throws -> CGImage {
        guard factor < 1 else { return image }
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let context = makeBitmapContext(width: width, height: height) else {
            throw Failure("could not allocate a \(width)×\(height) frame")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { throw Failure("could not scale a frame") }
        return scaled
    }

    /// An animated PNG (APNG) with `delays[i]` seconds per frame, repeating forever.
    private static func encodeAnimatedPNG(_ frames: [CGImage], delays: [TimeInterval]) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, frames.count, nil
        ) else {
            throw Failure("this system cannot write PNG animations")
        }
        let fileProperties: [String: Any] = [
            kCGImagePropertyPNGDictionary as String: [kCGImagePropertyAPNGLoopCount as String: 0],
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        for (index, frame) in frames.enumerated() {
            let frameProperties: [String: Any] = [
                kCGImagePropertyPNGDictionary as String: [kCGImagePropertyAPNGDelayTime as String: delays[index]],
            ]
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw Failure("PNG animation encoding failed")
        }
        let data = output as Data
        // An APNG carries an animation control chunk before its image data.
        guard data.range(of: Data("acTL".utf8)) != nil else {
            throw Failure("the encoder wrote a still image, not an animation")
        }
        return data
    }
}

/// Never ordered on screen. Claims to be key so controls draw in their active colours
/// (an inactive window draws switches and the selected tab in grey).
private final class ScreenshotWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

@MainActor
private final class SamplePermissions: PermissionsProviding {
    var accessibilityGranted: Bool { true }
    var screenRecordingGranted: Bool { true }
    func requestAccessibility() {}
    func requestScreenRecording() {}
    func openAccessibilitySettings() {}
    func openScreenRecordingSettings() {}
}

@MainActor
private final class SampleLaunchAtLogin: LaunchAtLoginProviding {
    var isEnabled: Bool { true }
    func setEnabled(_ enabled: Bool) throws {}
}

// MARK: - Drawing helpers

private func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: white, green: white, blue: white, alpha: alpha)
}

private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

/// Rounded rectangle; the radius is clamped, since CGPath traps on one too large for the rect.
private func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let clamped = max(0, min(radius, rect.width / 2, rect.height / 2))
    return CGPath(roundedRect: rect, cornerWidth: clamped, cornerHeight: clamped, transform: nil)
}

/// An sRGB, premultiplied-alpha bitmap context.
private func makeBitmapContext(width: Int, height: Int) -> CGContext? {
    guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    return CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

// MARK: - Synthetic window previews

/// Draws a made-up window (title bar plus grey text bars and coloured blocks, no real
/// text or content) to stand in for a window preview.
private struct WindowArt {
    /// In points; 16:10, like a typical window.
    static let size = CGSize(width: 680, height: 425)
    private static let titleBarHeight: CGFloat = 28
    /// Lengths of successive text lines, as fractions of the available width.
    private static let lineLengths: [CGFloat] = [0.92, 0.74, 0.86, 0.58, 0.95, 0.68, 0.81, 0.47]

    let context: CGContext
    let mode: ScreenshotMode
    let accent: ScreenshotColor

    static func image(for sample: SampleWindow, mode: ScreenshotMode, scale: CGFloat) -> CGImage? {
        let pixelsWide = Int((size.width * scale).rounded())
        let pixelsHigh = Int((size.height * scale).rounded())
        guard let context = makeBitmapContext(width: pixelsWide, height: pixelsHigh) else { return nil }
        context.scaleBy(x: scale, y: scale)
        // Top-left origin; only rectangles and circles are drawn, so nothing comes out mirrored.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        WindowArt(context: context, mode: mode, accent: sample.accent).draw(sample.content)
        return context.makeImage()
    }

    // MARK: Palette

    private var isLight: Bool { mode == .light }
    private var base: CGColor { isLight ? gray(1) : gray(0.12) }
    private var bar: CGColor { isLight ? gray(0.93) : gray(0.20) }
    private var side: CGColor { isLight ? gray(0.955) : gray(0.165) }
    private var ink: CGColor { isLight ? gray(0, 0.20) : gray(1, 0.24) }
    private var strong: CGColor { isLight ? gray(0, 0.42) : gray(1, 0.50) }
    private var faint: CGColor { isLight ? gray(0, 0.07) : gray(1, 0.08) }
    private var rule: CGColor { isLight ? gray(0, 0.09) : gray(0, 0.40) }
    private var bubble: CGColor { isLight ? gray(0.90) : gray(0.24) }
    private var switchOff: CGColor { isLight ? gray(0.82) : gray(0.32) }

    private func tint(_ alpha: CGFloat) -> CGColor { accent.cgColor(alpha: alpha) }

    private func length(_ index: Int, of width: CGFloat) -> CGFloat {
        (width * Self.lineLengths[index % Self.lineLengths.count]).rounded()
    }

    // MARK: Primitives

    private func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: CGColor, radius: CGFloat = 0) {
        let rect = CGRect(x: x, y: y, width: width, height: height)
        context.setFillColor(color)
        if radius > 0 {
            context.addPath(roundedPath(rect, radius: radius))
            context.fillPath()
        } else {
            context.fill(rect)
        }
    }

    private func dot(_ centerX: CGFloat, _ centerY: CGFloat, _ radius: CGFloat, _ color: CGColor) {
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2))
    }

    /// `count` lines of "text" of varied length.
    private func text(_ x: CGFloat, _ y: CGFloat, width: CGFloat, count: Int, spacing: CGFloat = 16,
                      height: CGFloat = 6, color: CGColor? = nil, seed: Int = 0) {
        for line in 0..<count {
            box(x, y + CGFloat(line) * spacing, length(line + seed, of: width), height, color ?? ink, radius: height / 2)
        }
    }

    private func sidebar(width: CGFloat) {
        box(0, Self.titleBarHeight, width, Self.size.height - Self.titleBarHeight, side)
        box(width, Self.titleBarHeight, 1, Self.size.height - Self.titleBarHeight, rule)
    }

    // MARK: Windows

    func draw(_ content: SampleWindow.Content) {
        let width = Self.size.width
        let height = Self.size.height
        box(0, 0, width, height, base)

        switch content {
        case .terminal: drawTerminal()
        case .browser: drawBrowser()
        case .mail: drawMail()
        case .notes: drawNotes()
        case .calendar: drawCalendar()
        case .pdf: drawPDF()
        case .finder: drawFinder()
        case .music: drawMusic()
        case .chat: drawChat()
        case .photos: drawPhotos()
        case .settings: drawSettings()
        case .document: drawDocument()
        }

        // Title bar: traffic lights and a title-shaped bar.
        box(0, 0, width, Self.titleBarHeight, bar)
        box(0, Self.titleBarHeight - 1, width, 1, rule)
        let lights = [rgb(1.00, 0.37, 0.34), rgb(1.00, 0.74, 0.18), rgb(0.16, 0.78, 0.25)]
        for (index, light) in lights.enumerated() {
            dot(14 + CGFloat(index) * 20, 14, 6, light)
        }
        box(width / 2 - 70, 11, 140, 6, ink, radius: 3)
    }

    private func drawTerminal() {
        for line in 0..<20 {
            let y = 42 + CGFloat(line) * 18
            if line % 4 == 0 || line == 19 {
                box(14, y, 8, 8, tint(0.95), radius: 2)
                if line == 19 {
                    box(28, y - 1, 8, 10, tint(0.85))
                } else {
                    box(28, y + 1, 90 + CGFloat((line * 37) % 160), 6, strong, radius: 3)
                }
            } else {
                box(14, y + 1, length(line, of: 520), 6, ink, radius: 3)
            }
        }
    }

    private func drawBrowser() {
        let width = Self.size.width
        box(0, 28, width, 34, bar)
        box(0, 61, width, 1, rule)
        box(16, 40, 18, 12, faint, radius: 3)
        box(40, 40, 18, 12, faint, radius: 3)
        box(190, 37, 300, 18, faint, radius: 9)
        box(270, 43, 140, 6, ink, radius: 3)

        box(40, 84, 600, 120, tint(0.88), radius: 10)
        box(64, 118, 260, 14, gray(1, 0.9), radius: 4)
        box(64, 142, 180, 10, gray(1, 0.65), radius: 4)
        box(64, 170, 90, 18, gray(1, 0.85), radius: 9)
        text(40, 224, width: 600, count: 4)
        for card in 0..<3 {
            let x = 40 + CGFloat(card) * 204
            box(x, 300, 192, 104, faint, radius: 8)
            box(x + 12, 314, 64, 8, tint(0.6), radius: 4)
            text(x + 12, 334, width: 168, count: 4, spacing: 14, seed: card)
        }
    }

    private func drawMail() {
        sidebar(width: 150)
        text(16, 48, width: 110, count: 8, spacing: 22, height: 7, seed: 2)
        for row in 0..<7 {
            let y = 28 + CGFloat(row) * 56
            if row == 0 { box(151, y, 189, 56, tint(0.20)) }
            box(164, y + 12, row == 0 ? 120 : 100, 7, strong, radius: 3.5)
            box(164, y + 26, length(row, of: 150), 6, ink, radius: 3)
            box(164, y + 38, 160, 5, faint, radius: 2.5)
            box(151, y + 55, 189, 1, rule)
        }
        box(340, 28, 1, Self.size.height - 28, rule)
        dot(374, 66, 16, tint(0.75))
        box(400, 56, 150, 8, strong, radius: 4)
        box(400, 70, 100, 6, ink, radius: 3)
        box(356, 100, 308, 1, rule)
        text(360, 118, width: 300, count: 10, seed: 1)
    }

    private func drawNotes() {
        sidebar(width: 180)
        for row in 0..<7 {
            let y = 40 + CGFloat(row) * 48
            if row == 0 { box(8, y - 4, 164, 44, tint(0.55), radius: 6) }
            box(20, y + 6, length(row + 3, of: 130), 7, strong, radius: 3.5)
            box(20, y + 20, 90, 6, ink, radius: 3)
        }
        box(212, 52, 240, 14, strong, radius: 5)
        text(212, 84, width: 430, count: 5, seed: 3)
        for item in 0..<5 {
            let y = 176 + CGFloat(item) * 22
            context.setStrokeColor(tint(0.9))
            context.setLineWidth(1.5)
            context.strokeEllipse(in: CGRect(x: 212, y: y, width: 12, height: 12))
            if item < 2 { dot(218, y + 6, 4, tint(0.9)) }
            box(234, y + 3, length(item + 5, of: 300), 6, ink, radius: 3)
        }
        text(212, 300, width: 430, count: 6, seed: 6)
    }

    private func drawCalendar() {
        let width = Self.size.width
        let top: CGFloat = 68
        let cellWidth = width / 7
        let cellHeight = (Self.size.height - top) / 5
        box(0, 28, width, 40, bar)
        box(16, 42, 130, 12, strong, radius: 5)
        box(width - 120, 42, 104, 12, faint, radius: 6)
        for column in 1..<7 {
            box(CGFloat(column) * cellWidth, top, 1, Self.size.height - top, rule)
        }
        for row in 0..<5 {
            let y = top + CGFloat(row) * cellHeight
            box(0, y, width, 1, rule)
            for column in 0..<7 {
                let x = CGFloat(column + 1) * cellWidth - 20
                if row == 1 && column == 4 {
                    dot(x + 6, y + 9, 8, tint(0.9))
                    box(x, y + 6, 12, 6, gray(1, 0.9), radius: 3)
                } else {
                    box(x, y + 6, 12, 6, ink, radius: 3)
                }
            }
        }
        let events: [(column: Int, row: Int, primary: Bool)] = [
            (1, 0, true), (3, 1, false), (4, 1, true), (2, 1, true), (0, 2, false),
            (2, 2, true), (5, 3, true), (1, 4, false), (3, 4, true),
        ]
        for event in events {
            let x = CGFloat(event.column) * cellWidth + 5
            let y = top + CGFloat(event.row) * cellHeight + 22
            box(x, y, cellWidth - 10, 14, event.primary ? tint(0.8) : ScreenshotColor.teal.cgColor(alpha: 0.75), radius: 3)
        }
    }

    private func drawPDF() {
        let width = Self.size.width
        box(0, 28, width, Self.size.height - 28, side)
        box(0, 28, 120, Self.size.height - 28, isLight ? gray(0.92) : gray(0.14))
        for page in 0..<3 {
            let y = 44 + CGFloat(page) * 112
            box(30, y, 60, 84, base, radius: 2)
            if page == 0 {
                context.setStrokeColor(tint(0.9))
                context.setLineWidth(2)
                context.stroke(CGRect(x: 27, y: y - 3, width: 66, height: 90))
            }
        }
        box(150, 42, 500, 368, base, radius: 2)
        box(184, 76, 240, 16, strong, radius: 5)
        box(184, 100, 160, 8, ink, radius: 4)
        let bars: [CGFloat] = [70, 110, 95, 160, 210]
        for (index, barHeight) in bars.enumerated() {
            box(204 + CGFloat(index) * 84, 370 - barHeight, 48, barHeight, tint(0.45 + 0.12 * CGFloat(index)), radius: 3)
        }
        box(184, 370, 432, 1, rule)
    }

    private func drawFinder() {
        sidebar(width: 150)
        for row in 0..<9 {
            let y = 48 + CGFloat(row) * 24
            if row == 2 { box(8, y - 6, 134, 20, faint, radius: 5) }
            dot(24, y + 4, 5, tint(0.85))
            box(36, y + 1, length(row, of: 90), 6, ink, radius: 3)
        }
        for row in 0..<3 {
            for column in 0..<5 {
                let x = 186 + CGFloat(column) * 96
                let y = 56 + CGFloat(row) * 116
                box(x, y, 28, 12, tint(0.8), radius: 3)
                box(x, y + 6, 64, 48, tint(0.8), radius: 6)
                box(x + 4, y + 66, 56, 6, ink, radius: 3)
            }
        }
    }

    private func drawMusic() {
        sidebar(width: 170)
        text(18, 52, width: 120, count: 9, spacing: 24, height: 7, seed: 4)
        box(196, 50, 120, 120, tint(0.85), radius: 8)
        dot(256, 110, 34, gray(1, 0.35))
        dot(256, 110, 8, tint(0.95))
        box(336, 74, 210, 14, strong, radius: 5)
        box(336, 98, 130, 8, ink, radius: 4)
        box(336, 136, 84, 26, tint(0.95), radius: 13)
        box(428, 136, 84, 26, faint, radius: 13)
        for row in 0..<10 {
            let y = 188 + CGFloat(row) * 22
            if row % 2 == 1 { box(186, y, 478, 22, faint) }
            box(196, y + 8, 10, 6, ink, radius: 3)
            box(220, y + 8, length(row + 1, of: 220), 6, ink, radius: 3)
            box(620, y + 8, 30, 6, ink, radius: 3)
        }
    }

    private func drawChat() {
        let width = Self.size.width
        sidebar(width: 200)
        for row in 0..<6 {
            let y = 36 + CGFloat(row) * 60
            let selected = row == 0
            if selected { box(8, y, 184, 56, tint(0.85), radius: 8) }
            let avatar = ScreenshotColor.palette[(row + 2) % ScreenshotColor.palette.count]
            dot(36, y + 28, 18, selected ? gray(1, 0.5) : avatar.cgColor(alpha: 0.85))
            box(62, y + 18, 90, 7, selected ? gray(1, 0.9) : strong, radius: 3.5)
            box(62, y + 32, length(row, of: 110), 6, selected ? gray(1, 0.6) : ink, radius: 3)
        }
        let bubbles: [(mine: Bool, width: CGFloat, height: CGFloat)] = [
            (false, 210, 30), (true, 170, 30), (false, 260, 44), (true, 230, 30), (true, 130, 30), (false, 190, 30),
        ]
        var y: CGFloat = 50
        for message in bubbles {
            let x = message.mine ? width - 20 - message.width : 220
            box(x, y, message.width, message.height, message.mine ? tint(0.95) : bubble, radius: 15)
            box(x + 14, y + 12, message.width - 40, 6, message.mine ? gray(1, 0.8) : ink, radius: 3)
            if message.height > 40 {
                box(x + 14, y + 26, message.width - 80, 6, message.mine ? gray(1, 0.8) : ink, radius: 3)
            }
            y += message.height + 12
        }
        box(220, Self.size.height - 38, 440, 24, faint, radius: 12)
    }

    private func drawPhotos() {
        sidebar(width: 150)
        text(16, 50, width: 110, count: 8, spacing: 24, height: 7, seed: 5)
        let tile: CGFloat = 82
        let gap: CGFloat = 4
        let palette = ScreenshotColor.palette
        for row in 0..<5 {
            for column in 0..<6 {
                let x = 160 + CGFloat(column) * (tile + gap)
                let y = 36 + CGFloat(row) * (tile + gap)
                let color = palette[(row * 6 + column * 5) % palette.count]
                box(x, y, tile, tile, color.cgColor(alpha: 0.85))
                box(x, y + tile * 0.6, tile, tile * 0.4, gray(0, 0.15))
            }
        }
    }

    private func drawSettings() {
        sidebar(width: 200)
        box(12, 40, 176, 22, faint, radius: 7)
        let palette = ScreenshotColor.palette
        for row in 0..<10 {
            let y = 74 + CGFloat(row) * 30
            let selected = row == 4
            if selected { box(8, y - 4, 184, 26, tint(0.9), radius: 6) }
            box(18, y, 18, 18, palette[row % palette.count].cgColor(), radius: 5)
            box(44, y + 6, length(row, of: 110), 6, selected ? gray(1, 0.9) : strong, radius: 3)
        }
        box(224, 46, 130, 12, strong, radius: 5)
        let groups: [(top: CGFloat, rows: Int)] = [(74, 3), (196, 4)]
        for group in groups {
            box(220, group.top, 440, CGFloat(group.rows) * 36, faint, radius: 8)
            for row in 0..<group.rows {
                let y = group.top + CGFloat(row) * 36
                if row > 0 { box(232, y, 416, 1, rule) }
                box(236, y + 15, length(row + group.rows, of: 220), 6, strong, radius: 3)
                let isOn = (row + group.rows) % 2 == 0
                box(612, y + 9, 34, 19, isOn ? tint(0.95) : switchOff, radius: 9.5)
                dot(isOn ? 636.5 : 621.5, y + 18.5, 7.5, gray(1))
            }
        }
    }

    private func drawDocument() {
        let width = Self.size.width
        box(0, 28, width, 26, bar)
        for tick in 0..<24 {
            let tickHeight: CGFloat = tick % 4 == 0 ? 8 : 4
            box(40 + CGFloat(tick) * 25, 54 - tickHeight, 1, tickHeight, ink)
        }
        box(0, 54, width, 1, rule)
        box(40, 74, 220, 12, strong, radius: 5)
        text(40, 102, width: 600, count: 6)
        text(40, 210, width: 600, count: 6, seed: 3)
        text(40, 318, width: 600, count: 5, seed: 5)
    }
}
