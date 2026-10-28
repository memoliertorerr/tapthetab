import Foundation

/// Result of matching a query against one switcher item.
public struct FuzzyMatch: Equatable, Sendable {
    /// Higher is better.
    public var score: Int
    /// Character offsets in `SwitcherItem.displayTitle` that matched, for highlighting.
    public var titleIndices: [Int]
    /// Character offsets in `SwitcherItem.appName` that matched, for highlighting.
    public var appNameIndices: [Int]

    public init(score: Int, titleIndices: [Int] = [], appNameIndices: [Int] = []) {
        self.score = score
        self.titleIndices = titleIndices
        self.appNameIndices = appNameIndices
    }
}

/// Small, dependency-free fuzzy matcher tuned for window titles and app names.
///
/// - Matching is case- and diacritic-insensitive.
/// - The query is split on whitespace; every token must match the title or the app name.
/// - Contiguous matches beat scattered ones; matches at word starts beat matches mid-word.
public enum FuzzyMatcher {
    /// Match `query` against an item. Returns nil when any token fails to match.
    public static func match(_ query: String, item: SwitcherItem) -> FuzzyMatch? {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { fold(String($0)) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return FuzzyMatch(score: 0) }

        let title = Array(item.displayTitle)
        let appName = Array(item.appName)
        let foldedTitle = title.map(foldCharacter)
        let foldedApp = appName.map(foldCharacter)

        var total = 0
        var titleHits = Set<Int>()
        var appHits = Set<Int>()

        for token in tokens {
            let inTitle = score(token: token, folded: foldedTitle, original: title)
            // App-name hits get a small bonus: typing "saf" usually means Safari.
            let inApp = score(token: token, folded: foldedApp, original: appName).map {
                (score: $0.score + 8, indices: $0.indices)
            }
            switch (inTitle, inApp) {
            case (nil, nil):
                return nil
            case let (t?, nil):
                total += t.score
                titleHits.formUnion(t.indices)
            case let (nil, a?):
                total += a.score
                appHits.formUnion(a.indices)
            case let (t?, a?):
                if a.score > t.score {
                    total += a.score
                    appHits.formUnion(a.indices)
                } else {
                    total += t.score
                    titleHits.formUnion(t.indices)
                }
            }
        }
        // An untitled window shows the app name as its title (see `displayTitle`), so the
        // two labels are the same text and every hit belongs highlighted on both.
        if title == appName {
            let all = titleHits.union(appHits)
            titleHits = all
            appHits = all
        }
        // Shorter titles are slightly preferred when everything else is equal.
        total -= min(title.count, 120) / 12
        return FuzzyMatch(score: total, titleIndices: titleHits.sorted(), appNameIndices: appHits.sorted())
    }

    /// Score one token against one field. Exposed for tests.
    static func score(token: [Character], folded: [Character], original: [Character]) -> (score: Int, indices: [Int])? {
        guard !token.isEmpty, token.count <= folded.count else { return nil }

        // 1. Contiguous substring: pick the best-scoring occurrence.
        var best: (score: Int, indices: [Int])?
        var start = 0
        while start + token.count <= folded.count {
            if Array(folded[start..<(start + token.count)]) == token {
                var s = 100 + token.count * 12
                if start == 0 { s += 30 }
                if isWordStart(original, at: start) { s += 25 }
                if start + token.count == folded.count || !isWordContinuation(original, at: start + token.count) {
                    s += 10 // whole-word or word-prefix-to-end match
                }
                if best == nil || s > best!.score {
                    best = (s, Array(start..<(start + token.count)))
                }
            }
            start += 1
        }
        if let best { return best }

        // 2. Subsequence: greedy, but jump to a word start when one is available ahead.
        var indices: [Int] = []
        indices.reserveCapacity(token.count)
        var cursor = 0
        for (k, ch) in token.enumerated() {
            var found: Int?
            var firstPlain: Int?
            var i = cursor
            while i < folded.count {
                if folded[i] == ch {
                    if isWordStart(original, at: i) { found = i; break }
                    if firstPlain == nil { firstPlain = i }
                }
                i += 1
            }
            // Prefer the plain hit when it is directly adjacent to the previous match.
            if let plain = firstPlain, let last = indices.last, plain == last + 1 {
                found = plain
            }
            // Never jump to a later word start if that leaves the rest of the token unmatchable;
            // the earliest hit always keeps every remaining character reachable.
            if let jump = found, let plain = firstPlain, plain < jump,
               !isSubsequence(token[(k + 1)...], of: folded, from: jump + 1) {
                found = plain
            }
            guard let hit = found ?? firstPlain else { return nil }
            indices.append(hit)
            cursor = hit + 1
        }

        var s = 0
        for (n, idx) in indices.enumerated() {
            s += 10
            if isWordStart(original, at: idx) { s += 18 }
            if n > 0 {
                let gap = idx - indices[n - 1] - 1
                if gap == 0 { s += 14 } else { s -= min(gap, 10) }
            } else if idx == 0 {
                s += 15
            }
        }
        return (max(s, 1), indices)
    }

    static func isSubsequence(_ needle: ArraySlice<Character>, of haystack: [Character], from start: Int) -> Bool {
        var i = start
        for ch in needle {
            while i < haystack.count && haystack[i] != ch { i += 1 }
            guard i < haystack.count else { return false }
            i += 1
        }
        return true
    }

    static func isWordStart(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = chars[index - 1]
        let cur = chars[index]
        if prev.isWhitespace || "-_./\\:|()[]{}—–·,".contains(prev) { return true }
        if prev.isLowercase && cur.isUppercase { return true } // camelCase
        if !prev.isNumber && cur.isNumber { return true }
        return false
    }

    static func isWordContinuation(_ chars: [Character], at index: Int) -> Bool {
        guard index < chars.count else { return false }
        return chars[index].isLetter || chars[index].isNumber
    }

    static func fold(_ string: String) -> [Character] {
        Array(string).map(foldCharacter)
    }

    /// Folds one character for comparison while keeping a 1:1 mapping to the original
    /// characters, so match indices stay valid for highlighting.
    static func foldCharacter(_ ch: Character) -> Character {
        let folded = String(ch).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.lowercased().first ?? ch
    }
}
