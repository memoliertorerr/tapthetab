import XCTest
@testable import TapTheTabCore

final class AutomationCommandTests: XCTestCase {
    private func parse(_ string: String) -> AutomationCommand? {
        guard let url = URL(string: string) else { return nil }
        return AutomationCommand(url: url)
    }

    private func switcher(_ scope: SwitcherScope = .allWindows, _ query: String? = nil) -> AutomationCommand {
        .showSwitcher(scope: scope, query: query)
    }

    // MARK: - Constants

    func testConstants() {
        XCTAssertEqual(AutomationCommand.scheme, "tapthetab")
        XCTAssertEqual(AutomationCommand.maximumQueryLength, 200)
    }

    // MARK: - Commands

    func testPlainSwitch() {
        XCTAssertEqual(parse("tapthetab://switch"), switcher())
    }

    func testSettings() {
        XCTAssertEqual(parse("tapthetab://settings"), .openSettings)
        XCTAssertEqual(parse("tapthetab://settings/"), .openSettings)
    }

    func testSettingsIgnoresParameters() {
        XCTAssertEqual(parse("tapthetab://settings?scope=bogus&query=x"), .openSettings)
    }

    func testTrailingSlash() {
        XCTAssertEqual(parse("tapthetab://switch/"), switcher())
    }

    func testPathForms() {
        XCTAssertEqual(parse("tapthetab:switch"), switcher())
        XCTAssertEqual(parse("tapthetab:///switch"), switcher())
        XCTAssertEqual(parse("tapthetab:settings"), .openSettings)
        XCTAssertEqual(parse("tapthetab:///settings"), .openSettings)
        XCTAssertEqual(parse("tapthetab:switch?scope=apps&query=mail"), switcher(.apps, "mail"))
        XCTAssertEqual(parse("tapthetab:///switch?query=mail"), switcher(.allWindows, "mail"))
    }

    func testSchemeAndCommandAreCaseInsensitive() {
        XCTAssertEqual(parse("TapTheTab://switch"), switcher())
        XCTAssertEqual(parse("TAPTHETAB://SWITCH"), switcher())
        XCTAssertEqual(parse("tapthetab://Settings"), .openSettings)
    }

    // MARK: - Scope

    func testEveryScope() {
        XCTAssertEqual(parse("tapthetab://switch?scope=allWindows"), switcher(.allWindows))
        XCTAssertEqual(parse("tapthetab://switch?scope=activeApp"), switcher(.activeApp))
        XCTAssertEqual(parse("tapthetab://switch?scope=apps"), switcher(.apps))
    }

    func testScopeValueIsCaseInsensitive() {
        XCTAssertEqual(parse("tapthetab://switch?scope=ACTIVEAPP"), switcher(.activeApp))
        XCTAssertEqual(parse("tapthetab://switch?scope=allwindows"), switcher(.allWindows))
    }

    func testUnknownScopeIsRejected() {
        XCTAssertNil(parse("tapthetab://switch?scope=everything"))
        XCTAssertNil(parse("tapthetab://switch?scope=all"))
        XCTAssertNil(parse("tapthetab://switch?scope=apps%20"))
        XCTAssertNil(parse("tapthetab://switch?scope=%00apps"))
    }

    func testEmptyScopeIsRejected() {
        XCTAssertNil(parse("tapthetab://switch?scope="))
        XCTAssertNil(parse("tapthetab://switch?scope"))
    }

    func testFirstScopeWins() {
        XCTAssertEqual(parse("tapthetab://switch?scope=apps&scope=activeApp"), switcher(.apps))
        XCTAssertNil(parse("tapthetab://switch?scope=nope&scope=apps"), "first scope is unknown")
        XCTAssertEqual(parse("tapthetab://switch?scope=apps&scope=nope"), switcher(.apps))
    }

    func testScopeParameterNameIsCaseSensitive() {
        XCTAssertEqual(parse("tapthetab://switch?Scope=apps"), switcher(), "unknown parameter, ignored")
    }

    // MARK: - Query

    func testQueryIsPercentDecoded() {
        XCTAssertEqual(parse("tapthetab://switch?query=hello%20world"), switcher(.allWindows, "hello world"))
        XCTAssertEqual(parse("tapthetab://switch?query=caf%C3%A9"), switcher(.allWindows, "café"))
        XCTAssertEqual(parse("tapthetab://switch?query=a%26b%3Dc"), switcher(.allWindows, "a&b=c"))
    }

    func testPlusIsLiteral() {
        XCTAssertEqual(parse("tapthetab://switch?query=c++"), switcher(.allWindows, "c++"))
    }

    func testScopeAndQueryTogetherInAnyOrder() {
        XCTAssertEqual(parse("tapthetab://switch?scope=activeApp&query=doc"), switcher(.activeApp, "doc"))
        XCTAssertEqual(parse("tapthetab://switch?query=doc&scope=activeApp"), switcher(.activeApp, "doc"))
    }

    func testFirstQueryWins() {
        XCTAssertEqual(parse("tapthetab://switch?query=one&query=two"), switcher(.allWindows, "one"))
    }

    func testFirstQueryWinsEvenWhenItSanitizesToNothing() {
        XCTAssertEqual(parse("tapthetab://switch?query=%20&query=two"), switcher())
    }

    func testEmptyQueryIsNil() {
        XCTAssertEqual(parse("tapthetab://switch?query="), switcher())
        XCTAssertEqual(parse("tapthetab://switch?query"), switcher())
        XCTAssertEqual(parse("tapthetab://switch?query=%20%20%09"), switcher())
    }

    func testQueryIsTrimmed() {
        XCTAssertEqual(parse("tapthetab://switch?query=%20%20mail%20%20"), switcher(.allWindows, "mail"))
    }

    func testUnknownParametersAreIgnored() {
        XCTAssertEqual(parse("tapthetab://switch?foo=bar&query=x&action=close"), switcher(.allWindows, "x"))
        XCTAssertEqual(parse("tapthetab://switch?&&=x&query=y"), switcher(.allWindows, "y"))
    }

    func testFragmentIsIgnored() {
        XCTAssertEqual(parse("tapthetab://switch?query=x#scope=apps"), switcher(.allWindows, "x"))
    }

    // MARK: - Hostile query text

    func testControlCharactersAreRemoved() {
        XCTAssertEqual(parse("tapthetab://switch?query=a%00b"), switcher(.allWindows, "ab"))
        XCTAssertEqual(parse("tapthetab://switch?query=a%0Ab%0Dc%09d"), switcher(.allWindows, "abcd"))
        XCTAssertEqual(parse("tapthetab://switch?query=a%7Fb%1Bc"), switcher(.allWindows, "abc"))
        XCTAssertEqual(parse("tapthetab://switch?query=a%C2%85b"), switcher(.allWindows, "ab"), "C1 NEL")
        XCTAssertEqual(parse("tapthetab://switch?query=a%E2%80%A8b%E2%80%A9c"), switcher(.allWindows, "abc"),
                       "line and paragraph separators")
    }

    func testOnlyControlCharactersIsNil() {
        XCTAssertEqual(parse("tapthetab://switch?query=%00%01%0A%7F"), switcher())
    }

    func testBidiOverridesAreRemoved() {
        // RLO + "fdp.exe" would render reversed.
        XCTAssertEqual(parse("tapthetab://switch?query=%E2%80%AEfdp.exe"), switcher(.allWindows, "fdp.exe"))
        for scalar in [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0x200E, 0x200F, 0x061C] {
            let encoded = String(Character(Unicode.Scalar(scalar)!))
                .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            XCTAssertEqual(parse("tapthetab://switch?query=a\(encoded)b"), switcher(.allWindows, "ab"),
                           String(scalar, radix: 16))
        }
    }

    func testEmojiAndJoinersSurvive() {
        // 👩‍💻 contains a zero-width joiner, which is formatting but not bidi.
        let encoded = "👩‍💻 term".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        XCTAssertEqual(parse("tapthetab://switch?query=\(encoded)"), switcher(.allWindows, "👩‍💻 term"))
    }

    func testScriptLikeValuesAreJustText() {
        let hostile = "javascript:alert(1)//<script>"
        let encoded = hostile.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        XCTAssertEqual(parse("tapthetab://switch?query=\(encoded)"), switcher(.allWindows, hostile))
    }

    func testHugeQueryIsTruncated() {
        let long = String(repeating: "a", count: 100_000)
        guard case .showSwitcher(let scope, let query)? = parse("tapthetab://switch?query=\(long)") else {
            return XCTFail("expected showSwitcher")
        }
        XCTAssertEqual(scope, .allWindows)
        XCTAssertEqual(query, String(repeating: "a", count: 200))
    }

    func testTruncationCountsCharactersNotScalars() {
        // "é" as e + combining acute is one Character but two scalars.
        let decomposed = String(repeating: "e\u{301}", count: 300)
        let encoded = decomposed.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        guard case .showSwitcher(_, let query?)? = parse("tapthetab://switch?query=\(encoded)") else {
            return XCTFail("expected a query")
        }
        XCTAssertEqual(query.count, 200)
        XCTAssertEqual(query.unicodeScalars.count, 400)
    }

    func testTruncationThenTrimsTrailingSpace() {
        let text = String(repeating: "a", count: 199) + " " + String(repeating: "b", count: 50)
        guard case .showSwitcher(_, let query?)? = parse("tapthetab://switch?query=\(text.replacingOccurrences(of: " ", with: "%20"))") else {
            return XCTFail("expected a query")
        }
        XCTAssertEqual(query, String(repeating: "a", count: 199))
    }

    func testControlCharactersDoNotCountTowardTheLimit() {
        let text = String(repeating: "%00", count: 500) + String(repeating: "x", count: 200)
        XCTAssertEqual(parse("tapthetab://switch?query=\(text)"), switcher(.allWindows, String(repeating: "x", count: 200)))
    }

    // MARK: - Bad encoding

    func testInvalidUTF8IsRejected() {
        XCTAssertNil(parse("tapthetab://switch?query=%FF"))
        XCTAssertNil(parse("tapthetab://switch?query=%C3"))
        XCTAssertNil(parse("tapthetab://switch?query=%C0%AF"), "overlong encoding")
    }

    func testBadEncodingInAnUnknownParameterIsRejectedToo() {
        XCTAssertNil(parse("tapthetab://switch?junk=%FF&query=x"))
        XCTAssertNil(parse("tapthetab://settings?junk=%FF"))
    }

    func testMalformedEscapeNeverCrashes() {
        // Foundation either refuses this URL or re-encodes the stray "%"; both are fine,
        // as long as the result is nil or the literal text.
        for raw in ["tapthetab://switch?query=%zz", "tapthetab://switch?query=%", "tapthetab://switch?query=%4"] {
            guard let url = URL(string: raw), let command = AutomationCommand(url: url) else { continue }
            guard case .showSwitcher(.allWindows, let query?) = command else {
                return XCTFail("unexpected \(command) for \(raw)")
            }
            XCTAssertTrue(query.hasPrefix("%"), raw)
        }
    }

    // MARK: - Rejected URLs

    func testOtherSchemesAreRejected() {
        for raw in ["https://switch", "http://example.com/tapthetab://switch", "file:///switch",
                    "javascript:switch", "tapthetabx://switch", "tapthe://switch", "x-tapthetab://switch",
                    "data:text/plain,tapthetab://switch"] {
            XCTAssertNil(parse(raw), raw)
        }
    }

    func testUnknownCommandsAreRejected() {
        for raw in ["tapthetab://close", "tapthetab://quit", "tapthetab://minimize", "tapthetab://hide",
                    "tapthetab://activate?query=x", "tapthetab://switcher", "tapthetab://switch-now",
                    "tapthetab://", "tapthetab:", "tapthetab:///", "tapthetab://settings2"] {
            XCTAssertNil(parse(raw), raw)
        }
    }

    func testExtraPathIsRejected() {
        for raw in ["tapthetab://switch/close", "tapthetab://switch/x", "tapthetab://settings/switch",
                    "tapthetab:switch/close", "tapthetab:///switch/close"] {
            XCTAssertNil(parse(raw), raw)
        }
    }

    func testCredentialsAndPortsAreRejected() {
        for raw in ["tapthetab://user@switch", "tapthetab://user:pw@switch", "tapthetab://switch:80",
                    "tapthetab://switch@evil.example", "tapthetab://evil.example/switch"] {
            XCTAssertNil(parse(raw), raw)
        }
    }

    func testCommandsAreNotReadFromTheQuery() {
        XCTAssertNil(parse("tapthetab://?switch"))
        XCTAssertNil(parse("tapthetab://x?command=settings"))
    }
}
