import XCTest
@testable import TapTheTabCore

final class FuzzyMatcherTests: XCTestCase {
    private func match(_ query: String, app: String = "App", title: String = "") -> FuzzyMatch? {
        FuzzyMatcher.match(query, item: window(1, app: app, title: title))
    }

    // MARK: - Empty queries

    func testEmptyQueryMatchesWithZeroScore() {
        XCTAssertEqual(match("", title: "Anything"), FuzzyMatch(score: 0))
    }

    func testWhitespaceOnlyQueryMatchesWithZeroScore() {
        XCTAssertEqual(match("  \t ", title: "Anything"), FuzzyMatch(score: 0))
    }

    // MARK: - Folding

    func testCaseInsensitive() {
        XCTAssertNotNil(match("README", title: "readme.md"))
        XCTAssertNotNil(match("readme", title: "README.md"))
    }

    func testDiacriticInsensitiveQueryWithoutAccent() {
        let m = match("cafe", title: "Café Menu")
        XCTAssertNotNil(m)
        XCTAssertEqual(m.map { characters(of: "Café Menu", at: $0.titleIndices) }, "Café")
    }

    func testDiacriticInsensitiveQueryWithAccent() {
        XCTAssertNotNil(match("café", title: "Cafe Menu"))
        XCTAssertNotNil(match("ÜBER", title: "uber eats"))
    }

    // MARK: - Non-matches

    func testNonMatchReturnsNil() {
        XCTAssertNil(match("xyz", app: "Safari", title: "Apple"))
    }

    func testTokenLongerThanBothFieldsReturnsNil() {
        XCTAssertNil(match("safarisafari", app: "Safari", title: "Safari"))
    }

    func testOutOfOrderCharactersDoNotMatch() {
        XCTAssertNil(match("cba", app: "X", title: "abc"))
    }

    func testEveryTokenMustMatch() {
        XCTAssertNil(match("chrome zebra", app: "Google Chrome", title: "GitHub"))
    }

    // MARK: - Multi-token

    func testTokensCanHitDifferentFields() throws {
        let m = try XCTUnwrap(match("chrome github", app: "Google Chrome", title: "GitHub - Pull requests"))
        XCTAssertEqual(characters(of: "Google Chrome", at: m.appNameIndices), "Chrome")
        XCTAssertEqual(characters(of: "GitHub - Pull requests", at: m.titleIndices), "GitHub")
    }

    func testTokenOrderDoesNotMatter() {
        let a = match("chrome github", app: "Google Chrome", title: "GitHub")
        let b = match("github chrome", app: "Google Chrome", title: "GitHub")
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
    }

    func testRepeatedWhitespaceBetweenTokensIsIgnored() {
        XCTAssertEqual(
            match("chrome    github", app: "Google Chrome", title: "GitHub"),
            match("chrome github", app: "Google Chrome", title: "GitHub")
        )
    }

    // MARK: - Ranking

    func testContiguousBeatsScattered() throws {
        let contiguous = try XCTUnwrap(match("note", title: "notes"))
        let scattered = try XCTUnwrap(match("note", title: "nxoxtxe"))
        XCTAssertGreaterThan(contiguous.score, scattered.score)
    }

    func testWordStartBeatsMidWord() throws {
        let wordStart = try XCTUnwrap(match("port", title: "my port"))
        let midWord = try XCTUnwrap(match("port", title: "my report"))
        XCTAssertGreaterThan(wordStart.score, midWord.score)
    }

    func testPrefixBeatsLaterWordStart() throws {
        let prefix = try XCTUnwrap(match("mail", title: "mail box"))
        let later = try XCTUnwrap(match("mail", title: "box mail"))
        XCTAssertGreaterThan(prefix.score, later.score)
    }

    func testBestOccurrenceIsChosen() throws {
        // "log" appears mid-word in "blog" and at a word start in "Log".
        let m = try XCTUnwrap(match("log", title: "blog - Log in"))
        XCTAssertEqual(m.titleIndices, [7, 8, 9])
    }

    func testCamelCaseCountsAsWordStart() throws {
        let camel = try XCTUnwrap(match("view", title: "MainViewController"))
        let plain = try XCTUnwrap(match("view", title: "Mainviewcontroller"))
        XCTAssertGreaterThan(camel.score, plain.score)
    }

    func testSubsequencePrefersWordStarts() throws {
        // "gp" should highlight the initials of "Git Pull" rather than any earlier "p".
        let m = try XCTUnwrap(match("gp", title: "Git Pull"))
        XCTAssertEqual(m.titleIndices, [0, 4])
    }

    func testSubsequenceDoesNotJumpPastTheOnlyRemainingMatch() throws {
        // "b" at index 1 is mid-word, "b" at index 5 is a word start, but jumping to it
        // would leave no "a" for the next character. The token is still a subsequence.
        let m = try XCTUnwrap(match("ba", title: "xbya b"))
        XCTAssertEqual(m.titleIndices, [1, 3])
    }

    func testAppNameBonus() throws {
        let inApp = try XCTUnwrap(match("saf", app: "Safari", title: "Untitled"))
        let inTitle = try XCTUnwrap(match("saf", app: "Untitled", title: "Safari"))
        XCTAssertGreaterThan(inApp.score, inTitle.score)
        XCTAssertEqual(inApp.appNameIndices, [0, 1, 2])
        XCTAssertEqual(inApp.titleIndices, [])
        XCTAssertEqual(inTitle.titleIndices, [0, 1, 2])
        XCTAssertEqual(inTitle.appNameIndices, [])
    }

    func testShorterTitleWinsTie() throws {
        let short = try XCTUnwrap(match("doc", title: "doc"))
        let long = try XCTUnwrap(match("doc", title: "doc " + String(repeating: "z", count: 60)))
        XCTAssertGreaterThan(short.score, long.score)
    }

    func testLongerContiguousMatchScoresHigher() throws {
        let three = try XCTUnwrap(match("ter", title: "terminal"))
        let five = try XCTUnwrap(match("termi", title: "terminal"))
        XCTAssertGreaterThan(five.score, three.score)
    }

    // MARK: - Highlight indices

    func testIndicesPointAtMatchedCharactersInTitle() throws {
        let title = "Inbox — Mail"
        let m = try XCTUnwrap(match("inbox", app: "Mail", title: title))
        XCTAssertEqual(characters(of: title, at: m.titleIndices), "Inbox")
    }

    func testScatteredIndicesPointAtMatchedCharacters() throws {
        let title = "Activity Monitor"
        let m = try XCTUnwrap(match("acmo", app: "X", title: title))
        XCTAssertEqual(characters(of: title, at: m.titleIndices).lowercased(), "acmo")
        XCTAssertEqual(m.titleIndices, m.titleIndices.sorted())
    }

    func testIndicesCountGraphemesNotScalars() throws {
        // "👩‍👩‍👧" is one Character made of several scalars; indices must count Characters.
        let title = "👩‍👩‍👧 family photos"
        let m = try XCTUnwrap(match("photos", app: "X", title: title))
        XCTAssertEqual(m.titleIndices, Array(9...14))
        XCTAssertEqual(characters(of: title, at: m.titleIndices), "photos")
    }

    func testIndicesAreRelativeToTrimmedDisplayTitle() throws {
        let item = window(1, app: "X", title: "   Notes")
        let m = try XCTUnwrap(FuzzyMatcher.match("notes", item: item))
        XCTAssertEqual(item.displayTitle, "Notes")
        XCTAssertEqual(characters(of: item.displayTitle, at: m.titleIndices), "Notes")
    }

    func testUntitledWindowHighlightsDisplayTitleFallback() throws {
        // With no title, displayTitle is the app name; the main label must still highlight.
        let item = window(1, app: "Finder", title: "")
        XCTAssertEqual(item.displayTitle, "Finder")
        let m = try XCTUnwrap(FuzzyMatcher.match("fin", item: item))
        XCTAssertEqual(characters(of: item.displayTitle, at: m.titleIndices), "Fin")
        XCTAssertEqual(characters(of: item.appName, at: m.appNameIndices), "Fin")
    }

    func testWindowlessAppMatchesByName() throws {
        let item = windowlessApp(pid: 3, app: "Calculator")
        let m = try XCTUnwrap(FuzzyMatcher.match("calc", item: item))
        XCTAssertEqual(characters(of: item.displayTitle, at: m.titleIndices), "Calc")
    }

    func testTokenHittingBothFieldsHighlightsBoth() throws {
        let title = "Slack — general"
        let m = try XCTUnwrap(match("slack", app: "Slack", title: title))
        XCTAssertEqual(characters(of: "Slack", at: m.appNameIndices), "Slack")
        XCTAssertEqual(characters(of: title, at: m.titleIndices), "Slack")
        // Scoring is unchanged: only the better field (the app name, +8 bonus) counts.
        let appOnly = try XCTUnwrap(match("slack", app: "Slack", title: "Inbox — general"))
        XCTAssertEqual(m.score, appOnly.score)
    }

    func testTitleWinsAndAppNameIsHighlightedToo() throws {
        let m = try XCTUnwrap(match("notes", app: "Sticky Notes", title: "Notes"))
        XCTAssertEqual(characters(of: "Notes", at: m.titleIndices), "Notes")
        XCTAssertEqual(characters(of: "Sticky Notes", at: m.appNameIndices), "Notes")
    }

    func testScatteredHitInLosingFieldIsNotHighlighted() throws {
        // "mail" is a scattered subsequence of the title; highlighting it would be noise.
        let m = try XCTUnwrap(match("mail", app: "Mail", title: "my alpha in lab"))
        XCTAssertEqual(m.appNameIndices, [0, 1, 2, 3])
        XCTAssertEqual(m.titleIndices, [])
    }

    func testBothFieldsHighlightedPerTokenWithMultipleTokens() throws {
        let title = "Slack huddle — design"
        let m = try XCTUnwrap(match("slack design", app: "Slack", title: title))
        XCTAssertEqual(characters(of: "Slack", at: m.appNameIndices), "Slack")
        XCTAssertEqual(characters(of: title, at: m.titleIndices), "Slackdesign")
    }

    func testIsContiguous() {
        XCTAssertTrue(FuzzyMatcher.isContiguous([3]))
        XCTAssertTrue(FuzzyMatcher.isContiguous([3, 4, 5]))
        XCTAssertFalse(FuzzyMatcher.isContiguous([3, 5]))
        XCTAssertFalse(FuzzyMatcher.isContiguous([]))
    }

    func testIndicesAreUniqueWhenTokensOverlap() throws {
        let m = try XCTUnwrap(match("git github", app: "X", title: "GitHub"))
        XCTAssertEqual(m.titleIndices, Array(Set(m.titleIndices)).sorted())
    }

    // MARK: - Helpers

    func testWordStartRules() {
        let chars = Array("foo-barBaz 9x")
        XCTAssertTrue(FuzzyMatcher.isWordStart(chars, at: 0))
        XCTAssertFalse(FuzzyMatcher.isWordStart(chars, at: 1))
        XCTAssertTrue(FuzzyMatcher.isWordStart(chars, at: 4))   // after "-"
        XCTAssertTrue(FuzzyMatcher.isWordStart(chars, at: 7))   // camelCase "B"
        XCTAssertTrue(FuzzyMatcher.isWordStart(chars, at: 11))  // after space
    }

    func testFoldKeepsOneCharacterPerCharacter() {
        let input = "Ça Été ÅNGSTRÖM"
        XCTAssertEqual(FuzzyMatcher.fold(input).count, input.count)
        XCTAssertEqual(String(FuzzyMatcher.fold(input)), "ca ete angstrom")
    }
}
