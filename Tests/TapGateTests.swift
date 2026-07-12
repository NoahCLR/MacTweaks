import XCTest

final class TapGateTests: XCTestCase {

    private func facts(
        masterEnabled: Bool = true,
        featureEnabled: Bool = true,
        accessibilityTrusted: Bool = true
    ) -> TapGateFacts {
        TapGateFacts(
            masterEnabled: masterEnabled,
            featureEnabled: featureEnabled,
            accessibilityTrusted: accessibilityTrusted
        )
    }

    func testMasterDisabledDisables() {
        XCTAssertEqual(TapGate.decide(facts(masterEnabled: false)), .disable)
    }

    func testFeatureDisabledDisables() {
        XCTAssertEqual(TapGate.decide(facts(featureEnabled: false)), .disable)
    }

    func testMissingAccessibilityDisables() {
        XCTAssertEqual(TapGate.decide(facts(accessibilityTrusted: false)), .disable)
    }

    func testAccessibilityGrantedEnables() {
        XCTAssertEqual(TapGate.decide(facts()), .enable)
    }

    func testFeatureDisabledBeatsMissingAccessibility() {
        // Feature off short-circuits before any permission check.
        XCTAssertEqual(
            TapGate.decide(facts(featureEnabled: false, accessibilityTrusted: false)),
            .disable
        )
    }
}
