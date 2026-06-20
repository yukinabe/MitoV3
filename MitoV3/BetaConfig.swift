import Foundation

/// Launch-stage feature flags. Centralised so shipping decisions are one edit,
/// not a hunt through the UI.
enum BetaConfig {
    /// The real OS app-shield (Family Controls) needs Apple's restricted
    /// `com.apple.developer.family-controls` entitlement, which is a separate
    /// approval. Keep the "Block apps" settings UI hidden until that's granted;
    /// the in-app soft lock still works. Flip to `true` in v1.1 after approval.
    static let appShieldEnabled = false

    /// Set this to true only for a deliberately free TestFlight cohort.
    /// Production access comes from the RevenueCat "Mito Pro" entitlement.
    static let premiumFreeForBeta = false

    /// The effective Mito+ state: unlocked for everyone during the beta, else
    /// RevenueCat is the single source of truth for paid access.
    @MainActor static var premiumActive: Bool {
        premiumFreeForBeta || SubscriptionManager.shared.isPro
    }
}
