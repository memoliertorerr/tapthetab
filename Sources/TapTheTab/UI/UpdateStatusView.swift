import AppKit
import SwiftUI
import TapTheTabCore

/// What the updater knows and what can be done about it: status, last check, release
/// notes and the install, Homebrew or release-page actions. Used in Settings → About and
/// in the Software Update window.
struct UpdateStatusView: View {
    @ObservedObject var updater: Updater
    /// The window also says whether automatic checks are on (Settings has the toggle).
    var showsScheduleNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusLine

            if let release = updater.availableRelease {
                UpdateNotesView(notes: release.notes)
                installActions(release)
            }

            HStack(spacing: 8) {
                Button(L10n.tr("Check Now")) {
                    updater.checkNow()
                }
                .disabled(updater.isChecking || updater.installPhase.isBusy)
                .accessibilityHint(Text(L10n.tr("Asks GitHub once for the latest version.")))
                if case .failed = updater.state {
                    Button(L10n.tr("Open Release Page")) {
                        updater.openReleasePage()
                    }
                    .accessibilityHint(Text(L10n.tr("Opens the releases page in your browser.")))
                }
            }

            if let lastCheck = updater.lastCheck {
                Text(L10n.tr("Last checked: %@", lastCheck.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
            if showsScheduleNote {
                Text(updater.automaticChecksEnabled
                     ? L10n.tr("TapTheTab checks automatically once a day.")
                     : L10n.tr("Automatic checks are off. You can turn them on in Settings → About."))
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch updater.state {
            case .idle:
                Text(L10n.tr("Installed version: %@", AppInfo.version))
            case .checking:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(L10n.tr("Checking for updates…"))
            case .upToDate:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.green)
                    .accessibilityHidden(true)
                Text(L10n.tr("TapTheTab %@ is up to date.", AppInfo.version))
            case .available(let release):
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(Color.accentColor)
                    .accessibilityHidden(true)
                Text(L10n.tr("TapTheTab %@ is available. You have %@.", release.version.description, AppInfo.version))
                    .fontWeight(.semibold)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color.orange)
                    .accessibilityHidden(true)
                Text(verbatim: message)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Install

    @ViewBuilder
    private func installActions(_ release: ReleaseInfo) -> some View {
        switch updater.installMethod {
        case .selfUpdate:
            selfUpdateActions(release)
        case .homebrew:
            homebrewActions
        case .manual(let reason):
            VStack(alignment: .leading, spacing: 6) {
                if !reason.isEmpty {
                    Text(verbatim: reason)
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                releasePageButton
            }
        }
    }

    @ViewBuilder
    private func selfUpdateActions(_ release: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if updater.installPhase.isBusy {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text(phaseText(release))
                }
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: 8) {
                    Button(L10n.tr("Install and Relaunch")) {
                        updater.installUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(Text(L10n.tr("Downloads the update, checks it, replaces TapTheTab and opens the new version.")))
                    releasePageButton
                }
                if case .failed(let message) = updater.installPhase {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(verbatim: message)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundColor(Color.red)
                    .accessibilityElement(children: .combine)
                }
                Text(L10n.tr("TapTheTab checks the download's checksum and Developer ID signature before it replaces itself."))
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var homebrewActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("TapTheTab was installed with Homebrew. Update it in Terminal:"))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(verbatim: UpdateInstaller.homebrewCommand)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(nsColor: NSColor.textBackgroundColor))
                    )
                Button(L10n.tr("Copy Command")) {
                    updater.copyHomebrewCommand()
                }
                .accessibilityHint(Text(L10n.tr("Copies the Homebrew command to the clipboard.")))
                if updater.commandCopied {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.green)
                            .accessibilityHidden(true)
                        Text(L10n.tr("Copied"))
                    }
                    .font(.caption)
                }
            }
            releasePageButton
        }
    }

    private var releasePageButton: some View {
        Button(L10n.tr("Open Release Page")) {
            updater.openReleasePage()
        }
        .accessibilityHint(Text(L10n.tr("Opens the releases page in your browser.")))
    }

    private func phaseText(_ release: ReleaseInfo) -> String {
        switch updater.installPhase {
        case .downloading:
            return L10n.tr("Downloading TapTheTab %@…", release.version.description)
        case .verifying:
            return L10n.tr("Verifying the update…")
        case .relaunching:
            return L10n.tr("Installing and relaunching…")
        case .idle, .failed:
            return ""
        }
    }
}

/// The release notes, shortened, as plain styled text: no links, no images.
struct UpdateNotesView: View {
    let notes: String

    private static let maximumCharacters = 1500

    var body: some View {
        let excerpt = Self.excerpt(notes)
        if !excerpt.characters.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("What's new"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.secondary)
                    .accessibilityAddTraits(.isHeader)
                ScrollView {
                    Text(excerpt)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 150)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: NSColor.textBackgroundColor).opacity(0.6))
                )
                .accessibilityLabel(Text(L10n.tr("Release notes")))
            }
        }
    }

    /// The changelog part of the notes (before the release's "### Install" section),
    /// headings in bold, bullets as "•", cut at a line end near `maximumCharacters`.
    /// Inline Markdown only; links are removed so the notes can't point anywhere.
    static func excerpt(_ notes: String) -> AttributedString {
        var lines: [String] = []
        var length = 0
        var truncated = false
        for rawLine in notes.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### Install") || line.hasPrefix("## Install") { break }
            var shown = line
            if line.hasPrefix("#") {
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                shown = title.isEmpty ? "" : "**\(title)**"
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                shown = "• " + line.dropFirst(2)
            }
            if shown.isEmpty, lines.last?.isEmpty ?? true { continue }
            if length + shown.count > maximumCharacters {
                truncated = true
                break
            }
            lines.append(shown)
            length += shown.count + 1
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        if truncated { lines.append("…") }
        let text = lines.joined(separator: "\n")

        var attributed = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        attributed.link = nil
        return attributed
    }
}
