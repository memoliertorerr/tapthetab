import Foundation

/// Looks up user-facing text in `Localizable.strings` of the app bundle.
///
/// Keys are the English sentences themselves, so a missing table (`swift run`, where
/// `Bundle.main` has no `.lproj` folders) or a missing key still shows correct English.
/// Only UI text goes through here — never window titles, app names or other user data.
/// `scripts/check-strings.py` checks that every `L10n.tr("…")` key exists in `en.lproj`.
enum L10n {
    /// The localized text for `key`; with `args`, `key` is a format string (`%@`, `%lld`).
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let localized = NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
        guard !args.isEmpty else { return localized }
        return String(format: localized, arguments: args)
    }
}
