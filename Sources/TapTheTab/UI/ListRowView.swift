import AppKit
import SwiftUI
import TapTheTabCore

/// One row in the list style. With previews and window thumbnails on, the row is taller
/// and leads with the window's live thumbnail (its app icon as a badge) and two lines of
/// text; otherwise the app icon and one line.
struct ListRowView: View {
    let cell: SwitcherCell
    let isSelected: Bool
    let icon: NSImage
    let thumbnail: CGImage?
    let showsThumbnail: Bool
    let rowHeight: CGFloat
    let showAppName: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    private var item: SwitcherItem { cell.ranked.item }
    private var match: FuzzyMatch? { cell.ranked.match }
    private var isDimmed: Bool { item.isMinimized || item.isAppHidden }

    /// Thumbnail box in a tall row: 16:10, the common window shape, as large as the row allows.
    private var thumbnailSize: CGSize {
        let height = max(24, rowHeight - 4 - 10)
        return CGSize(width: (height * 1.6).rounded(), height: height)
    }

    var body: some View {
        if showsThumbnail {
            tallRow
        } else {
            compactRow
        }
    }

    private var tallRow: some View {
        HStack(spacing: 12) {
            ListRowThumbnail(icon: icon, thumbnail: thumbnail, size: thumbnailSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    HighlightedText.make(item.displayTitle, indices: match?.titleIndices ?? [])
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    ItemBadges(item: item, size: 11)
                }
                if showAppName {
                    HighlightedText.make(item.appName, indices: match?.appNameIndices ?? [], baseColor: Color.secondary)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
        }
        .opacity(isDimmed ? 0.6 : 1)
        .padding(.horizontal, 8)
        .frame(height: rowHeight - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SelectionBackground(isSelected: isSelected, cornerRadius: 10))
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(item.displayTitle), \(item.appName)"))
        .accessibilityValue(Text(verbatim: ItemBadges.accessibilityDescription(for: item)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private var compactRow: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            HighlightedText.make(item.displayTitle, indices: match?.titleIndices ?? [])
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            ItemBadges(item: item, size: 11)
            Spacer(minLength: 8)
            if showAppName {
                HighlightedText.make(item.appName, indices: match?.appNameIndices ?? [], baseColor: Color.secondary)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .opacity(isDimmed ? 0.6 : 1)
        .padding(.horizontal, 10)
        .frame(height: rowHeight - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SelectionBackground(isSelected: isSelected, cornerRadius: 8))
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(item.displayTitle), \(item.appName)"))
        .accessibilityValue(Text(verbatim: ItemBadges.accessibilityDescription(for: item)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// A list row's window thumbnail, aspect-fit in a fixed box with the app icon as a badge
/// in its corner; the app icon alone (larger) when there is no thumbnail, e.g. for
/// minimized windows and hidden apps.
struct ListRowThumbnail: View {
    let icon: NSImage
    let thumbnail: CGImage?
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: Color.black.opacity(0.2), radius: 1.5, x: 0, y: 1)
                    .padding(2)
            } else {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.height * 0.8, height: size.height * 0.8)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottomTrailing) {
            if thumbnail != nil {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .offset(x: 5, y: 4)
            }
        }
        .accessibilityHidden(true)
    }
}
