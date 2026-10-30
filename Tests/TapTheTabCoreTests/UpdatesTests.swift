import XCTest
@testable import TapTheTabCore

final class AppVersionTests: XCTestCase {
    private func v(_ string: String, file: StaticString = #filePath, line: UInt = #line) -> AppVersion {
        guard let version = AppVersion(string) else {
            XCTFail("\(string) should parse", file: file, line: line)
            return AppVersion("0.0.0")!
        }
        return version
    }

    // MARK: - Parsing

    func testParsesPlainVersions() {
        let version = v("0.10.0")
        XCTAssertEqual(version.major, 0)
        XCTAssertEqual(version.minor, 10)
        XCTAssertEqual(version.patch, 0)
        XCTAssertEqual(version.prerelease, [])
        XCTAssertFalse(version.isPrerelease)
        XCTAssertEqual(version.description, "0.10.0")
        XCTAssertEqual(v("123.456.789").description, "123.456.789")
    }

    func testLeadingVIsAccepted() {
        XCTAssertEqual(v("v1.2.3"), v("1.2.3"))
        XCTAssertEqual(v("V1.2.3"), v("1.2.3"))
        XCTAssertEqual(v("v1.2.3").description, "1.2.3")
        XCTAssertNil(AppVersion("vv1.2.3"))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("version1.2.3"))
    }

    func testShortVersionsArePadded() {
        XCTAssertEqual(v("1.2"), v("1.2.0"))
        XCTAssertEqual(v("1"), v("1.0.0"))
        XCTAssertEqual(v("v2").description, "2.0.0")
        XCTAssertEqual(v("1.2-beta").description, "1.2.0-beta")
    }

    func testPrereleaseIsParsed() {
        let version = v("1.0.0-beta.2")
        XCTAssertEqual(version.prerelease, ["beta", "2"])
        XCTAssertTrue(version.isPrerelease)
        XCTAssertEqual(version.description, "1.0.0-beta.2")
        XCTAssertEqual(v("1.0.0-x-y-z.--").prerelease, ["x-y-z", "--"], "hyphens are allowed inside identifiers")
        XCTAssertEqual(v("1.0.0-0.3.7").prerelease, ["0", "3", "7"])
        XCTAssertEqual(v("1.0.0-alpha-1").prerelease, ["alpha-1"], "only the first hyphen starts the prerelease")
    }

    func testBuildMetadataIsIgnored() {
        XCTAssertEqual(v("1.0.0+20130313144700"), v("1.0.0"))
        XCTAssertEqual(v("1.0.0-beta+exp.sha.5114f85"), v("1.0.0-beta"))
        XCTAssertEqual(v("1.0.0+21AF26D3----117B344092BD").description, "1.0.0")
        XCTAssertEqual(v("1.0.0+001"), v("1.0.0"), "leading zeros are fine in build metadata")
        XCTAssertEqual(v("1.0.0-rc.1+build-7").prerelease, ["rc", "1"])
        XCTAssertNil(AppVersion("1.0.0+"))
        XCTAssertNil(AppVersion("1.0.0+a..b"))
        XCTAssertNil(AppVersion("1.0.0+a+b"))
        XCTAssertNil(AppVersion("1.0.0+ä"))
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(v("  v0.10.0\n"), v("0.10.0"))
        XCTAssertNil(AppVersion("0. 10.0"))
        XCTAssertNil(AppVersion("v 1.0.0"))
    }

    func testMalformedVersionsAreRejected() {
        for bad in [
            "", " ", "1.2.3.4", "1..3", ".1.2", "1.2.", "a.b.c", "1.2.x", "-1.2.3", "1.-2.3",
            "01.2.3", "1.02.3", "1.2.03", "1.2.3-", "1.2.3-beta..1", "1.2.3-beta_1", "1.2.3-01",
            "1.2.3-beta.007", "1.2.3 beta", "1.2.3-beta 2", "+1.2.3", "1.2.3-é", "１.２.３", "1.2.3\u{0}",
            "latest", "nightly", "v1.2.3-", "1,2,3", "0x1.2.3",
            "99999999999999999999.0.0", "1.99999999999999999999.0",
            String(repeating: "1", count: 65), "1.2.3-" + String(repeating: "a", count: 100),
        ] {
            XCTAssertNil(AppVersion(bad), bad.debugDescription)
        }
        XCTAssertEqual(AppVersion("1.2.3--")?.prerelease, ["-"], "a lone hyphen is a valid identifier")
    }

    func testZeroIsAValidPart() {
        XCTAssertEqual(v("0.0.0").description, "0.0.0")
        XCTAssertEqual(v("1.0.0-0").prerelease, ["0"])
        XCTAssertEqual(v("1.0.0-0a").prerelease, ["0a"], "an alphanumeric identifier may start with 0")
    }

    // MARK: - Precedence

    func testSemVerSpecExampleOrder() {
        // From semver.org, section 11.
        let ordered = [
            "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
            "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "2.0.0", "2.1.0", "2.1.1",
        ].map { v($0) }
        for (index, version) in ordered.enumerated() {
            for (otherIndex, other) in ordered.enumerated() {
                XCTAssertEqual(version < other, index < otherIndex, "\(version) < \(other)")
                XCTAssertEqual(version == other, index == otherIndex, "\(version) == \(other)")
            }
        }
        XCTAssertEqual(ordered.shuffled().sorted(), ordered)
    }

    func testNumericPartsCompareNumerically() {
        XCTAssertLessThan(v("0.9.0"), v("0.10.0"))
        XCTAssertLessThan(v("0.10.0"), v("0.10.1"))
        XCTAssertLessThan(v("1.9.9"), v("1.10.0"))
        XCTAssertLessThan(v("9.0.0"), v("10.0.0"))
        XCTAssertLessThan(v("1.0.0-rc.9"), v("1.0.0-rc.10"))
        XCTAssertLessThan(v("1.0.0-2"), v("1.0.0-10"))
    }

    func testHugeNumericPrereleaseIdentifiersCompareWithoutOverflow() {
        let small = v("1.0.0-99999999999999999999")
        let large = v("1.0.0-100000000000000000000")
        XCTAssertLessThan(small, large)
        XCTAssertLessThan(large, v("1.0.0-a"), "numeric below alphanumeric")
    }

    func testNumericIdentifiersRankBelowAlphanumeric() {
        XCTAssertLessThan(v("1.0.0-1"), v("1.0.0-alpha"))
        XCTAssertLessThan(v("1.0.0-999"), v("1.0.0-0a"))
        XCTAssertLessThan(v("1.0.0-alpha.1"), v("1.0.0-alpha.a"))
    }

    func testAlphanumericIdentifiersCompareInASCIIOrder() {
        XCTAssertLessThan(v("1.0.0-Beta"), v("1.0.0-alpha"), "uppercase sorts before lowercase in ASCII")
        XCTAssertLessThan(v("1.0.0-a-b"), v("1.0.0-ab"), "hyphen sorts before letters")
        XCTAssertLessThan(v("1.0.0-rc"), v("1.0.0-rc1"))
    }

    func testPrereleaseIsBelowItsReleaseButAboveTheOneBefore() {
        XCTAssertLessThan(v("1.0.0-rc.1"), v("1.0.0"))
        XCTAssertGreaterThan(v("1.0.0-alpha"), v("0.99.99"))
        XCTAssertFalse(v("1.0.0") < v("1.0.0-rc.1"))
    }

    func testEqualityIsConsistentWithOrdering() {
        let a = v("v1.2.3-beta.1+build.5")
        let b = v("1.2.3-beta.1")
        XCTAssertEqual(a, b)
        XCTAssertFalse(a < b)
        XCTAssertFalse(b < a)
        XCTAssertEqual(Set([a, b, v("1.2")]).count, 2)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testComparableOperatorsAndSorting() {
        let versions = ["0.10.0", "0.9.0", "0.10.0-beta", "1.0.0", "0.1"].map { v($0) }
        XCTAssertEqual(versions.sorted().map(\.description), ["0.1.0", "0.9.0", "0.10.0-beta", "0.10.0", "1.0.0"])
        XCTAssertEqual(versions.max()?.description, "1.0.0")
        XCTAssertTrue(v("1.0.0") >= v("1.0"))
        XCTAssertTrue(v("1.0.0") <= v("1"))
    }
}

final class ReleaseFeedTests: XCTestCase {
    private let dmgURL = "https://github.com/memoliertorerr/tapthetab/releases/download/v0.10.0/TapTheTab-0.10.0.dmg"
    private let sumsURL = "https://github.com/memoliertorerr/tapthetab/releases/download/v0.10.0/SHA256SUMS.txt"
    private let pageURL = "https://github.com/memoliertorerr/tapthetab/releases/tag/v0.10.0"

    /// A trimmed copy of a real GitHub "latest release" response.
    private func releaseJSON(
        tag: String = "v0.10.0",
        htmlURL: String? = nil,
        draft: String = "false",
        prerelease: String = "false",
        body: String = ###""## Added\r\n- Update checks""###,
        assets: String? = nil
    ) -> Data {
        let assetsJSON = assets ?? ##"""
        [
          {"url": "https://api.github.com/repos/memoliertorerr/tapthetab/releases/assets/1", "id": 1, "name": "TapTheTab-0.10.0.zip", "content_type": "application/zip", "state": "uploaded", "size": 1234567, "download_count": 3, "browser_download_url": "https://github.com/memoliertorerr/tapthetab/releases/download/v0.10.0/TapTheTab-0.10.0.zip"},
          {"url": "https://api.github.com/repos/memoliertorerr/tapthetab/releases/assets/2", "id": 2, "name": "TapTheTab-0.10.0.dmg", "content_type": "application/x-apple-diskimage", "state": "uploaded", "size": 2345678, "download_count": 9, "browser_download_url": "\##(dmgURL)", "uploader": {"login": "github-actions[bot]", "id": 41898282}},
          {"url": "https://api.github.com/repos/memoliertorerr/tapthetab/releases/assets/3", "id": 3, "name": "SHA256SUMS.txt", "content_type": "text/plain", "state": "uploaded", "size": 180, "download_count": 1, "browser_download_url": "\##(sumsURL)"}
        ]
        """##
        let json = ##"""
        {
          "url": "https://api.github.com/repos/memoliertorerr/tapthetab/releases/1",
          "html_url": \##(htmlURL ?? "\"\(pageURL)\""),
          "id": 1,
          "author": {"login": "memoliertorerr", "id": 1, "type": "User", "site_admin": false},
          "node_id": "RE_kwDO",
          "tag_name": "\##(tag)",
          "target_commitish": "main",
          "name": "TapTheTab \##(tag)",
          "draft": \##(draft),
          "immutable": false,
          "prerelease": \##(prerelease),
          "created_at": "2026-10-30T10:00:00Z",
          "published_at": "2026-10-30T10:05:00Z",
          "assets": \##(assetsJSON),
          "tarball_url": "https://api.github.com/repos/memoliertorerr/tapthetab/tarball/\##(tag)",
          "zipball_url": "https://api.github.com/repos/memoliertorerr/tapthetab/zipball/\##(tag)",
          "body": \##(body),
          "reactions": {"total_count": 0, "+1": 0}
        }
        """##
        return Data(json.utf8)
    }

    /// `value` as a JSON string literal, escaped properly.
    private func json(_ value: String) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }

    func testConstants() {
        XCTAssertEqual(ReleaseFeed.latestURL.absoluteString, "https://api.github.com/repos/memoliertorerr/tapthetab/releases/latest")
        XCTAssertEqual(ReleaseFeed.releasesPageURL.absoluteString, "https://github.com/memoliertorerr/tapthetab/releases")
        XCTAssertEqual(ReleaseFeed.dmgName(for: AppVersion("0.10.0")!), "TapTheTab-0.10.0.dmg")
        XCTAssertEqual(ReleaseFeed.dmgName(for: AppVersion("v1.2")!), "TapTheTab-1.2.0.dmg")
        XCTAssertEqual(ReleaseFeed.dmgName(for: AppVersion("1.0.0-rc.1+b")!), "TapTheTab-1.0.0-rc.1.dmg")
    }

    func testParsesARealisticRelease() throws {
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON()))
        XCTAssertEqual(info.version, AppVersion("0.10.0"))
        XCTAssertEqual(info.tag, "v0.10.0")
        XCTAssertEqual(info.pageURL.absoluteString, pageURL)
        XCTAssertEqual(info.dmgURL?.absoluteString, dmgURL)
        XCTAssertEqual(info.checksumsURL?.absoluteString, sumsURL)
        XCTAssertEqual(info.notes, "## Added\r\n- Update checks")
        XCTAssertFalse(info.isPrerelease)
    }

    func testTagWithoutV() throws {
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(tag: "0.10.0")))
        XCTAssertEqual(info.tag, "0.10.0")
        XCTAssertEqual(info.version.description, "0.10.0")
    }

    func testDraftsAndPrereleasesAreIgnored() {
        XCTAssertNil(ReleaseFeed.parseLatest(releaseJSON(draft: "true")))
        XCTAssertNil(ReleaseFeed.parseLatest(releaseJSON(prerelease: "true")))
        XCTAssertNil(ReleaseFeed.parseLatest(releaseJSON(tag: "v0.10.0-beta.1")), "a prerelease tag counts even when not flagged")
    }

    func testFlagsOfTheWrongTypeAreRejected() {
        XCTAssertNil(ReleaseFeed.parseLatest(releaseJSON(draft: #""false""#)))
        XCTAssertNil(ReleaseFeed.parseLatest(releaseJSON(prerelease: "0")))
        XCTAssertNotNil(ReleaseFeed.parseLatest(releaseJSON(draft: "null")), "null is the same as missing")
    }

    func testMissingFlagsReadAsFalse() throws {
        let json = #"{"tag_name": "v1.0.0", "html_url": "https://github.com/memoliertorerr/tapthetab/releases/tag/v1.0.0"}"#
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(Data(json.utf8)))
        XCTAssertEqual(info.version, AppVersion("1.0.0"))
        XCTAssertNil(info.dmgURL)
        XCTAssertNil(info.checksumsURL)
        XCTAssertEqual(info.notes, "")
    }

    func testUnparsableTagsAreRejected() {
        for tag in ["latest", "release-2026-10", "v1.2.3.4", "", "v01.0.0", "TapTheTab 0.10"] {
            XCTAssertNil(ReleaseFeed.parseLatest(releaseJSON(tag: tag)), tag)
        }
        XCTAssertEqual(ReleaseFeed.parseLatest(releaseJSON(tag: "v0.10"))?.version.description, "0.10.0", "two-part tags are versions")
    }

    func testMissingOrWrongTypedRequiredFieldsAreRejected() {
        XCTAssertNil(ReleaseFeed.parseLatest(Data(#"{"html_url": "https://github.com/memoliertorerr/tapthetab/releases/tag/v1.0.0"}"#.utf8)))
        XCTAssertNil(ReleaseFeed.parseLatest(Data(#"{"tag_name": "v1.0.0"}"#.utf8)))
        XCTAssertNil(ReleaseFeed.parseLatest(releaseJSON(htmlURL: "null")))
        XCTAssertNil(ReleaseFeed.parseLatest(releaseJSON(htmlURL: "42")))
        XCTAssertNil(ReleaseFeed.parseLatest(Data(#"{"tag_name": 1.0, "html_url": "https://github.com/memoliertorerr/tapthetab/releases/tag/v1.0.0"}"#.utf8)))
    }

    func testBadJSONIsRejected() {
        for text in ["", "null", "[]", "\"v1.0.0\"", "{", "{\"tag_name\": \"v1.0.0\",}", "<html>rate limited</html>",
                     #"{"message": "API rate limit exceeded", "documentation_url": "https://docs.github.com"}"#,
                     #"{"message": "Not Found"}"#] {
            XCTAssertNil(ReleaseFeed.parseLatest(Data(text.utf8)), text)
        }
        XCTAssertNil(ReleaseFeed.parseLatest(Data([0xFF, 0xFE, 0x00, 0x7B])))
    }

    func testOversizedResponseIsRejected() {
        let padding = String(repeating: "x", count: ReleaseFeed.maximumResponseBytes)
        XCTAssertNil(ReleaseFeed.parseLatest(releaseJSON(body: "\"\(padding)\"")))
    }

    func testLongNotesAreCut() throws {
        let long = String(repeating: "a", count: ReleaseFeed.maximumNotesLength + 500)
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(body: "\"\(long)\"")))
        XCTAssertEqual(info.notes.count, ReleaseFeed.maximumNotesLength)
    }

    func testOddBodiesBecomeEmptyNotes() throws {
        for body in ["null", "42", "[\"a\"]", "{}"] {
            let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(body: body)), body)
            XCTAssertEqual(info.notes, "", body)
        }
    }

    func testDeeplyNestedJunkIsHandled() {
        let nested = String(repeating: "[", count: 200) + String(repeating: "]", count: 200)
        XCTAssertNotNil(ReleaseFeed.parseLatest(releaseJSON(body: #""ok""#, assets: nested)), "assets that are not assets are ignored")
        XCTAssertNil(ReleaseFeed.parseLatest(Data(nested.utf8)))
    }

    func testUnknownAndExtraFieldsAreIgnored() throws {
        let json = #"{"tag_name": "v2.0.0", "html_url": "https://github.com/memoliertorerr/tapthetab/releases/tag/v2.0.0", "draft": false, "prerelease": false, "assets": [], "something_new": {"a": [1, 2, null]}, "body": "x"}"#
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(Data(json.utf8)))
        XCTAssertEqual(info.version, AppVersion("2.0.0"))
        XCTAssertNil(info.dmgURL)
    }

    // MARK: - html_url

    func testPageURLMustBeThisProjectsReleasesOnGitHub() {
        for bad in [
            "http://github.com/memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "https://gitlab.com/memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "https://github.com.evil.example/memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "https://evilgithub.com/memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "https://github.com/someoneelse/tapthetab/releases/tag/v0.10.0",
            "https://github.com/memoliertorerr/tapthetab-fork/releases/tag/v0.10.0",
            "https://github.com/memoliertorerr/tapthetab/issues/1",
            "https://github.com/memoliertorerr/tapthetab/releases/",
            "https://github.com/memoliertorerr/tapthetab/releases",
            "https://github.com/memoliertorerr/tapthetab/releases/../../../evil/repo",
            "https://github.com/memoliertorerr/tapthetab/releases/%2e%2e/%2e%2e/evil",
            "https://github.com@evil.example/memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "https://user:pass@github.com/memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "https://github.com:8443/memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "https://github.com\\@evil.example/memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "https://github.com/memoliertorerr/tapthetab/releases/tag/v0.10.0 javascript:alert(1)",
            "https://github.com./memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "https://gіthub.com/memoliertorerr/tapthetab/releases/tag/v0.10.0", // Cyrillic і
            "javascript:alert(1)",
            "file:///etc/passwd",
            "//github.com/memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "",
        ] {
            XCTAssertNil(ReleaseFeed.parseLatest(releaseJSON(htmlURL: json(bad))), bad)
        }
    }

    func testPageURLVariantsThatAreFine() throws {
        for good in [
            "https://github.com/memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "HTTPS://GitHub.com/memoliertorerr/tapthetab/releases/tag/v0.10.0",
            "https://github.com/MemoliErtorerr/TapTheTab/releases/tag/v0.10.0",
            "https://github.com/memoliertorerr/tapthetab/releases/tag/v0.10.0?x=1#notes",
        ] {
            let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(htmlURL: json(good))), good)
            XCTAssertEqual(info.pageURL.absoluteString, good)
        }
    }

    // MARK: - Assets

    private func assets(_ entries: [(String, String)]) -> String {
        "[" + entries.map { #"{"name": \#(json($0.0)), "browser_download_url": \#(json($0.1))}"# }.joined(separator: ",") + "]"
    }

    func testAssetsOnTrustedHostsAreKept() throws {
        let objects = "https://objects.githubusercontent.com/github-production-release-asset-2e65be/1/2?X-Amz-Algorithm=AWS4-HMAC-SHA256&response-content-disposition=attachment%3B%20filename%3DTapTheTab-0.10.0.dmg"
        let releaseAssets = "https://release-assets.githubusercontent.com/github-production-release-asset/1/3?sp=r&sig=abc%3D"
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(assets: assets([
            ("TapTheTab-0.10.0.dmg", objects), ("SHA256SUMS.txt", releaseAssets),
        ]))))
        XCTAssertEqual(info.dmgURL?.absoluteString, objects)
        XCTAssertEqual(info.checksumsURL?.absoluteString, releaseAssets)
    }

    func testUntrustedAssetURLsAreDroppedButTheReleaseIsKept() throws {
        for bad in [
            "http://github.com/memoliertorerr/tapthetab/releases/download/v0.10.0/TapTheTab-0.10.0.dmg",
            "https://evil.example/TapTheTab-0.10.0.dmg",
            "https://githubusercontent.com.evil.example/x.dmg",
            "https://evilgithubusercontent.com/x.dmg",
            "https://githubusercontent.com/x.dmg",
            "https://.githubusercontent.com/x.dmg",
            "https://objects.githubusercontent.com",
            "https://objects.githubusercontent.com/",
            "https://github.com/someoneelse/tapthetab/releases/download/v0.10.0/TapTheTab-0.10.0.dmg",
            "https://github.com/memoliertorerr/tapthetab/archive/refs/tags/v0.10.0.zip",
            "https://github.com/memoliertorerr/tapthetab/releases/download/../../../../evil/x.dmg",
            "https://github.com@evil.example/memoliertorerr/tapthetab/releases/download/v0.10.0/TapTheTab-0.10.0.dmg",
            "https://objects.githubusercontent.com:444/x",
            "https://objects.githubusercontent.com\\@evil.example/x",
            "ftp://objects.githubusercontent.com/x",
            "TapTheTab-0.10.0.dmg",
            "",
        ] {
            let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(assets: assets([
                ("TapTheTab-0.10.0.dmg", bad), ("SHA256SUMS.txt", sumsURL),
            ]))), bad)
            XCTAssertNil(info.dmgURL, bad)
            XCTAssertEqual(info.checksumsURL?.absoluteString, sumsURL, "the other asset is unaffected by \(bad)")
        }
    }

    func testAssetsAreMatchedByExactName() throws {
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(assets: assets([
            ("TapTheTab-0.9.0.dmg", "https://github.com/memoliertorerr/tapthetab/releases/download/v0.9.0/TapTheTab-0.9.0.dmg"),
            ("tapthetab-0.10.0.dmg", dmgURL),
            ("TapTheTab-0.10.0.dmg.sig", dmgURL),
            ("sha256sums.txt", sumsURL),
        ]))))
        XCTAssertNil(info.dmgURL)
        XCTAssertNil(info.checksumsURL)
    }

    func testMissingAssets() throws {
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(assets: "[]")))
        XCTAssertNil(info.dmgURL)
        XCTAssertNil(info.checksumsURL)
        let notAnArray = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(assets: #"{"name": "x"}"#)))
        XCTAssertNil(notAnArray.dmgURL)
    }

    func testMalformedAssetEntriesAreSkipped() throws {
        let json = "[1, null, \"x\", {\"name\": 5}, {\"name\": \"SHA256SUMS.txt\"}, "
            + #"{"name": "TapTheTab-0.10.0.dmg", "browser_download_url": "\#(dmgURL)"}, {"name": "SHA256SUMS.txt", "browser_download_url": "\#(sumsURL)"}]"#
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(assets: json)))
        XCTAssertEqual(info.dmgURL?.absoluteString, dmgURL)
        XCTAssertEqual(info.checksumsURL?.absoluteString, sumsURL, "an entry without a URL does not count as the asset")
    }

    func testFirstAssetWithTheNameWins() throws {
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(assets: assets([
            ("TapTheTab-0.10.0.dmg", "https://evil.example/x.dmg"),
            ("TapTheTab-0.10.0.dmg", dmgURL),
        ]))))
        XCTAssertNil(info.dmgURL, "a bad first match is not replaced by a later one")
    }

    func testAssetNameFollowsTheTagsVersion() throws {
        let url = "https://github.com/memoliertorerr/tapthetab/releases/download/v1.0/TapTheTab-1.0.0.dmg"
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(releaseJSON(tag: "v1.0", assets: assets([("TapTheTab-1.0.0.dmg", url)]))))
        XCTAssertEqual(info.dmgURL?.absoluteString, url)
    }

    func testReleaseInfoIsEquatable() throws {
        XCTAssertEqual(ReleaseFeed.parseLatest(releaseJSON()), ReleaseFeed.parseLatest(releaseJSON()))
        XCTAssertNotEqual(ReleaseFeed.parseLatest(releaseJSON()), ReleaseFeed.parseLatest(releaseJSON(body: #""other""#)))
        let made = ReleaseInfo(version: AppVersion("1.0.0")!, tag: "v1.0.0", pageURL: ReleaseFeed.releasesPageURL)
        XCTAssertNil(made.dmgURL)
        XCTAssertEqual(made.notes, "")
        XCTAssertFalse(made.isPrerelease)
    }
}

final class ChecksumsTests: XCTestCase {
    private let dmgHash = "3a7bd3e2360a3d29eea436fcfb7e44c735d117c42d1c1835420b6b9942dd4f1b"
    private let zipHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    func testShasumOutput() {
        let text = "\(dmgHash)  TapTheTab-0.10.0.dmg\n\(zipHash)  TapTheTab-0.10.0.zip\n"
        XCTAssertEqual(Checksums.parse(text), ["TapTheTab-0.10.0.dmg": dmgHash, "TapTheTab-0.10.0.zip": zipHash])
    }

    func testBinaryModeAndUppercaseHex() {
        let text = "\(dmgHash.uppercased()) *TapTheTab-0.10.0.dmg"
        XCTAssertEqual(Checksums.parse(text), ["TapTheTab-0.10.0.dmg": dmgHash])
    }

    func testBSDTaggedFormat() {
        XCTAssertEqual(Checksums.parse("SHA256 (TapTheTab-0.10.0.dmg) = \(dmgHash)\n"), ["TapTheTab-0.10.0.dmg": dmgHash])
        XCTAssertEqual(Checksums.parse("SHA256 (a (1).dmg) = \(dmgHash)"), ["a (1).dmg": dmgHash])
        XCTAssertEqual(Checksums.parse("SHA1 (x) = \(dmgHash)"), [:])
    }

    func testWindowsLineEndingsAndTrailingSpace() {
        let text = "\(dmgHash)  TapTheTab-0.10.0.dmg \r\n\(zipHash)  TapTheTab-0.10.0.zip\r\n\r\n"
        XCTAssertEqual(Checksums.parse(text), ["TapTheTab-0.10.0.dmg": dmgHash, "TapTheTab-0.10.0.zip": zipHash])
    }

    func testNamesWithSpacesAndPaths() {
        XCTAssertEqual(Checksums.parse("\(dmgHash)  My App 1.dmg"), ["My App 1.dmg": dmgHash])
        XCTAssertEqual(Checksums.parse("\(dmgHash)  dist/TapTheTab.dmg"), ["dist/TapTheTab.dmg": dmgHash], "names are kept as written")
    }

    func testMalformedLinesAreIgnored() {
        let text = """
        # checksums
        \(dmgHash) TapTheTab-0.10.0.dmg
        \(dmgHash)\tTapTheTab-tab.dmg
        \(String(dmgHash.dropLast()))  short.dmg
        \(dmgHash)0  long.dmg
        \(String(dmgHash.dropLast()))g  nothex.dmg
        \(dmgHash)
        \(dmgHash)
        \\\(dmgHash)  escaped\\nname.dmg
         \(dmgHash)  indented.dmg
        md5  x
        \(zipHash)  TapTheTab-0.10.0.zip
        """
        XCTAssertEqual(Checksums.parse(text), ["TapTheTab-0.10.0.zip": zipHash])
    }

    func testEmptyAndJunkInput() {
        XCTAssertEqual(Checksums.parse(""), [:])
        XCTAssertEqual(Checksums.parse("\n\n\r\n"), [:])
        XCTAssertEqual(Checksums.parse("<html><body>Not Found</body></html>"), [:])
        XCTAssertEqual(Checksums.parse(String(repeating: "a", count: 10_000)), [:])
    }

    func testConflictingDuplicatesAreDropped() {
        let text = "\(dmgHash)  a.dmg\n\(zipHash)  a.dmg\n\(zipHash)  b.zip\n\(zipHash.uppercased())  b.zip\n"
        XCTAssertEqual(Checksums.parse(text), ["b.zip": zipHash], "identical duplicates are fine; differing ones are untrustworthy")
    }

    func testRealPackageScriptOutputMatchesTheAssetName() {
        // scripts/package.sh runs `shasum -a 256 "$ZIP_NAME" "$DMG_NAME"` inside dist/.
        let version = AppVersion("0.10.0")!
        let text = "\(zipHash)  TapTheTab-0.10.0.zip\n\(dmgHash)  \(ReleaseFeed.dmgName(for: version))\n"
        XCTAssertEqual(Checksums.parse(text)[ReleaseFeed.dmgName(for: version)], dmgHash)
    }
}

final class UpdatePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testIntervalIsADay() {
        XCTAssertEqual(UpdatePolicy.checkInterval, 86_400)
    }

    func testNeverDueWhenDisabled() {
        for last in [nil, now, now.addingTimeInterval(-10 * 86_400), now.addingTimeInterval(86_400)] as [Date?] {
            XCTAssertFalse(UpdatePolicy.isCheckDue(enabled: false, lastCheck: last, now: now))
        }
    }

    func testDueWithoutAPreviousCheck() {
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: nil, now: now))
    }

    func testDueOnceTheIntervalHasPassed() {
        XCTAssertFalse(UpdatePolicy.isCheckDue(enabled: true, lastCheck: now, now: now))
        XCTAssertFalse(UpdatePolicy.isCheckDue(enabled: true, lastCheck: now.addingTimeInterval(-3_600), now: now))
        XCTAssertFalse(UpdatePolicy.isCheckDue(enabled: true, lastCheck: now.addingTimeInterval(-86_399), now: now))
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: now.addingTimeInterval(-86_400), now: now))
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: now.addingTimeInterval(-90 * 86_400), now: now))
    }

    func testDueWhenTheLastCheckIsInTheFuture() {
        // The clock was turned back (or the stored date is bogus): check rather than wait.
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: now.addingTimeInterval(1), now: now))
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: now.addingTimeInterval(365 * 86_400), now: now))
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: .distantFuture, now: now))
        XCTAssertTrue(UpdatePolicy.isCheckDue(enabled: true, lastCheck: .distantPast, now: now))
    }

    private func release(_ version: String, prerelease: Bool = false) -> ReleaseInfo {
        ReleaseInfo(version: AppVersion(version)!, tag: "v" + version, pageURL: ReleaseFeed.releasesPageURL, isPrerelease: prerelease)
    }

    func testOffersOnlyStrictlyNewerReleases() {
        let current = AppVersion("0.10.0")!
        XCTAssertTrue(UpdatePolicy.shouldOffer(release("0.10.1"), current: current))
        XCTAssertTrue(UpdatePolicy.shouldOffer(release("0.11.0"), current: current))
        XCTAssertTrue(UpdatePolicy.shouldOffer(release("1.0.0"), current: current))
        XCTAssertFalse(UpdatePolicy.shouldOffer(release("0.10.0"), current: current))
        XCTAssertFalse(UpdatePolicy.shouldOffer(release("0.9.9"), current: current))
        XCTAssertFalse(UpdatePolicy.shouldOffer(release("0.1.0"), current: current))
    }

    func testNumericNotStringComparison() {
        XCTAssertTrue(UpdatePolicy.shouldOffer(release("0.10.0"), current: AppVersion("0.9.0")!))
        XCTAssertFalse(UpdatePolicy.shouldOffer(release("0.9.0"), current: AppVersion("0.10.0")!))
    }

    func testPrereleasesAreNeverOffered() {
        let current = AppVersion("0.10.0")!
        XCTAssertFalse(UpdatePolicy.shouldOffer(release("0.11.0", prerelease: true), current: current))
        XCTAssertFalse(UpdatePolicy.shouldOffer(release("0.11.0-beta.1"), current: current))
        XCTAssertFalse(UpdatePolicy.shouldOffer(release("1.0.0-rc.1", prerelease: true), current: current))
    }

    func testAPrereleaseBuildIsOfferedItsRelease() {
        XCTAssertTrue(UpdatePolicy.shouldOffer(release("1.0.0"), current: AppVersion("1.0.0-rc.2")!))
        XCTAssertFalse(UpdatePolicy.shouldOffer(release("0.9.0"), current: AppVersion("1.0.0-rc.2")!))
    }

    func testEndToEndFromJSON() throws {
        let json = #"{"tag_name": "v0.11.0", "html_url": "https://github.com/memoliertorerr/tapthetab/releases/tag/v0.11.0", "draft": false, "prerelease": false, "assets": []}"#
        let info = try XCTUnwrap(ReleaseFeed.parseLatest(Data(json.utf8)))
        XCTAssertTrue(UpdatePolicy.shouldOffer(info, current: AppVersion("0.10.0")!))
        XCTAssertFalse(UpdatePolicy.shouldOffer(info, current: AppVersion("v0.11.0")!))
    }
}
