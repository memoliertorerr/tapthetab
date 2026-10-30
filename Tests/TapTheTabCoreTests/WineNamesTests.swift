import XCTest
@testable import TapTheTabCore

final class WineNamesTests: XCTestCase {
    // MARK: - isWineLoader

    func testKnownLoaderNames() {
        for name in [
            "wine", "wine64", "wine-preloader", "wine64-preloader", "wineloader", "wineloader64",
            "wine32on64", "wine32on64-preloader", "wine32on64-prelo",
            "Wine", "WINE64-PRELOADER", "WineLoader", " wine64-preloader \n",
        ] {
            XCTAssertTrue(WineNames.isWineLoader(name), name)
        }
    }

    func testLoaderPaths() {
        for path in [
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine64-preloader",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wineloader",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine",
            "/Users/me/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64-preloader",
            "/usr/local/opt/game-porting-toolkit/bin/wine64",
            "/opt/homebrew/bin/wine",
            "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine-preloader",
        ] {
            XCTAssertTrue(WineNames.isWineLoader(path), path)
        }
    }

    func testOtherNamesAreNotLoaders() {
        for name in [
            "", " ", "/", "wineserver", "winecfg", "winetricks", "Wine Stable", "CrossOver", "Whisky",
            "Safari", "wine64-preloader.exe", "notwine", "wines", "wine64-preloader-helper",
            "/usr/bin/winedbg", "C:\\windows\\wine64", "Wine Stable.app",
        ] {
            XCTAssertFalse(WineNames.isWineLoader(name), name)
        }
    }

    func testTrailingSlashPathStillNamesTheLoader() {
        XCTAssertTrue(WineNames.isWineLoader("/opt/wine/bin/wine64/"))
    }

    // MARK: - displayName

    private func name(_ arguments: [String]) -> String? {
        WineNames.displayName(fromArguments: arguments)
    }

    func testWindowsPathAfterTheLoader() {
        XCTAssertEqual(name([
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine64-preloader",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine64",
            "C:\\Program Files\\Notepad++\\notepad++.exe",
        ]), "notepad++")
    }

    func testProgramArgumentsAfterTheExeAreIgnored() {
        XCTAssertEqual(name(["wine64-preloader", "wine64", "C:\\Games\\Foo\\Foo.exe", "-windowed", "C:\\Games\\Foo\\launcher.exe"]), "Foo")
    }

    func testRewrittenArgv0IsTheWindowsPath() {
        // Wine rewrites the argument area so that argv[0] is the Windows program.
        XCTAssertEqual(name(["C:\\windows\\system32\\notepad.exe"]), "notepad")
        XCTAssertEqual(name(["C:\\Program Files (x86)\\Steam\\steam.exe", "-silent"]), "steam")
    }

    func testWhiskyStartUnix() {
        XCTAssertEqual(name([
            "/Users/me/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64-preloader",
            "/Users/me/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64",
            "start", "/unix",
            "/Users/me/Library/Containers/com.isaacmarovitz.Whisky/Bottles/8F0B-11/drive_c/Program Files/Some Game/Some Game.exe",
        ]), "Some Game")
    }

    func testGamePortingToolkit() {
        XCTAssertEqual(name([
            "/usr/local/opt/game-porting-toolkit/bin/wine64-preloader",
            "/usr/local/opt/game-porting-toolkit/bin/wine64",
            "C:\\Program Files (x86)\\Battle.net\\Battle.net Launcher.exe",
        ]), "Battle.net Launcher")
    }

    func testCrossOverWineScriptFlagsAreSkipped() {
        XCTAssertEqual(name([
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wineloader",
            "--bottle", "Steam", "--check", "--wait-children",
            "--start", "C:/users/crossover/Start Menu/Programs/Steam/Steam.lnk",
            "C:/Program Files (x86)/Steam/steam.exe",
        ]), "steam")
        XCTAssertNil(name([
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine",
            "--bottle", "Office", "--start", "C:/users/crossover/Start Menu/Programs/Word.lnk",
        ]), "a shortcut is not a program name")
    }

    func testStartAndCmdLaunchersAreSkipped() {
        XCTAssertEqual(name(["wine64-preloader", "wine64", "C:\\windows\\command\\start.exe", "/unix", "/Users/me/Games/game.exe"]), "game")
        XCTAssertEqual(name(["wine", "start.exe", "/wait", "/min", "Z:\\Users\\me\\Tools\\tool.EXE"]), "tool")
        XCTAssertEqual(name(["wine", "cmd.exe", "/c", "C:\\Tools\\build.exe"]), "build")
    }

    func testExplorerDesktopLauncher() {
        XCTAssertEqual(name(["wine64-preloader", "C:\\windows\\explorer.exe", "/desktop=shell,1024x768", "C:\\Games\\Old\\old.exe"]), "old")
        XCTAssertEqual(name(["explorer.exe /desktop=Game,1920x1080 C:\\Games\\New\\new.exe"]), "new", "as one command-line argument")
        XCTAssertEqual(name(["explorer.exe /desktop=shell,1024x768 game.exe"]), "game")
    }

    func testLauncherAloneGivesNil() {
        XCTAssertNil(name(["wine64-preloader", "C:\\windows\\explorer.exe", "/desktop=shell,1024x768"]))
        XCTAssertNil(name(["wine", "start.exe", "/unix"]))
        XCTAssertNil(name(["C:\\windows\\system32\\cmd.exe"]))
        XCTAssertNil(name(["C:\\windows\\system32\\conhost.exe", "--headless"]))
    }

    func testCommandLineInOneArgument() {
        XCTAssertEqual(name([#""C:\Program Files\My App\app.exe" -flag value"#]), "app")
        XCTAssertEqual(name([#"C:\Games\game.exe -windowed -w 800"#]), "game")
        XCTAssertEqual(name([#"start /unix "/Users/me/My Games/x y.exe""#]), "x y")
        XCTAssertEqual(name(["cmd /c C:\\x\\foo.exe /quiet"]), "foo")
        XCTAssertEqual(name(["--bottle Steam C:\\Program Files\\Steam\\steam.exe"]), "steam")
        XCTAssertEqual(name(["start game.exe"]), "game")
    }

    func testSingleQuotes() {
        XCTAssertEqual(name(["'C:\\Program Files\\Tool\\tool.exe'"]), "tool")
    }

    func testPathsWithSpacesAndDashes() {
        XCTAssertEqual(name(["C:\\Program Files\\Foo - Bar\\Foo - Bar.exe"]), "Foo - Bar")
        XCTAssertEqual(name(["/Volumes/My Disk/Games/My Game.exe"]), "My Game")
        XCTAssertEqual(name(["My Game.exe"]), "My Game", "a bare name may have spaces")
    }

    func testCaseInsensitiveExtensionAndSeparators() {
        XCTAssertEqual(name(["C:/Games/UPPER.EXE"]), "UPPER")
        XCTAssertEqual(name(["Z:\\home\\me\\Mixed.Exe"]), "Mixed")
        XCTAssertEqual(name(["C:\\a/b\\c/d.exe"]), "d")
        XCTAssertEqual(name(["\\\\server\\share\\app.exe"]), "app")
        XCTAssertEqual(name(["C:app.exe"]), "app", "drive-relative path")
        XCTAssertEqual(name(["  C:\\x\\padded.exe  "]), "padded")
    }

    func testDotsInNamesAreKept() {
        XCTAssertEqual(name(["C:\\Program Files\\Battle.net\\Battle.net.exe"]), "Battle.net")
        XCTAssertEqual(name(["C:\\x\\app.v2.exe"]), "app.v2")
    }

    func testNotExecutables() {
        for arguments in [
            [], [""], ["wine64-preloader"], ["wine64-preloader", "wine64"],
            ["wine", "C:\\x\\library.dll"], ["wine", "C:\\x\\setup.msi"], ["wine", "notepad"], ["wine", "winecfg"],
            ["wine", "C:\\x\\app.exe.config"], ["wine", "C:\\x\\exe"], ["wine", "C:\\x\\.exe"], ["wine", ".exe"],
            ["wine", "C:\\x\\"], ["wine", "-exe"], ["wine", "--run=C:\\x\\app.exe"], ["wine", "C:\\..exe"],
            ["wine", "C:\\x\\ .exe"], ["wine", "C:\\x\\---.exe"],
        ] {
            XCTAssertNil(name(arguments), arguments.description)
        }
    }

    func testResultIsNeverPathLike() {
        let samples: [[String]] = [
            ["wine", "C:\\a\\b.exe"], ["/x/y/z.exe"], ["C:/a/b.exe"], ["a\\b.exe"], ["explorer.exe /desktop=a,1x1 b.exe"],
            ["\"C:\\a b\\c d.exe\" e"], ["start /unix /Users/a/b c/d e.exe"], ["Z:\\a\\b:c.exe"],
        ]
        for arguments in samples {
            let result = name(arguments)
            XCTAssertNotNil(result, arguments.description)
            if let result {
                XCTAssertFalse(result.isEmpty)
                XCTAssertFalse(result.contains("/") || result.contains("\\") || result.contains(":"), result)
                XCTAssertFalse(result.lowercased().hasSuffix(".exe"), result)
            }
        }
    }

    func testControlCharactersAndOverlongNamesAreRejected() {
        XCTAssertNil(name(["C:\\x\\bad\u{0007}name.exe"]))
        XCTAssertNil(name(["C:\\x\\rtl\u{202E}exe.exe"]))
        XCTAssertNil(name(["C:\\x\\" + String(repeating: "a", count: 200) + ".exe"]))
        XCTAssertEqual(name(["C:\\x\\" + String(repeating: "a", count: 80) + ".exe"])?.count, 80)
        XCTAssertEqual(name(["C:\\x\\" + String(repeating: "a", count: 200) + ".exe", "C:\\y\\ok.exe"]), "ok", "a bad candidate does not stop the search")
    }

    func testUnicodeNamesAreKept() {
        XCTAssertEqual(name(["C:\\Program Files\\日本語\\ゲーム.exe"]), "ゲーム")
        XCTAssertEqual(name(["C:\\Spiele\\Größe.exe"]), "Größe")
    }

    func testHostileInputIsBounded() {
        let many = Array(repeating: "-flag", count: 10_000) + ["C:\\late\\app.exe"]
        XCTAssertNil(name(many), "only the first arguments are looked at")
        let huge = String(repeating: "x", count: 100_000) + ".exe"
        XCTAssertNil(name([huge]))
        XCTAssertEqual(name([huge, "C:\\ok\\fine.exe"]), "fine")
        let manyExes = Array(repeating: "x", count: 500).joined(separator: ".exe ") // one long command line
        XCTAssertNotNil(name([manyExes]))
    }

    func testFirstUsableProgramWins() {
        XCTAssertEqual(name(["wine", "C:\\a\\first.exe", "C:\\b\\second.exe"]), "first")
        XCTAssertEqual(name(["wine", "start.exe", "explorer.exe", "cmd.exe", "C:\\b\\real.exe"]), "real")
    }
}
