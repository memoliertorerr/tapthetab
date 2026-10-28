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
        let escape = query.isEmpty ? "⎋ close" : "⎋ clear"
        return "⇧W close · ⇧M minimize · ⇧Q quit · " + escape
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
        } else if isLocked {
            Text("Locked open — ↩ to switch")
                .font(.system(size: fontSize))
                .foregroundColor(Color.secondary)
                .lineLimit(1)
        } else if searchEnabled {
            Text("Type to search windows")
                .font(.system(size: fontSize))
                .foregroundColor(Color.secondary)
                .lineLimit(1)
        } else {
            Text("Search is turned off in Settings")
                .font(.system(size: fontSize))
                .foregroundColor(Color.secondary)
                .lineLimit(1)
        }
    }
}

struct SwitcherEmptyView: View {
    let query: String

    private var message: String {
        query.isEmpty ? "No windows to show" : "No windows match “\(query)”"
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: query.isEmpty ? "macwindow" : "magnifyingglass")
                .font(.system(size: 22))
                .foregroundColor(Color.secondary)
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
        return VStack(spacing: 0) {
            ForEach(cells) { cell in
                row(for: cell)
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

enum SwitcherScrolling {
    @MainActor
    static func scrollToSelection(session: SwitcherSession, proxy: ScrollViewProxy) {
        guard let index = session.selectedIndex, session.visible.indices.contains(index) else { return }
        let id: ItemID = session.visible[index].id
        proxy.scrollTo(id, anchor: nil)
    }
}
