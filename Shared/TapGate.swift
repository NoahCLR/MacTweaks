import Foundation

/// Everything the "should this tap be running?" decision depends on. Extracted so
/// the gating ladder — which the keyboard-tap controllers used to copy verbatim —
/// is a pure function, testable without a live tap or real permissions.
struct TapGateFacts {
    let masterEnabled: Bool
    /// The controller's own feature toggle (e.g. Backspace-to-Trash, or
    /// paste-as-file || cut-files).
    let featureEnabled: Bool
    let accessibilityTrusted: Bool
}

/// What to do with a tap after reconciling settings + permissions.
enum TapGateDecision: Equatable {
    /// Tear the tap down.
    case disable
    /// Bring the tap up (Accessibility is already trusted).
    case enable
}

enum TapGate {
    /// Decides a tap's target state. Pure — see `TapGateFacts`. The executor
    /// (`reconcile`) performs the side effects.
    static func decide(_ facts: TapGateFacts) -> TapGateDecision {
        guard facts.masterEnabled, facts.featureEnabled else { return .disable }
        guard facts.accessibilityTrusted else { return .disable }
        return .enable
    }
}
