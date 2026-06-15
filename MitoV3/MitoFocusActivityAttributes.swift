import ActivityKit
import Foundation

struct MitoFocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var remainingDue: Int
        var streakSafe: Bool
        var message: String
    }

    var modeLabel: String
    var buddyName: String
    var buddyAsset: String
    var startedAt: Date
    var targetSeconds: Int
}
