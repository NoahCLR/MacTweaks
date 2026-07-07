import XCTest

final class TapGateTests: XCTestCase {

    private func facts(
        masterEnabled: Bool = true,
        featureEnabled: Bool = true,
        accessibilityTrusted: Bool = true,
        inputMonitoringGranted: Bool = true,
        inputMonitoringAlreadyRequested: Bool = false,
        requiresInputMonitoring: Bool = true
    ) -> TapGateFacts {
        TapGateFacts(
            masterEnabled: masterEnabled,
            featureEnabled: featureEnabled,
            accessibilityTrusted: accessibilityTrusted,
            inputMonitoringGranted: inputMonitoringGranted,
            inputMonitoringAlreadyRequested: inputMonitoringAlreadyRequested,
            requiresInputMonitoring: requiresInputMonitoring
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

    func testAllGrantedEnables() {
        XCTAssertEqual(TapGate.decide(facts()), .enable)
    }

    func testInputMonitoringMissingAndNotYetRequestedRequests() {
        XCTAssertEqual(
            TapGate.decide(facts(inputMonitoringGranted: false, inputMonitoringAlreadyRequested: false)),
            .requestInputThenEnable
        )
    }

    func testInputMonitoringMissingButAlreadyRequestedDisables() {
        XCTAssertEqual(
            TapGate.decide(facts(inputMonitoringGranted: false, inputMonitoringAlreadyRequested: true)),
            .disable
        )
    }

    func testInputMonitoringNotRequiredEnablesWithoutIt() {
        // The right-click fallback's requirement set: Accessibility only.
        XCTAssertEqual(
            TapGate.decide(facts(inputMonitoringGranted: false, inputMonitoringAlreadyRequested: false, requiresInputMonitoring: false)),
            .enable
        )
    }

    func testMissingAccessibilityDisablesEvenWhenInputNotRequired() {
        XCTAssertEqual(
            TapGate.decide(facts(accessibilityTrusted: false, requiresInputMonitoring: false)),
            .disable
        )
    }

    func testFeatureDisabledBeatsMissingAccessibility() {
        // Feature off short-circuits before any permission check.
        XCTAssertEqual(
            TapGate.decide(facts(featureEnabled: false, accessibilityTrusted: false, inputMonitoringGranted: false)),
            .disable
        )
    }
}
