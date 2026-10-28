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
                    ItemBadges(item: item, size: 10)
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
        .background(SelectionBackground(isSelected: isSelected, cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(item.displayTitle), \(item.appName)"))
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
                .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                .overlay(alignment: .bottomLeading) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                        .offset(x: -4, y: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSide, height: iconSide)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Small state symbols: minimized, hidden app, fullscreen, app without windows.
struct ItemBadges: View {
    let item: SwitcherItem
    let size: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            if item.isMinimized {
                Image(systemName: "minus.circle").help("Minimized")
            }
            if item.isAppHidden {
                Image(systemName: "eye.slash").help("App is hidden")
            }
            if item.isFullscreen {
                Image(systemName: "arrow.up.left.and.arrow.down.right").help("Full screen")
            }
            if item.isWindowless {
                Image(systemName: "app.dashed").help("No open windows")
            }
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundColor(Color.secondary)
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
