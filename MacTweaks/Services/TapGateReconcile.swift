import Foundation

extension TapGate {
    /// Applies the gate decision by tearing the tap down or bringing it up.
    ///
    /// `enable` brings the tap up and returns whether it is running; `disable` tears
    /// it down (a controller may do more than `tap.disable()` — e.g. the fallback
    /// clears its transient menu state). `onEnableFailure` fires when a tap that
    /// should come up can't.
    @discardableResult
    static func reconcile(
        facts: TapGateFacts,
        enable: () -> Bool,
        disable: () -> Void,
        onEnableFailure: () -> Void = {}
    ) -> TapGateDecision {
        let decision = decide(facts)
        switch decision {
        case .disable:
            disable()
        case .enable:
            if !enable() { onEnableFailure() }
        }
        return decision
    }

    /// Convenience for taps whose teardown is exactly `tap.disable()`.
    @discardableResult
    static func reconcile(
        facts: TapGateFacts,
        tap: EventTap,
        onEnableFailure: () -> Void
    ) -> TapGateDecision {
        reconcile(
            facts: facts,
            enable: { tap.enable() },
            disable: { tap.disable() },
            onEnableFailure: onEnableFailure
        )
    }
}
