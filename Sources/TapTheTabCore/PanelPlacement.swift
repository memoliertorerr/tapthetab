import Foundation

/// A rectangle in screen points, origin at the bottom left and y growing upwards (AppKit's
/// screen coordinates).
public struct ScreenRect: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var size: Size { Size(width: width, height: height) }
}

/// Where the user dragged one of the switcher's two blocks, as fractions of the screen's
/// visible frame so it means the same on every display. `x` is the block's horizontal
/// centre; `y` is the main block's top edge or the preview card's bottom edge (the edges
/// that stay put while the block changes size). Stored in config.json.
public struct BlockPosition: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Both values finite; out-of-range values are clamped by `clamped`.
    public var isValid: Bool { x.isFinite && y.isFinite }

    /// Within 0...1.
    public var clamped: BlockPosition {
        BlockPosition(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(Double.self, forKey: .x)
        let y = try c.decode(Double.self, forKey: .y)
        guard x.isFinite, y.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .x, in: c, debugDescription: "not a number")
        }
        self.x = x
        self.y = y
    }
}

/// Where the switcher's two blocks go on a screen: the main block (search bar plus grid or
/// list) and the large preview's card. By default they sit together in the middle of the
/// screen, the card just above the main block; either can be dragged elsewhere, and a
/// dragged position is remembered as a `BlockPosition`. Every frame stays inside the
/// visible frame.
public enum PanelPlacement {
    /// Space between the main block and a card that follows it.
    public static var gap: Double { PanelLayout.previewGap }

    /// The two frames for blocks of `mainSize` and (when the preview shows) `previewSize`
    /// on a screen whose visible frame is `visible`.
    ///
    /// - The main block goes where `mainPosition` says, else centred together with the card.
    /// - The card goes where `previewPosition` says; without one it follows the main block:
    ///   centred above it, or below it when there is no room above.
    public static func frames(
        visible: ScreenRect,
        mainSize: Size,
        previewSize: Size?,
        mainPosition: BlockPosition?,
        previewPosition: BlockPosition?
    ) -> (main: ScreenRect, preview: ScreenRect?) {
        let preview = previewSize.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
        let main: ScreenRect
        if let position = mainPosition, position.isValid {
            let p = position.clamped
            main = clamp(ScreenRect(
                x: visible.minX + p.x * visible.width - mainSize.width / 2,
                y: visible.minY + p.y * visible.height - mainSize.height,
                width: mainSize.width,
                height: mainSize.height
            ), in: visible)
        } else {
            let total = mainSize.height + (preview.map { $0.height + gap } ?? 0)
            let top = visible.midY + total / 2
            main = clamp(ScreenRect(
                x: visible.midX - mainSize.width / 2,
                y: top - (preview.map { $0.height + gap } ?? 0) - mainSize.height,
                width: mainSize.width,
                height: mainSize.height
            ), in: visible)
        }

        guard let preview else { return (main, nil) }
        if let position = previewPosition, position.isValid {
            let p = position.clamped
            return (main, clamp(ScreenRect(
                x: visible.minX + p.x * visible.width - preview.width / 2,
                y: visible.minY + p.y * visible.height,
                width: preview.width,
                height: preview.height
            ), in: visible))
        }
        let x = main.midX - preview.width / 2
        let above = ScreenRect(x: x, y: main.maxY + gap, width: preview.width, height: preview.height)
        if above.maxY <= visible.maxY {
            return (main, clamp(above, in: visible))
        }
        let below = ScreenRect(x: x, y: main.minY - gap - preview.height, width: preview.width, height: preview.height)
        if below.minY >= visible.minY {
            return (main, clamp(below, in: visible))
        }
        return (main, clamp(above, in: visible))
    }

    /// `frame` moved (not resized, unless it is larger than `visible`) so it lies inside
    /// `visible`, with whole-point coordinates.
    public static func clamp(_ frame: ScreenRect, in visible: ScreenRect) -> ScreenRect {
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        var x = frame.x.isFinite ? frame.x : visible.midX - width / 2
        var y = frame.y.isFinite ? frame.y : visible.midY - height / 2
        x = min(max(x, visible.minX), visible.maxX - width)
        y = min(max(y, visible.minY), visible.maxY - height)
        return ScreenRect(x: x.rounded(), y: y.rounded(), width: width, height: height)
    }

    /// The position to remember for a main block dragged to `frame`.
    public static func mainPosition(of frame: ScreenRect, in visible: ScreenRect) -> BlockPosition {
        position(x: frame.midX, y: frame.maxY, in: visible)
    }

    /// The position to remember for a preview card dragged to `frame`.
    public static func previewPosition(of frame: ScreenRect, in visible: ScreenRect) -> BlockPosition {
        position(x: frame.midX, y: frame.minY, in: visible)
    }

    private static func position(x: Double, y: Double, in visible: ScreenRect) -> BlockPosition {
        guard visible.width > 0, visible.height > 0 else { return BlockPosition(x: 0.5, y: 0.5) }
        return BlockPosition(
            x: (x - visible.minX) / visible.width,
            y: (y - visible.minY) / visible.height
        ).clamped
    }
}
