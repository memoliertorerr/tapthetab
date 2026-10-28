import AppKit
import SwiftUI
import TapTheTabCore

/// One row in the list style.
struct ListRowView: View {
    let cell: SwitcherCell
    let isSelected: Bool
    let icon: NSImage
    let showAppName: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    private var item: SwitcherItem { cell.ranked.item }
    private var match: FuzzyMatch? { cell.ranked.match }
    private var isDimmed: Bool { item.isMinimized || item.isAppHidden }

    var body: some View {
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
        .frame(height: SwitcherLayout.listRowHeight - 4)
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
