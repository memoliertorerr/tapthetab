import SwiftUI

/// Builds a `Text` where the characters at `indices` (character offsets, as produced by
/// `FuzzyMatcher`) are bold and accent-coloured.
enum HighlightedText {
    static func make(_ string: String, indices: [Int], baseColor: Color? = nil) -> Text {
        if indices.isEmpty {
            return piece(string, isMatch: false, baseColor: baseColor)
        }
        let marks = Set(indices)
        var result: Text = Text(verbatim: "")
        var run: String = ""
        var runIsMatch = false
        for (offset, character) in string.enumerated() {
            let isMatch = marks.contains(offset)
            if isMatch != runIsMatch && !run.isEmpty {
                result = result + piece(run, isMatch: runIsMatch, baseColor: baseColor)
                run = ""
            }
            runIsMatch = isMatch
            run.append(character)
        }
        if !run.isEmpty {
            result = result + piece(run, isMatch: runIsMatch, baseColor: baseColor)
        }
        return result
    }

    private static func piece(_ string: String, isMatch: Bool, baseColor: Color?) -> Text {
        let text = Text(verbatim: string)
        if isMatch {
            return text.fontWeight(.bold).foregroundColor(Color.accentColor)
        }
        if let baseColor {
            return text.foregroundColor(baseColor)
        }
        return text
    }
}
