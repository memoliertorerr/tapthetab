import XCTest
@testable import TapTheTabCore

final class WindowAdmissionTests: XCTestCase {
    private func traits(_ subrole: String?, title: Bool = true, layer: Int? = 0, alpha: Double? = 1,
                        size: Size? = Size(width: 800, height: 600), role: String? = "AXWindow") -> WindowTraits {
        WindowTraits(role: role, subrole: subrole, hasTitle: title, layer: layer, alpha: alpha, size: size)
    }

    func testStandardWindowsAlwaysCount() {
        XCTAssertTrue(WindowAdmission.isSwitchable(traits("AXStandardWindow")))
        XCTAssertTrue(WindowAdmission.isSwitchable(traits("AXStandardWindow", title: false, layer: 3, alpha: 0, size: nil)),
                      "unchanged from before: standard windows need nothing else")
    }

    func testDialogsNeedATitle() {
        XCTAssertTrue(WindowAdmission.isSwitchable(traits("AXDialog")))
        XCTAssertFalse(WindowAdmission.isSwitchable(traits("AXDialog", title: false)))
    }

    func testTitledNormalUnknownWindowsCount() {
        // A Wine/CrossOver window that draws its own frame.
        XCTAssertTrue(WindowAdmission.isSwitchable(traits("AXUnknown")))
        XCTAssertTrue(WindowAdmission.isSwitchable(traits("AXUnknown", layer: nil, alpha: nil)),
                      "off-screen windows have no window-server data; size from AX is enough")
    }

    func testUnknownWindowsThatLookLikeOverlaysAreSkipped() {
        XCTAssertFalse(WindowAdmission.isSwitchable(traits("AXUnknown", title: false)))
        XCTAssertFalse(WindowAdmission.isSwitchable(traits("AXUnknown", layer: 25)))
        XCTAssertFalse(WindowAdmission.isSwitchable(traits("AXUnknown", alpha: 0)))
        XCTAssertFalse(WindowAdmission.isSwitchable(traits("AXUnknown", size: Size(width: 99, height: 600))))
        XCTAssertFalse(WindowAdmission.isSwitchable(traits("AXUnknown", size: Size(width: 800, height: 49))))
        XCTAssertFalse(WindowAdmission.isSwitchable(traits("AXUnknown", size: nil)))
    }

    func testMinimumSizeIsInclusive() {
        XCTAssertTrue(WindowAdmission.isSwitchable(traits("AXUnknown", size: WindowAdmission.minimumUnknownSize)))
    }

    func testOtherSubrolesAndRolesNeverCount() {
        for subrole in ["AXFloatingWindow", "AXSystemDialog", "AXSystemFloatingWindow", "AXSheet", "AXTooltip", nil] {
            XCTAssertFalse(WindowAdmission.isSwitchable(traits(subrole)), "\(String(describing: subrole))")
        }
        XCTAssertFalse(WindowAdmission.isSwitchable(traits("AXStandardWindow", role: "AXSheet")))
        XCTAssertFalse(WindowAdmission.isSwitchable(traits("AXStandardWindow", role: nil)))
    }

    func testDiagnosticLabelsNeverCarryAppSpecificText() {
        XCTAssertEqual(WindowAdmission.label(for: "AXFloatingWindow"), "AXFloatingWindow")
        XCTAssertEqual(WindowAdmission.label(for: nil), "none")
        XCTAssertEqual(WindowAdmission.label(for: ""), "none")
        XCTAssertEqual(WindowAdmission.label(for: "MyCompanySecretPanel"), "other")
        XCTAssertEqual(WindowAdmission.label(for: "AX Custom 1"), "other")
        XCTAssertEqual(WindowAdmission.label(for: "AX" + String(repeating: "x", count: 60)), "other")
    }
}
