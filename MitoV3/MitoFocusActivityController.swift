import ActivityKit
import Foundation

@MainActor
enum MitoFocusActivityController {
    private static var activity: Activity<MitoFocusActivityAttributes>?
    private static var lastUpdateSecond = -1

    static func start(mode: StudyMode) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endImmediatelyIfNeeded()

        let buddy = WidgetBridge.currentBuddy()
        let attributes = MitoFocusActivityAttributes(
            modeLabel: mode.label,
            buddyName: buddy.name,
            buddyAsset: buddy.asset,
            startedAt: Date(),
            targetSeconds: mode.durationSeconds
        )
        let state = MitoFocusActivityAttributes.ContentState(
            elapsedSeconds: 0,
            remainingDue: ReviewSession.shared.dueCount(by: Date()),
            streakSafe: StreakStore.shared.isActiveToday,
            message: "\(buddy.name) is studying with you"
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastUpdateSecond = 0
        } catch {
            activity = nil
        }
    }

    static func update(elapsed: Int, mode: StudyMode) {
        guard let activity else { return }
        guard elapsed == 0 || elapsed - lastUpdateSecond >= 15 || (!mode.isCountUp && elapsed >= mode.durationSeconds) else {
            return
        }
        lastUpdateSecond = elapsed
        let state = MitoFocusActivityAttributes.ContentState(
            elapsedSeconds: elapsed,
            remainingDue: ReviewSession.shared.dueCount(by: Date()),
            streakSafe: StreakStore.shared.isActiveToday,
            message: message(elapsed: elapsed, mode: mode)
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    static func end(elapsed: Int, mode: StudyMode, completed: Bool) {
        guard let activity else { return }
        let buddy = WidgetBridge.currentBuddy()
        let state = MitoFocusActivityAttributes.ContentState(
            elapsedSeconds: elapsed,
            remainingDue: ReviewSession.shared.dueCount(by: Date()),
            streakSafe: StreakStore.shared.isActiveToday,
            message: completed ? "\(buddy.name) is proud of you" : "\(buddy.name) saved your progress"
        )
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60)))
        }
        self.activity = nil
        lastUpdateSecond = -1
    }

    private static func endImmediatelyIfNeeded() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
        lastUpdateSecond = -1
    }

    private static func message(elapsed: Int, mode: StudyMode) -> String {
        let buddy = WidgetBridge.currentBuddy()
        if !mode.isCountUp {
            let remaining = max(0, mode.durationSeconds - elapsed)
            if remaining <= 60 { return "\(buddy.name) sees the finish line" }
        }
        if ReviewSession.shared.dueCount(by: Date()) > 0 {
            return "\(buddy.name) is guarding your due cards"
        }
        return "\(buddy.name) is keeping watch"
    }
}
