import AppKit
import SwiftUI
import TapTheTabCore

/// One card in the grid style.
struct ItemCardView: View {
    let cell: SwitcherCell
    let isSelected: Bool
    let size: CGSize
    let icon: NSImage
    let thumbnail: CGImage?
    let showAppName: Bool
    let isPinned: Bool
    /// "⌘1"… for the first nine items when quick select is on.
    let quickSelectLabel: String?
    /// Shared by the grid's cards so the selection highlight slides between them.
    let selectionNamespace: Namespace.ID?
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    private static let innerPadding: CGFloat = 8

    private var item: SwitcherItem { cell.ranked.item }
    private var match: FuzzyMatch? { cell.ranked.match }
    private var isDimmed: Bool { item.isMinimized || item.isAppHidden }

    private var titleFontSize: CGFloat { size.width < 140 ? 11 : 12 }
    private var titleLines: Int { size.height >= 130 ? 2 : 1 }
    /// Very small (shrunk) cards drop the app name to keep the title readable.
    private var showsAppNameLine: Bool { showAppName && size.height >= 90 }

    private var textHeight: CGFloat {
        var height = CGFloat(titleLines) * (titleFontSize * 1.3)
        if showsAppNameLine {
            height += (titleFontSize - 1) * 1.3 + 2
        }
        return height
    }

    private var innerWidth: CGFloat { max(10, size.width - Self.innerPadding * 2) }
    private var previewHeight: CGFloat { max(10, size.height - Self.innerPadding * 2 - textHeight - 4) }
    private var iconSide: CGFloat { min(96, max(16, min(previewHeight, innerWidth) * 0.9)) }

    var body: some View {
        VStack(spacing: 4) {
            preview
                .frame(width: innerWidth, height: previewHeight)
                .overlay(alignment: .topTrailing) {
                    ItemBadges(item: item, size: 10, isPinned: isPinned)
                }
                .overlay(alignment: .topLeading) {
                    if let quickSelectLabel {
                        QuickSelectBadge(label: quickSelectLabel)
                    }
                }
            VStack(spacing: 2) {
                HighlightedText.make(item.displayTitle, indices: match?.titleIndices ?? [])
                    .font(.system(size: titleFontSize, weight: .medium))
                    .lineLimit(titleLines)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                if showsAppNameLine {
                    HighlightedText.make(item.appName, indices: match?.appNameIndices ?? [], baseColor: Color.secondary)
                        .font(.system(size: titleFontSize - 1))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: innerWidth, height: textHeight, alignment: .top)
        }
        .padding(Self.innerPadding)
        .opacity(isDimmed ? 0.6 : 1)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(SelectionHighlight(isSelected: isSelected, cornerRadius: 10, namespace: selectionNamespace))
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(item.displayTitle), \(item.appName)"))
        .accessibilityValue(Text(verbatim: ItemBadges.accessibilityDescription(for: item, isPinned: isPinned)))
        .accessibilityHint(Text(verbatim: QuickSelectBadge.accessibilityHint(for: quickSelectLabel)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
                .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                .overlay(alignment: .bottomLeading) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                        .offset(x: -4, y: 4)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSide, height: iconSide)
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Small state symbols: pinned app, minimized, hidden app, fullscreen, app without windows.
struct ItemBadges: View {
    let item: SwitcherItem
    let size: CGFloat
    var isPinned: Bool = false

    private static var pinnedText: String { L10n.tr("Pinned") }
    private static var minimizedText: String { L10n.tr("Minimized") }
    private static var hiddenText: String { L10n.tr("App is hidden") }
    private static var fullscreenText: String { L10n.tr("Full screen") }
    private static var windowlessText: String { L10n.tr("No open windows") }

    /// The badges as words, e.g. "Minimized, App is hidden"; empty when there are none.
    /// Used as the accessibility value of a card or row, whose label is "<title>, <app>".
    static func accessibilityDescription(for item: SwitcherItem, isPinned: Bool = false) -> String {
        var parts: [String] = []
        if isPinned { parts.append(pinnedText) }
        if item.isMinimized { parts.append(minimizedText) }
        if item.isAppHidden { parts.append(hiddenText) }
        if item.isFullscreen { parts.append(fullscreenText) }
        if item.isWindowless { parts.append(windowlessText) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 3) {
            if isPinned {
                badge("pin.fill", Self.pinnedText)
            }
            if item.isMinimized {
                badge("minus.circle", Self.minimizedText)
            }
            if item.isAppHidden {
                badge("eye.slash", Self.hiddenText)
            }
            if item.isFullscreen {
                badge("arrow.up.left.and.arrow.down.right", Self.fullscreenText)
            }
            if item.isWindowless {
                badge("app.dashed", Self.windowlessText)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundColor(Color.secondary)
    }

    private func badge(_ systemName: String, _ text: String) -> some View {
        Image(systemName: systemName)
            .help(text)
            .accessibilityLabel(Text(text))
    }
}

/// The quick-select key of a card or row, e.g. "⌘1", in a small capsule.
struct QuickSelectBadge: View {
    let label: String

    /// Spoken after the item, e.g. "Press ⌘1 to switch to it"; empty without a label.
    static func accessibilityHint(for label: String?) -> String {
        guard let label else { return "" }
        return L10n.tr("Press %@ to switch to it", label)
    }

    var body: some View {
        Text(verbatim: label)
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundColor(Color.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule(style: .continuous).fill(.thinMaterial))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// The selected card's or row's highlight. With a namespace it is one shape shared by all
/// cards (or rows), so an animated selection change slides it to the new one.
struct SelectionHighlight: View {
    let isSelected: Bool
    let cornerRadius: CGFloat
    let namespace: Namespace.ID?

    /// One highlight per grid or list.
    private static let matchID = "selection"

    var body: some View {
        if isSelected {
            if let namespace {
                SelectionBackground(isSelected: true, cornerRadius: cornerRadius)
                    .matchedGeometryEffect(id: Self.matchID, in: namespace)
            } else {
                SelectionBackground(isSelected: true, cornerRadius: cornerRadius)
            }
        }
    }
}

/// Accent fill plus stroke for the selected card or row; clear otherwise.
struct SelectionBackground: View {
    let isSelected: Bool
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
    }
}
