import Foundation

/// Modifier keys, independent of AppKit so the core stays portable.
public struct ModifierFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = ModifierFlags(rawValue: 1 << 0)
    public static let option = ModifierFlags(rawValue: 1 << 1)
    public static let shift = ModifierFlags(rawValue: 1 << 2)
    public static let command = ModifierFlags(rawValue: 1 << 3)
    public static let function = ModifierFlags(rawValue: 1 << 4)

    /// Apple's canonical display order: ⌃ ⌥ ⇧ ⌘.
    static let ordered: [(flag: ModifierFlags, name: String, symbol: String)] = [
        (.control, "control", "⌃"),
        (.option, "option", "⌥"),
        (.shift, "shift", "⇧"),
        (.command, "command", "⌘"),
        (.function, "fn", "fn"),
    ]

    static let aliases: [String: ModifierFlags] = [
        "control": .control, "ctrl": .control, "⌃": .control,
        "option": .option, "opt": .option, "alt": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
        "command": .command, "cmd": .command, "⌘": .command,
        "fn": .function, "function": .function,
    ]

    public var symbols: String {
        Self.ordered.filter { contains($0.flag) }.map(\.symbol).joined()
    }

    public var names: [String] {
        Self.ordered.filter { contains($0.flag) }.map(\.name)
    }
}

/// A key plus modifiers, e.g. ⌥⇥. Stored in config files as a readable string
/// such as `"option+tab"`.
public struct Shortcut: Hashable, Sendable, Codable, CustomStringConvertible {
    public var keyCode: UInt16
    public var modifiers: ModifierFlags

    public init(keyCode: UInt16, modifiers: ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let optionTab = Shortcut(keyCode: KeyCode.tab, modifiers: .option)
    public static let commandTab = Shortcut(keyCode: KeyCode.tab, modifiers: .command)
    public static let controlTab = Shortcut(keyCode: KeyCode.tab, modifiers: .control)
    public static let optionGrave = Shortcut(keyCode: KeyCode.grave, modifiers: .option)
    public static let commandGrave = Shortcut(keyCode: KeyCode.grave, modifiers: .command)

    /// Parses strings like `"option+tab"` or `"cmd + shift + grave"`. Parts are separated
    /// by `+`; the last part is the key. Returns nil for unknown keys or modifiers.
    public init?(string: String) {
        let parts = string
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        // A trailing "+" means the key itself is "+" which we do not support; reject.
        guard let keyName = parts.last, !keyName.isEmpty else { return nil }
        var mods: ModifierFlags = []
        for part in parts.dropLast() {
            guard let flag = ModifierFlags.aliases[part] else { return nil }
            mods.insert(flag)
        }
        guard let code = KeyCode.code(forName: keyName) else { return nil }
        self.init(keyCode: code, modifiers: mods)
    }

    /// Canonical config representation, e.g. `"option+tab"`.
    public var stringValue: String {
        (modifiers.names + [KeyCode.name(for: keyCode)]).joined(separator: "+")
    }

    /// Human-facing label, e.g. `⌥⇥`.
    public var displayString: String {
        modifiers.symbols + KeyCode.symbol(for: keyCode)
    }

    public var description: String { displayString }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = Shortcut(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown shortcut \"\(raw)\"")
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

/// macOS virtual key codes (Carbon `kVK_*` values, ANSI layout positions).
public enum KeyCode {
    public static let a: UInt16 = 0x00
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    public static let grave: UInt16 = 0x32
    public static let delete: UInt16 = 0x33
    public static let escape: UInt16 = 0x35
    public static let returnKey: UInt16 = 0x24
    public static let keypadEnter: UInt16 = 0x4C
    public static let forwardDelete: UInt16 = 0x75
    public static let leftArrow: UInt16 = 0x7B
    public static let rightArrow: UInt16 = 0x7C
    public static let downArrow: UInt16 = 0x7D
    public static let upArrow: UInt16 = 0x7E
    public static let home: UInt16 = 0x73
    public static let end: UInt16 = 0x77
    public static let pageUp: UInt16 = 0x74
    public static let pageDown: UInt16 = 0x79

    static let table: [(name: String, code: UInt16, symbol: String)] = [
        ("a", 0x00, "A"), ("s", 0x01, "S"), ("d", 0x02, "D"), ("f", 0x03, "F"),
        ("h", 0x04, "H"), ("g", 0x05, "G"), ("z", 0x06, "Z"), ("x", 0x07, "X"),
        ("c", 0x08, "C"), ("v", 0x09, "V"), ("b", 0x0B, "B"), ("q", 0x0C, "Q"),
        ("w", 0x0D, "W"), ("e", 0x0E, "E"), ("r", 0x0F, "R"), ("y", 0x10, "Y"),
        ("t", 0x11, "T"), ("1", 0x12, "1"), ("2", 0x13, "2"), ("3", 0x14, "3"),
        ("4", 0x15, "4"), ("6", 0x16, "6"), ("5", 0x17, "5"), ("=", 0x18, "="),
        ("9", 0x19, "9"), ("7", 0x1A, "7"), ("-", 0x1B, "-"), ("8", 0x1C, "8"),
        ("0", 0x1D, "0"), ("]", 0x1E, "]"), ("o", 0x1F, "O"), ("u", 0x20, "U"),
        ("[", 0x21, "["), ("i", 0x22, "I"), ("p", 0x23, "P"), ("return", 0x24, "↩"),
        ("l", 0x25, "L"), ("j", 0x26, "J"), ("'", 0x27, "'"), ("k", 0x28, "K"),
        (";", 0x29, ";"), ("\\", 0x2A, "\\"), (",", 0x2B, ","), ("/", 0x2C, "/"),
        ("n", 0x2D, "N"), ("m", 0x2E, "M"), (".", 0x2F, "."), ("tab", 0x30, "⇥"),
        ("space", 0x31, "Space"), ("`", 0x32, "`"), ("delete", 0x33, "⌫"),
        ("escape", 0x35, "⎋"), ("f5", 0x60, "F5"), ("f6", 0x61, "F6"),
        ("f7", 0x62, "F7"), ("f3", 0x63, "F3"), ("f8", 0x64, "F8"), ("f9", 0x65, "F9"),
        ("f11", 0x67, "F11"), ("f13", 0x69, "F13"), ("f14", 0x6B, "F14"),
        ("f10", 0x6D, "F10"), ("f12", 0x6F, "F12"), ("f15", 0x71, "F15"),
        ("home", 0x73, "↖"), ("pageup", 0x74, "⇞"), ("forwarddelete", 0x75, "⌦"),
        ("f4", 0x76, "F4"), ("end", 0x77, "↘"), ("f2", 0x78, "F2"),
        ("pagedown", 0x79, "⇟"), ("f1", 0x7A, "F1"), ("left", 0x7B, "←"),
        ("right", 0x7C, "→"), ("down", 0x7D, "↓"), ("up", 0x7E, "↑"),
    ]

    static let aliases: [String: String] = [
        "grave": "`", "backtick": "`", "esc": "escape", "enter": "return",
        "backspace": "delete", "del": "forwarddelete", "⇥": "tab", "↩": "return",
        "⎋": "escape", "⌫": "delete", "spacebar": "space",
        "leftarrow": "left", "rightarrow": "right", "uparrow": "up", "downarrow": "down",
    ]

    public static func code(forName name: String) -> UInt16? {
        let key = name.lowercased()
        let canonical = aliases[key] ?? key
        if let code = table.first(where: { $0.name == canonical })?.code { return code }
        // Round-trips the "keyNN" fallback produced by name(for:).
        if canonical.hasPrefix("key"), let n = UInt16(canonical.dropFirst(3)) { return n }
        return nil
    }

    public static func name(for code: UInt16) -> String {
        table.first { $0.code == code }?.name ?? "key\(code)"
    }

    public static func symbol(for code: UInt16) -> String {
        table.first { $0.code == code }?.symbol ?? "#\(code)"
    }
}
