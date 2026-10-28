import Foundation

/// Plain size type so the core does not depend on CoreGraphics.
public struct Size: Equatable, Hashable, Sendable, Codable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct GridMetrics: Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    /// Card size after scaling to fit.
    public var itemSize: Size
    /// Total panel content size including padding.
    public var contentSize: Size
    /// 1.0 when cards fit at full size; smaller when they were shrunk.
    public var scale: Double
    /// True when even the smallest scale does not fit and the content must scroll.
    public var needsScrolling: Bool
}

/// Works out how many cards fit per row on a screen, shrinking them when needed.
///
/// Cards shrink (down to `minimumScale`) until the content fits within
/// `maxScreenFraction` of the screen in both directions. If it still is too tall at the
/// minimum scale, the height is capped and `needsScrolling` is set. Width never scrolls:
/// the available width is never taken as less than one card at the minimum scale plus
/// padding, so `contentSize.width` can exceed the screen only on screens narrower than that.
public enum GridLayout {
    public static let minimumScale = 0.6

    public static func compute(
        itemCount: Int,
        screen: Size,
        item: Size,
        spacing: Double = 12,
        padding: Double = 20,
        maxScreenFraction: Double = 0.9
    ) -> GridMetrics {
        let count = max(itemCount, 0)
        let maxWidth = max(screen.width * maxScreenFraction, item.width * minimumScale + padding * 2)
        let maxHeight = max(screen.height * maxScreenFraction, item.height * minimumScale + padding * 2)

        func fit(scale: Double) -> (columns: Int, rows: Int, size: Size, content: Size) {
            let w = item.width * scale
            let h = item.height * scale
            let usable = maxWidth - padding * 2
            // Guard the division: zero-sized cards give NaN/infinity and huge screens overflow Int,
            // both of which trap when converted. More than `count` per row is never needed.
            let ratio = (usable + spacing) / (w + spacing)
            let perRow = ratio.isFinite
                ? max(1, Int(min(ratio, Double(max(count, 1))).rounded(.down)))
                : max(count, 1)
            let columns = max(1, min(count, perRow))
            let rows = count == 0 ? 0 : Int((Double(count) / Double(columns)).rounded(.up))
            let contentW = Double(columns) * w + Double(max(columns - 1, 0)) * spacing + padding * 2
            let contentH = Double(rows) * h + Double(max(rows - 1, 0)) * spacing + padding * 2
            return (columns, rows, Size(width: w, height: h), Size(width: contentW, height: contentH))
        }

        // Shrink in 5% steps until the content fits both the height and the width (a single
        // column of very large cards, or a narrow screen, can be wider than the screen).
        var scale = 1.0
        var result = fit(scale: scale)
        while (result.content.height > maxHeight || result.content.width > maxWidth) && scale > minimumScale {
            scale = max(minimumScale, scale - 0.05)
            result = fit(scale: scale)
        }
        let scrolling = result.content.height > maxHeight
        let content = scrolling ? Size(width: result.content.width, height: maxHeight) : result.content
        return GridMetrics(
            columns: result.columns,
            rows: result.rows,
            itemSize: result.size,
            contentSize: content,
            scale: scale,
            needsScrolling: scrolling
        )
    }
}
