import AppKit
import SwiftUI
import TapTheTabCore

// MARK: - Content

/// One key cap in the tour: the text drawn on it and how VoiceOver says it.
struct TourKey: Equatable {
    /// Drawn on the cap (symbols such as ⌥ or ⇧, a letter, or a short localized word).
    let symbol: String
    /// What VoiceOver reads for the key ("Option", "W").
    let spoken: String

    static func letter(_ letter: String) -> TourKey { TourKey(symbol: letter, spoken: letter) }

    static var shift: TourKey { TourKey(symbol: "⇧", spoken: L10n.tr("Shift")) }
    static var tab: TourKey { TourKey(symbol: "⇥", spoken: L10n.tr("Tab")) }
    static var space: TourKey { TourKey(symbol: L10n.tr("Space"), spoken: L10n.tr("Space")) }
    static var returnKey: TourKey { TourKey(symbol: "↩", spoken: L10n.tr("Return")) }
    static var escape: TourKey { TourKey(symbol: "⎋", spoken: L10n.tr("Escape")) }
    static var digits: TourKey { TourKey(symbol: "1–9", spoken: "1–9") }

    /// A modifier by its symbol (⌥ ⌘ ⌃ ⇧); anything else is shown and read as it is.
    static func modifier(_ symbol: String) -> TourKey {
        switch symbol {
        case "⌥": return TourKey(symbol: symbol, spoken: L10n.tr("Option"))
        case "⌘": return TourKey(symbol: symbol, spoken: L10n.tr("Command"))
        case "⌃": return TourKey(symbol: symbol, spoken: L10n.tr("Control"))
        case "⇧": return shift
        default: return TourKey(symbol: symbol, spoken: symbol)
        }
    }
}

/// A line of a tour page: keys (or an SF Symbol) and what they do.
struct TourRow: Equatable {
    var keys: [TourKey] = []
    /// Shown instead of key caps when there is no key to press.
    var systemImage: String?
    let text: String

    /// The whole line for VoiceOver, e.g. "Shift W, Close the window".
    var spokenDescription: String {
        let spokenKeys = keys.map(\.spoken).joined(separator: " ")
        return spokenKeys.isEmpty ? text : "\(spokenKeys), \(text)"
    }
}

struct TourPage: Equatable {
    let systemImage: String
    let title: String
    let intro: String
    let rows: [TourRow]

    /// The tour. `modifier` is the symbol of the user's trigger modifier (⌥ by default);
    /// quick select uses ⌘, or ⌃ when the shortcut itself uses ⌘.
    static func pages(modifier: String) -> [TourPage] {
        let trigger = TourKey.modifier(modifier)
        let quickSelect = TourKey.modifier(modifier == "⌘" ? "⌃" : "⌘")
        return [
            TourPage(
                systemImage: "keyboard",
                title: L10n.tr("Hold, tap, release"),
                intro: L10n.tr("TapTheTab shows every window at once, so you can jump to any of them without the mouse."),
                rows: [
                    TourRow(keys: [trigger, .tab], text: L10n.tr("Hold the first key and press the second to open the switcher")),
                    TourRow(keys: [.tab], text: L10n.tr("Keep pressing to move to the next window")),
                    TourRow(keys: [.shift, .tab], text: L10n.tr("Move to the previous window")),
                    TourRow(keys: [trigger], text: L10n.tr("Let go of the first key to switch to the selected window")),
                ]
            ),
            TourPage(
                systemImage: "magnifyingglass",
                title: L10n.tr("Type to search"),
                intro: L10n.tr("With the switcher open, just start typing. Window titles and app names are matched as you type."),
                rows: [
                    TourRow(keys: [.returnKey], text: L10n.tr("Switch to the selected window")),
                    TourRow(keys: [.escape], text: L10n.tr("Clear the search; press again to close")),
                    TourRow(keys: [.space], text: L10n.tr("Keep the switcher open after you let go (when the search is empty)")),
                ]
            ),
            TourPage(
                systemImage: "macwindow",
                title: L10n.tr("Act on windows"),
                intro: L10n.tr("Hold Shift and press a letter to act on the selected window without leaving the switcher."),
                rows: [
                    TourRow(keys: [.shift, .letter("W")], text: L10n.tr("Close the window")),
                    TourRow(keys: [.shift, .letter("M")], text: L10n.tr("Minimize or restore the window")),
                    TourRow(keys: [.shift, .letter("F")], text: L10n.tr("Toggle fullscreen")),
                    TourRow(keys: [.shift, .letter("H")], text: L10n.tr("Hide or show the app")),
                    TourRow(keys: [.shift, .letter("Q")], text: L10n.tr("Quit the app")),
                    TourRow(keys: [.shift, .letter("X")], text: L10n.tr("Close all of the app's windows")),
                ]
            ),
            TourPage(
                systemImage: "command",
                title: L10n.tr("More shortcuts"),
                intro: L10n.tr("A few more things you can do while the switcher is open."),
                rows: [
                    TourRow(keys: [.shift, .letter("P")], text: L10n.tr("Pin or unpin the app; pinned apps come first")),
                    TourRow(keys: [.shift, .letter("D")], text: L10n.tr("Move the window to the next display")),
                    TourRow(keys: [quickSelect, .digits], text: L10n.tr("Switch straight to that window")),
                    TourRow(keys: [.shift, .space], text: L10n.tr("Peek at the window full size where it is (needs Screen Recording)")),
                ]
            ),
            TourPage(
                systemImage: "hand.draw",
                title: L10n.tr("Make it yours"),
                intro: L10n.tr("You are all set. Two last things."),
                rows: [
                    TourRow(systemImage: "hand.draw", text: L10n.tr("While the switcher is open, drag the list or the large preview to move it. TapTheTab remembers where.")),
                    TourRow(systemImage: "menubar.rectangle", text: L10n.tr("Open Settings from the menu bar icon to change shortcuts, looks and filters. You can show this tour again from there.")),
                ]
            ),
        ]
    }
}

// MARK: - Model

@MainActor
final class TourViewModel: ObservableObject {
    let pages: [TourPage]
    let theme: ColorTheme
    @Published private(set) var index = 0
    var onFinish: (() -> Void)?

    init(modifier: String, theme: ColorTheme) {
        self.pages = TourPage.pages(modifier: modifier)
        self.theme = theme
    }

    var page: TourPage { pages[index] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index >= pages.count - 1 }

    func next() { if !isLast { index += 1 } }
    func back() { if !isFirst { index -= 1 } }
    func finish() { onFinish?() }
}

// MARK: - Views

/// A key cap: a rounded, slightly raised label.
struct TourKeyCap: View {
    let key: TourKey

    var body: some View {
        Text(verbatim: key.symbol)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundColor(Color.primary)
            .padding(.horizontal, 7)
            .frame(minWidth: 30, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.primary.opacity(0.18), radius: 0, x: 0, y: 1.5)
            .accessibilityHidden(true)
    }
}

struct TourRowView: View {
    let row: TourRow

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let systemImage = row.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20))
                        .foregroundColor(Color.accentColor)
                        .frame(width: 30, height: 28)
                } else {
                    HStack(spacing: 5) {
                        ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in
                            TourKeyCap(key: key)
                        }
                    }
                }
            }
            .frame(width: 128, alignment: .leading)

            Text(verbatim: row.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenDescription)
    }
}

struct TourView: View {
    @ObservedObject var model: TourViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(nsColor: NSColor.windowBackgroundColor)
            ThemeBackground(theme: model.theme, cornerRadius: 0)

            VStack(alignment: .leading, spacing: 18) {
                pageContent
                    .id(model.index)
                    .transition(reduceMotion ? .identity : .opacity)
                Spacer(minLength: 0)
                footer
            }
            .padding(28)
        }
        .frame(width: 560, height: 470)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.index)
    }

    private var pageContent: some View {
        let page = model.page
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                Text(verbatim: page.title)
                    .font(.title.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            Text(verbatim: page.intro)
                .foregroundColor(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(page.rows.enumerated()), id: \.offset) { _, row in
                    TourRowView(row: row)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isLast {
                // Keeps the dots centered; the last page has nothing to skip.
                Color.clear.frame(width: 120, height: 1)
            } else {
                Button(L10n.tr("Skip tour")) { model.finish() }
                    .buttonStyle(.link)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 120, alignment: .leading)
            }
            Spacer()
            dots
            Spacer()
            Button(L10n.tr("Back")) { model.back() }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(model.isFirst)
            if model.isLast {
                Button(L10n.tr("Done")) { model.finish() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L10n.tr("Next")) { model.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<model.pages.count, id: \.self) { page in
                Circle()
                    .fill(page == model.index ? Color.accentColor : Color.primary.opacity(0.2))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("Step %lld of %lld", model.index + 1, model.pages.count))
    }
}
