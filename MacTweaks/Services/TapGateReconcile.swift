import Foundation

extension TapGate {
    /// Applies the gate decision: tears the tap down, brings it up, or runs the
    /// one-shot Input-Monitoring request then brings it up. The request dance — set
    /// the flag, prompt once, enable-or-disable on the result — lives here so the
    /// keyboard-tap controllers don't each copy it.
    ///
    /// `enable` brings the tap up and returns whether it is running; `disable` tears
    /// it down (a controller may do more than `tap.disable()` — e.g. the fallback
    /// clears its transient menu state). `onEnableFailure` fires when a tap that
    /// should come up can't.
    @discardableResult
    static func reconcile(
        facts: TapGateFacts,
        didRequestInput: inout Bool,
        requestInput: () -> Bool,
        enable: () -> Bool,
        disable: () -> Void,
        onEnableFailure: () -> Void
    ) -> TapGateDecision {
        let decision = decide(facts)
        switch decision {
        case .disable:
            disable()
        case .enable:
            if !enable() { onEnableFailure() }
        case .requestInputThenEnable:
            didRequestInput = true
            if requestInput() {
                _ = enable()
            } else {
                disable()
            }
        }
        return decision
    }

    /// Convenience for taps whose teardown is exactly `tap.disable()` and that need
    /// Input Monitoring (the keyboard taps).
    @discardableResult
    static func reconcile(
        facts: TapGateFacts,
        tap: EventTap,
        didRequestInput: inout Bool,
        requestInput: () -> Bool,
        onEnableFailure: () -> Void
    ) -> TapGateDecision {
        reconcile(
            facts: facts,
            didRequestInput: &didRequestInput,
            requestInput: requestInput,
            enable: { tap.enable() },
            disable: { tap.disable() },
            onEnableFailure: onEnableFailure
        )
    }

    /// Convenience for taps that never need Input Monitoring (Accessibility only,
    /// e.g. the right-click fallback) and may have custom teardown. The request
    /// rung is unreachable when `facts.requiresInputMonitoring` is false.
    @discardableResult
    static func reconcile(
        facts: TapGateFacts,
        enable: () -> Bool,
        disable: () -> Void,
        onEnableFailure: () -> Void = {}
    ) -> TapGateDecision {
        var unusedRequestFlag = false
        return reconcile(
            facts: facts,
            didRequestInput: &unusedRequestFlag,
            requestInput: { false },
            enable: enable,
            disable: disable,
            onEnableFailure: onEnableFailure
        )
    }
}
