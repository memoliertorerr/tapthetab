import AppKit
import SwiftUI
import TapTheTabCore

/// The main block in its own window: search bar plus grid or list, on its backdrop.
/// Dragging it (anywhere a click would not switch) moves the block.
struct SwitcherMainView: View {
    @ObservedObject var model: SwitcherViewModel

    var body: some View {
        let layout = model.layout
        let backdrop = PanelBackdropStyle(model.appearance)
        SwitcherGlassGroup(style: backdrop) {
            SwitcherMainBlock(model: model)
                .frame(width: layout.mainSize.width, height: layout.mainSize.height, alignment: .top)
                // Scrolled rows and cards stop at the rounded corners.
                .clipShape(RoundedRectangle(cornerRadius: SwitcherLayout.panelCornerRadius, style: .continuous))
                .switcherBackdrop(backdrop, cornerRadius: SwitcherLayout.panelCornerRadius)
                .switcherDraggable(.main, model: model)
                .scaleEffect(model.entranceScale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The large preview's card in its own window: it hugs the selected window's image, at
/// the bottom centre of the window (the edge next to the main block by default).
struct SwitcherPreviewView: View {
    @ObservedObject var model: SwitcherViewModel

    var body: some View {
        let backdrop = PanelBackdropStyle(model.appearance)
        SwitcherGlassGroup(style: backdrop) {
            SwitcherPreviewCard(model: model, backdrop: backdrop)
                .switcherDraggable(.preview, model: model)
                .scaleEffect(model.entranceScale, anchor: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// Both blocks the way they sit by default, the card above the main block. Only
/// `ScreenshotRenderer` draws them together; the app shows each in its own window.
struct SwitcherRootView: View {
    @ObservedObject var model: SwitcherViewModel

    var body: some View {
        let layout = model.layout
        let backdrop = PanelBackdropStyle(model.appearance)
        VStack(spacing: 0) {
            if layout.showsPreview {
                SwitcherPreviewCard(model: model, backdrop: backdrop)
                    .frame(width: layout.panelSize.width, height: layout.previewCardSize.height, alignment: .bottom)
                Color.clear
                    .frame(height: SwitcherLayout.previewGap)
                    .accessibilityHidden(true)
            }
            SwitcherMainBlock(model: model)
                .frame(width: layout.mainSize.width, height: layout.mainSize.height, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: SwitcherLayout.panelCornerRadius, style: .continuous))
                .switcherBackdrop(backdrop, cornerRadius: SwitcherLayout.panelCornerRadius)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Search bar plus grid or list (no backdrop).
struct SwitcherMainBlock: View {
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
            content
        }
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

/// The selected window's preview on a card that hugs the image, or the app icon on a
/// card the size of the whole box when there is no image (yet). Nothing without a preview.
/// One card for both, so with animations on it changes shape between windows instead of
/// being replaced (the model animates selection changes).
struct SwitcherPreviewCard: View {
    @ObservedObject var model: SwitcherViewModel
    let backdrop: PanelBackdropStyle

    var body: some View {
        let layout = model.layout
        if layout.showsPreview, let item = model.session.selectedItem {
            let preview: CGImage? = model.selectedPreview
            let card: CGSize = preview.map {
                layout.previewCardSize(fitting: CGSize(width: $0.width, height: $0.height))
            } ?? layout.previewCardSize
            ZStack {
                if let preview {
                    SwitcherLargePreview(image: preview)
                } else {
                    SwitcherPreviewPlaceholder(icon: model.icon(for: item.pid), boxSize: layout.previewSize)
                }
            }
            .padding(SwitcherLayout.previewCardPadding)
            .frame(width: card.width, height: card.height)
            .switcherBackdrop(backdrop, cornerRadius: SwitcherLayout.previewCardCornerRadius)
        }
    }
}

extension View {
    /// Dragging this view moves its block's window (see `SwitcherPanelController`), also
    /// when the drag starts on a card or row: the gesture runs alongside theirs, and a
    /// click that ends a drag does not switch (`SwitcherViewModel.click`). The pointer has
    /// to move a few points first, so a plain click still switches.
    func switcherDraggable(_ block: SwitcherBlock, model: SwitcherViewModel) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in model.drag(block, .changed) }
                .onEnded { _ in model.drag(block, .ended) }
        )
    }
}

struct SwitcherSearchBar: View {
    let query: String
    let isLocked: Bool
    let searchEnabled: Bool
    let isLarge: Bool

    private var fontSize: CGFloat { isLarge ? 17 : 15 }

    /// A few common keys only; the README lists them all.
    private var hint: String {
        query.isEmpty
            ? L10n.tr("⇧W close · ⇧M minimize · ⇧P pin · ⎋ close")
            : L10n.tr("⇧W close · ⇧M minimize · ⇧P pin · ⎋ clear")
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

/// Larger preview of the selected window on the card above the grid or list (previews
/// mode only). Fills the card minus its padding, which already has the image's shape; no
/// title, since the selected card or row right below shows it.
struct SwitcherLargePreview: View {
    let image: CGImage

    private static var cornerRadius: CGFloat {
        SwitcherLayout.previewCardCornerRadius - SwitcherLayout.previewCardPadding
    }

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
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
            RoundedRectangle(cornerRadius: SwitcherLayout.previewCardCornerRadius - SwitcherLayout.previewCardPadding,
                             style: .continuous)
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
    /// The selection highlight is one shape that moves from card to card.
    @Namespace private var selectionNamespace

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
            thumbnail: model.itemThumbnail(for: cell.id),
            showAppName: model.appearance.showAppName,
            isPinned: model.isPinned(cell.ranked.item),
            quickSelectLabel: model.quickSelectLabel(forIndex: index),
            selectionNamespace: selectionNamespace,
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
    /// The selection highlight is one shape that moves from row to row.
    @Namespace private var selectionNamespace

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
            thumbnail: model.itemThumbnail(for: cell.id),
            showsThumbnail: model.listShowsThumbnails,
            rowHeight: model.layout.itemSize.height,
            showAppName: model.appearance.showAppName,
            isPinned: model.isPinned(cell.ranked.item),
            quickSelectLabel: model.quickSelectLabel(forIndex: index),
            selectionNamespace: selectionNamespace,
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
