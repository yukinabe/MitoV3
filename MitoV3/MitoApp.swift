import SwiftUI
import CoreText
import PostHog

@main
struct MitoV3App: App {
    init() {
        PostHogManager.shared.configure()
        SubscriptionManager.shared.configure()
        FontRegistrar.registerFonts()
        AudioManager.shared.prepare()
        Haptics.warm()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private enum FontRegistrar {
    static func registerFonts() {
        ["PixelifySans", "Silkscreen-Regular", "Silkscreen-Bold"].forEach { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                return
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Thin, crash-proof wrapper around the PostHog SDK so the rest of the app has a
/// single analytics entry point. Every call is a no-op until `configure()` runs
/// with a valid key, so telemetry can never block launch or break a flow.
final class PostHogManager {
    static let shared = PostHogManager()

    // PostHog project token (a.k.a. "Project API Key") — a client/write-only
    // key, safe to ship in the binary. PostHog → Settings → Project.
    private static let projectToken = "phc_yTSYiqXmqNnhpXzYW8Zxy5P3LybQuREtrMBio6CFfQtk"
    // US Cloud: https://us.i.posthog.com · EU Cloud: https://eu.i.posthog.com
    private static let host = "https://us.i.posthog.com"

    private var started = false
    private var identifiedID: String?

    private init() {}

    func configure() {
        guard !started, Self.projectToken.hasPrefix("phc_") else { return }
        let config = PostHogConfig(projectToken: Self.projectToken, host: Self.host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = true

        // Session Replay. MitoV3 is SwiftUI, which needs screenshot mode (the
        // default wireframe replay only renders UIKit). Text inputs and images
        // are masked by default, so user content is never recorded.
        config.sessionReplay = true
        config.sessionReplayConfig.screenshotMode = true

        // Feature flags are preloaded on startup by default (preloadFeatureFlags),
        // so PostHogManager.isFeatureEnabled(_:) works right after launch.

        PostHogSDK.shared.setup(config)
        started = true
    }

    func capture(_ event: String, props: [String: String] = [:]) {
        guard started else { return }
        PostHogSDK.shared.capture(event, properties: props)
    }

    /// Gradual rollouts / kill-switches. Returns false until flags have loaded.
    func isFeatureEnabled(_ key: String) -> Bool {
        guard started else { return false }
        return PostHogSDK.shared.isFeatureEnabled(key)
    }

    /// Associates events with a stable user id. Cheap to call repeatedly —
    /// only the first call per id actually hits the SDK.
    func identifyOnce(_ id: String) {
        guard started, identifiedID != id else { return }
        identifiedID = id
        PostHogSDK.shared.identify(id)
    }

    /// Call on sign-out so subsequent events get a fresh anonymous id.
    func reset() {
        guard started else { return }
        identifiedID = nil
        PostHogSDK.shared.reset()
    }
}
