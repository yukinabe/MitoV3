import UIKit

/// Lightweight haptic feedback wrapper. Generators are kept warm and reused so
/// the taps are low-latency. Safe to call from anywhere on the main thread.
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notify = UINotificationFeedbackGenerator()

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "audio.haptics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "audio.haptics") }
    }

    /// Call when a screen that uses haptics appears, to minimize first-tap latency.
    static func warm() {
        guard enabled else { return }
        [light, medium, heavy, rigid, soft].forEach { $0.prepare() }
        selection.prepare()
    }

    static func tap() { impact(light, intensity: 0.7) }
    static func select() { guard enabled else { return }; selection.selectionChanged() }
    static func hit() { impact(heavy, intensity: 1.0) }
    static func skill() { impact(medium, intensity: 0.9) }
    static func crit() { impact(rigid, intensity: 1.0) }
    static func support() { impact(soft, intensity: 0.8) }
    static func success() { guard enabled else { return }; notify.notificationOccurred(.success) }
    static func warning() { guard enabled else { return }; notify.notificationOccurred(.warning) }

    private static func impact(_ gen: UIImpactFeedbackGenerator, intensity: CGFloat) {
        guard enabled else { return }
        gen.impactOccurred(intensity: intensity)
        gen.prepare() // ready for the next one
    }
}
