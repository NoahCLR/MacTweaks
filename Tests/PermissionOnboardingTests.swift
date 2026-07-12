import XCTest

final class PermissionOnboardingTests: XCTestCase {
    func testInitializationAndRefreshNeverRequestPermissions() {
        let requests = RequestLog()
        var snapshot = PermissionSnapshot(accessibilityGranted: false, screenCaptureGranted: false)
        let coordinator = makeCoordinator(snapshot: { snapshot }, requests: requests)

        coordinator.refresh()
        snapshot = PermissionSnapshot(accessibilityGranted: true, screenCaptureGranted: false)
        coordinator.refresh()

        XCTAssertEqual(requests.steps, [])
        XCTAssertEqual(
            coordinator.snapshot,
            PermissionSnapshot(accessibilityGranted: true, screenCaptureGranted: false)
        )
    }

    func testExplicitAccessibilityRequestRequestsOnlyAccessibilityOnce() {
        let requests = RequestLog()
        let coordinator = makeCoordinator(requests: requests)

        XCTAssertTrue(coordinator.request(.accessibility))
        XCTAssertFalse(coordinator.request(.accessibility))

        XCTAssertEqual(requests.steps, [.accessibility])
        XCTAssertTrue(coordinator.hasRequested(.accessibility))
        XCTAssertFalse(coordinator.hasRequested(.screenRecording))
    }

    func testExplicitScreenRecordingRequestRequestsOnlyScreenRecordingOnce() {
        let requests = RequestLog()
        let coordinator = makeCoordinator(requests: requests)

        XCTAssertTrue(coordinator.request(.screenRecording))
        XCTAssertFalse(coordinator.request(.screenRecording))

        XCTAssertEqual(requests.steps, [.screenRecording])
        XCTAssertFalse(coordinator.hasRequested(.accessibility))
        XCTAssertTrue(coordinator.hasRequested(.screenRecording))
    }

    func testPermissionsCanBeRequestedInEitherOrder() {
        let requests = RequestLog()
        let coordinator = makeCoordinator(requests: requests)

        XCTAssertTrue(coordinator.request(.screenRecording))
        XCTAssertTrue(coordinator.request(.accessibility))

        XCTAssertEqual(requests.steps, [.screenRecording, .accessibility])
    }

    func testReturnRefreshesStatusWithoutRequestingNextPermission() {
        let requests = RequestLog()
        var snapshot = PermissionSnapshot(accessibilityGranted: false, screenCaptureGranted: false)
        let coordinator = makeCoordinator(snapshot: { snapshot }, requests: requests)

        coordinator.request(.accessibility)
        snapshot = PermissionSnapshot(accessibilityGranted: true, screenCaptureGranted: false)
        coordinator.refresh()

        XCTAssertEqual(requests.steps, [.accessibility])
        XCTAssertTrue(coordinator.snapshot.accessibilityGranted)
        XCTAssertFalse(coordinator.hasRequested(.screenRecording))
    }

    func testReopeningAfterDismissalDoesNotRetryRequest() {
        let requests = RequestLog()
        let coordinator = makeCoordinator(requests: requests)

        coordinator.request(.accessibility)
        // Opening the tab and returning from System Settings both call refresh.
        coordinator.refresh()
        coordinator.refresh()

        XCTAssertEqual(requests.steps, [.accessibility])
        XCTAssertTrue(coordinator.hasRequested(.accessibility))
    }

    func testGrantedPermissionIsNeverRequested() {
        let requests = RequestLog()
        let coordinator = makeCoordinator(
            snapshot: {
                PermissionSnapshot(accessibilityGranted: true, screenCaptureGranted: true)
            },
            requests: requests
        )

        XCTAssertFalse(coordinator.request(.accessibility))
        XCTAssertFalse(coordinator.request(.screenRecording))

        XCTAssertEqual(requests.steps, [])
        XCTAssertEqual(coordinator.requestedSteps, [])
    }

    func testRequestIsRecordedBeforeCallingSystemAPI() {
        var coordinator: PermissionOnboardingCoordinator!
        var wasRecordedBeforeRequest = false
        coordinator = PermissionOnboardingCoordinator(
            readSnapshot: {
                PermissionSnapshot(accessibilityGranted: false, screenCaptureGranted: false)
            },
            requestAccessibility: {
                wasRecordedBeforeRequest = coordinator.hasRequested(.accessibility)
                // Models a second Settings window acting while the system API is
                // synchronously presenting its prompt.
                XCTAssertFalse(coordinator.request(.accessibility))
            },
            requestScreenCapture: {}
        )

        XCTAssertTrue(coordinator.request(.accessibility))

        XCTAssertTrue(wasRecordedBeforeRequest)
    }

    private func makeCoordinator(
        snapshot: @escaping () -> PermissionSnapshot = {
            PermissionSnapshot(accessibilityGranted: false, screenCaptureGranted: false)
        },
        requests: RequestLog
    ) -> PermissionOnboardingCoordinator {
        PermissionOnboardingCoordinator(
            readSnapshot: snapshot,
            requestAccessibility: { requests.steps.append(.accessibility) },
            requestScreenCapture: { requests.steps.append(.screenRecording) }
        )
    }

    private final class RequestLog {
        var steps: [PermissionOnboardingStep] = []
    }
}
