import Foundation

/// Launch-stage feature flags. Centralised so shipping decisions are one edit,
/// not a hunt through the UI.
enum BetaConfig {
    /// The real OS app-shield (Family Controls) needs Apple's restricted
    /// `com.apple.developer.family-controls` entitlement, which is a separate
    /// approval. Keep the "Block apps" settings UI hidden until that's granted;
    /// the in-app soft lock still works. Flip to `true` in v1.1 after approval.
    static let appShieldEnabled = false

    /// Mito+ is free for everyone during the beta — unlock every premium feature
    /// so testers experience the whole product and we get real feedback on it
    /// (there's no payment system yet anyway). The free-tier caps are still
    /// *instrumented* (we log when a tester would have hit one) so we learn
    /// where the friction lands without a wall. Flip to `false` at paid launch
    /// and wire RevenueCat.
    static let premiumFreeForBeta = true

    /// The effective Mito+ state: unlocked for everyone during the beta, else
    /// the real (dev-unlock / future RevenueCat) flag. Every premium gate reads
    /// this so flipping `premiumFreeForBeta` to false at paid launch is one edit.
    static var premiumActive: Bool {
        premiumFreeForBeta || UserDefaults.standard.bool(forKey: "premium.social")
    }
}
