import SwiftUI
import Combine
#if os(iOS)
import FamilyControls
import ManagedSettings
#endif

// MARK: - Focus lock

/// Two layered ways to keep the user in a focus session:
///
///   1. SOFT LOCK (always on, no entitlement): we watch the scene phase. If the
///      app is backgrounded mid-session, that's a "bail" — the UI warns and the
///      caller voids the reward / streak credit. iOS still lets them switch
///      apps; this is honour-system accountability (Forest's original model).
///
///   2. REAL SHIELD (opt-in, needs the com.apple.developer.family-controls
///      entitlement + a real device): Apple's Screen Time API actually blocks
///      the apps the user picked until the session ends. Compiled in only when
///      FamilyControls is available, and every call no-ops gracefully if the
///      user hasn't authorized or hasn't picked any apps.
///
/// There is deliberately NO "silence all notifications" switch: iOS gives apps
/// no API to toggle Do Not Disturb / system Focus. The shield removes the
/// temptation, which is what the feature is actually for.
@MainActor
final class FocusLockManager: ObservableObject {
    static let shared = FocusLockManager()

    /// Master switch for the in-app soft lock (warn + void on leave).
    @AppStorage("focus.softLock") var softLockEnabled = true
    /// Whether to also apply the real OS-level shield (needs authorization).
    @AppStorage("focus.shieldApps") var shieldEnabled = false

    /// Set true the moment the user leaves a live session; the session UI
    /// reads it to decide whether the run still counts.
    @Published private(set) var didLeaveDuringSession = false

    private var sessionActive = false

    #if os(iOS)
    private let store = ManagedSettingsStore(named: .init("mito.focus"))
    #endif

    private init() {}

    // MARK: Session lifecycle

    /// Call when a focus session begins.
    func beginSession() {
        sessionActive = true
        didLeaveDuringSession = false
        applyShield()
    }

    /// Call when a focus session ends (completed or abandoned).
    func endSession() {
        sessionActive = false
        clearShield()
    }

    /// Driven by the session view's scenePhase. A background transition during a
    /// live session is a bail.
    func scenePhaseChanged(to phase: ScenePhase) {
        guard sessionActive, softLockEnabled else { return }
        if phase == .background || phase == .inactive {
            didLeaveDuringSession = true
        }
    }

    // MARK: Real shield (Family Controls)

    /// Whether the OS-level shield can actually run right now (entitled,
    /// authorized, and apps were chosen). Drives whether settings shows it.
    var shieldAvailable: Bool {
        #if os(iOS)
        return AuthorizationCenter.shared.authorizationStatus == .approved
        #else
        return false
        #endif
    }

    /// Ask for Screen Time authorization (no-op if already decided). Safe to
    /// call from a settings toggle; fails quietly in the Simulator.
    func requestShieldAuthorization() {
        #if os(iOS)
        Task {
            try? await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        }
        #endif
    }

    private func applyShield() {
        #if os(iOS)
        guard shieldEnabled, shieldAvailable else { return }
        let selection = FocusBlockSelection.load()
        let apps = selection.applicationTokens
        let categories = selection.categoryTokens
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = categories.isEmpty
            ? nil
            : .specific(categories)
        #endif
    }

    private func clearShield() {
        #if os(iOS)
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        #endif
    }
}

// MARK: - Persisted app selection

#if os(iOS)
/// Stores the user's chosen apps/categories (opaque tokens — iOS hides real
/// app identities for privacy) as encoded data in UserDefaults.
enum FocusBlockSelection {
    private static let key = "focus.blockSelection"

    static func load() -> FamilyActivitySelection {
        guard let data = UserDefaults.standard.data(forKey: key),
              let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return sel
    }

    static func save(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Count of chosen apps + categories, for the settings summary line.
    static func count() -> Int {
        let s = load()
        return s.applicationTokens.count + s.categoryTokens.count
    }
}
#endif
