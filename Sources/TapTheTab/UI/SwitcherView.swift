import AppKit
import SwiftUI
import TapTheTabCore

/// Root of the switcher panel's SwiftUI content.
struct SwitcherRootView: View {
    @ObservedObject var model: SwitcherViewModel

    var body: some View {
        VStack(spacing: 0) {
            if model.layout.showsSearchBar {
                SwitcherSearchBar(
                    query: model.session.query,
                    isLocked: model.session.isLocked,
                    searchEnabled: model.behavior.searchEnabled,
                    isLarge: model.layout.style == .list
                )
                Divider()
            }
            if model.layout.showsPreview {
                Group {
                    if let preview = model.selectedPreview {
                        SwitcherLargePreview(image: preview, boxSize: model.layout.previewSize)
                    } else if let item = model.session.selectedItem {
                        SwitcherPreviewPlaceholder(icon: model.icon(for: item.pid), boxSize: model.layout.previewSize)
                    }
                }
                .padding(.top, SwitcherLayout.previewInset)
                .padding(.bottom, SwitcherLayout.previewBottomGap)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        if model.session.visible.isEmpty {
            SwitcherEmptyView(query: model.session.query)
        } else if model.layout.style == .list {
            SwitcherListView(model: model)
        } else {
            SwitcherGridView(model: model)
        }
    }
}

struct SwitcherSearchBar: View {
    let query: String
    let isLocked: Bool
    let searchEnabled: Bool
    let isLarge: Bool

    private var fontSize: CGFloat { isLarge ? 17 : 15 }

    private var hint: String {
        query.isEmpty
            ? L10n.tr("⇧W close · ⇧M minimize · ⇧Q quit · ⎋ close")
            : L10n.tr("⇧W close · ⇧M minimize · ⇧Q quit · ⎋ clear")
    }

    /// Shown in place of an empty query.
    private var placeholder: String {
        if isLocked { return L10n.tr("Locked open — ↩ to switch") }
        if searchEnabled { return L10n.tr("Type to search windows") }
        return L10n.tr("Search is turned off in Settings")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(Color.secondary)
            queryView
                .layoutPriority(1)
            Spacer(minLength: 12)
            Text(verbatim: hint)
                .font(.caption)
                .foregroundColor(Color(nsColor: NSColor.tertiaryLabelColor))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: SwitcherLayout.searchBarHeight - 1)
        // One element for VoiceOver: "Search", the query (or the placeholder), the key hints.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.tr("Search")))
        .accessibilityValue(Text(verbatim: query.isEmpty ? placeholder : query))
        .accessibilityHint(Text(verbatim: hint))
        .accessibilityAddTraits(.isSearchField)
    }

    @ViewBuilder
    private var queryView: some View {
        if !query.isEmpty {
            HStack(spacing: 1) {
                Text(verbatim: query)
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                    .truncationMode(.head)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: fontSize + 3)
            }
        } else {
            Text(verbatim: placeholder)
                .font(.system(size: fontSize))
                .foregroundColor(Color.secondary)
                .lineLimit(1)
        }
    }
}

/// Larger preview of the selected window above the grid or list (previews mode only).
/// Aspect-fit and centred in the box `SwitcherLayout` reserved; no title, since the
/// selected card or row right below already shows it.
struct SwitcherLargePreview: View {
    let image: CGImage
    let boxSize: CGSize

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 2)
            .frame(width: boxSize.width, height: boxSize.height)
            .accessibilityHidden(true)
    }
}

/// Fills the reserved preview box when the selected item has no thumbnail.
struct SwitcherPreviewPlaceholder: View {
    let icon: NSImage
    let boxSize: CGSize

    var body: some View {
        let side: CGFloat = max(32, min(128, min(boxSize.width, boxSize.height) * 0.45))
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
        }
        .frame(width: boxSize.width, height: boxSize.height)
        .accessibilityHidden(true)
    }
}

struct SwitcherEmptyView: View {
    let query: String

    private var message: String {
        query.isEmpty ? L10n.tr("No windows to show") : L10n.tr("No windows match “%@”", query)
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: query.isEmpty ? "macwindow" : "magnifyingglass")
                .font(.system(size: 22))
                .foregroundColor(Color.secondary)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(.system(size: 14))
                .foregroundColor(Color.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SwitcherGridView: View {
    @ObservedObject var model: SwitcherViewModel

    var body: some View {
        if model.layout.needsScrolling {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    grid
                        .frame(maxWidth: .infinity)
                }
                .onAppear {
                    scrollSoon(proxy)
                }
                .onChange(of: model.session.selectedIndex) { _ in
                    scrollToSelection(proxy)
                }
                .onChange(of: model.session.query) { _ in
                    scrollToSelection(proxy)
                }
            }
            .id(model.generation)
        } else {
            grid
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var grid: some View {
        let layout = model.layout
        let rows = SwitcherGridRow.rows(from: model.session.visible, columns: layout.columns)
        return VStack(alignment: .leading, spacing: SwitcherLayout.gridSpacing) {
            ForEach(rows) { row in
                HStack(spacing: SwitcherLayout.gridSpacing) {
                    ForEach(row.cells) { cell in
                        card(for: cell, layout: layout)
                    }
                }
            }
        }
        .padding(SwitcherLayout.gridPadding)
    }

    private func card(for cell: SwitcherCell, layout: SwitcherLayout) -> some View {
        let index = cell.index
        let viewModel = model
        return ItemCardView(
            cell: cell,
            isSelected: index == model.session.selectedIndex,
            size: layout.itemSize,
            icon: model.icon(for: cell.ranked.item.pid),
            thumbnail: model.thumbnail(for: cell.id),
            showAppName: model.appearance.showAppName,
            onHover: { inside in viewModel.hover(index: index, inside: inside) },
            onTap: { viewModel.click(index: index) }
        )
        .id(cell.id)
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        SwitcherScrolling.scrollToSelection(session: model.session, proxy: proxy)
    }

    private func scrollSoon(_ proxy: ScrollViewProxy) {
        let session = model.session
        Task { @MainActor in
            SwitcherScrolling.scrollToSelection(session: session, proxy: proxy)
        }
    }
}

struct SwitcherListView: View {
    @ObservedObject var model: SwitcherViewModel

    var body: some View {
        if model.layout.needsScrolling {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    rows
                }
                .onAppear {
                    scrollSoon(proxy)
                }
                .onChange(of: model.session.selectedIndex) { _ in
                    scrollToSelection(proxy)
                }
                .onChange(of: model.session.query) { _ in
                    scrollToSelection(proxy)
                }
            }
            .id(model.generation)
        } else {
            rows
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var rows: some View {
        let cells = SwitcherCell.cells(from: model.session.visible)
        let headers = model.sectionHeaders
        return VStack(spacing: 0) {
            ForEach(cells) { cell in
                if headers.contains(cell.index) {
                    // Header and row share the row's id, so scrolling to a group's first
                    // row brings its heading into view too.
                    VStack(spacing: 0) {
                        SwitcherSectionHeader(appName: cell.ranked.item.appName)
                        row(for: cell)
                    }
                    .id(cell.id)
                } else {
                    row(for: cell)
                        .id(cell.id)
                }
            }
        }
        .padding(.horizontal, SwitcherLayout.listPadding)
        .padding(.vertical, SwitcherLayout.listPadding)
    }

    private func row(for cell: SwitcherCell) -> some View {
        let index = cell.index
        let viewModel = model
        return ListRowView(
            cell: cell,
            isSelected: index == model.session.selectedIndex,
            icon: model.icon(for: cell.ranked.item.pid),
            showAppName: model.appearance.showAppName,
            onHover: { inside in viewModel.hover(index: index, inside: inside) },
            onTap: { viewModel.click(index: index) }
        )
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        SwitcherScrolling.scrollToSelection(session: model.session, proxy: proxy)
    }

    private func scrollSoon(_ proxy: ScrollViewProxy) {
        let session = model.session
        Task { @MainActor in
            SwitcherScrolling.scrollToSelection(session: session, proxy: proxy)
        }
    }
}

/// App-name heading above an app's first row in the list grouped by app.
struct SwitcherSectionHeader: View {
    let appName: String

    var body: some View {
        Text(verbatim: appName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .frame(height: SwitcherLayout.listSectionHeaderHeight, alignment: .bottomLeading)
            .accessibilityAddTraits(.isHeader)
    }
}

enum SwitcherScrolling {
    @MainActor
    static func scrollToSelection(session: SwitcherSession, proxy: ScrollViewProxy) {
        guard let index = session.selectedIndex, session.visible.indices.contains(index) else { return }
        let id: ItemID = session.visible[index].id
        proxy.scrollTo(id, anchor: nil)
    }
}
