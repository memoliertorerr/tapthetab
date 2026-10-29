import Foundation

/// The geometry of moving a window to the next display (`WindowAction.moveToNextDisplay`).
///
/// Pure translation and scaling, so it does not care whether y grows up (Cocoa,
/// `ScreenRect`'s usual convention) or down (Accessibility): feed it the window and the
/// display frames in one coordinate system and read the result in the same one.
public enum DisplayMove {
    /// The display after `current` (wrapping), or nil with fewer than two displays.
    /// A `current` outside `0..<count` starts from the first display.
    public static func nextIndex(after current: Int, count: Int) -> Int? {
        guard count > 1 else { return nil }
        guard (0..<count).contains(current) else { return 0 }
        return (current + 1) % count
    }

    /// Which display holds most of `window` (largest intersection area); nil if none
    /// intersects. Ties go to the earlier display.
    public static func displayIndex(containing window: ScreenRect, displays: [ScreenRect]) -> Int? {
        guard isUsable(window) else { return nil }
        var best: (index: Int, area: Double)?
        for (index, display) in displays.enumerated() where isUsable(display) {
            let width = min(window.maxX, display.maxX) - max(window.minX, display.minX)
            let height = min(window.maxY, display.maxY) - max(window.minY, display.minY)
            guard width > 0, height > 0 else { continue }
            let area = width * height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        return best?.index
    }

    /// `window` moved from display frame `source` to `target`: same position relative to
    /// the frame (fractions of the free space), shrunk to fit if larger than `target`,
    /// whole points, inside `target`.
    ///
    /// Degenerate input never produces NaN or infinities: an unusable `target` returns
    /// `window` unchanged; an unusable `source` or a window with no size is centred.
    public static func frame(_ window: ScreenRect, from source: ScreenRect, to target: ScreenRect) -> ScreenRect {
        guard isUsable(target) else { return window }
        let targetX = target.x.rounded(.up), targetY = target.y.rounded(.up)
        let targetMaxX = target.maxX.rounded(.down), targetMaxY = target.maxY.rounded(.down)
        let targetWidth = max(0, targetMaxX - targetX), targetHeight = max(0, targetMaxY - targetY)

        let width = fitted(window.width, into: targetWidth)
        let height = fitted(window.height, into: targetHeight)

        let fractionX = fraction(of: window.x, size: window.width, along: source.x, source.width, usable: isUsable(source))
        let fractionY = fraction(of: window.y, size: window.height, along: source.y, source.height, usable: isUsable(source))

        let x = targetX + ((targetWidth - width) * fractionX).rounded()
        let y = targetY + ((targetHeight - height) * fractionY).rounded()
        return ScreenRect(
            x: min(max(x, targetX), targetMaxX - width),
            y: min(max(y, targetY), targetMaxY - height),
            width: width,
            height: height
        )
    }

    // MARK: - Private

    /// Finite origin and finite, positive size.
    private static func isUsable(_ rect: ScreenRect) -> Bool {
        [rect.x, rect.y, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }

    /// A window length in whole points, at least 1 and at most `available` (an infinite
    /// length is simply too large; NaN or no length becomes 1).
    private static func fitted(_ length: Double, into available: Double) -> Double {
        guard length > 0 else { return min(1, available) }
        return min(max(1, length.rounded()), available)
    }

    /// Where the window sits in the source's free space along one axis: 0 at the start,
    /// 1 at the end, clamped. A window as large as the frame (no free space) counts as
    /// centred; so does anything that cannot be measured.
    private static func fraction(of position: Double, size: Double, along start: Double, _ length: Double, usable: Bool) -> Double {
        guard usable, position.isFinite, size.isFinite, size > 0 else { return 0.5 }
        let free = length - size
        guard free > 0 else { return 0.5 }
        let value = (position - start) / free
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }
}
