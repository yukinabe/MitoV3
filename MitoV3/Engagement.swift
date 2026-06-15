import SwiftUI
import UserNotifications
import WidgetKit

// MARK: - Day helpers

/// Local-calendar day stamps ("2026-06-09") so streaks and daily quests roll
/// over at the user's midnight, not UTC's.
enum StudyDay {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func stamp(_ date: Date = Date()) -> String {
        formatter.string(from: date)
    }

    /// Whole calendar days from stamp `a` to stamp `b` (positive if b is later).
    static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let da = formatter.date(from: a), let db = formatter.date(from: b) else { return nil }
        return Calendar.current.dateComponents([.day], from: da, to: db).day
    }
}

// MARK: - Streaks

/// Daily study streak: one qualifying study activity per local day keeps the
/// fire alive (a completed focus session of 5+ minutes, or finishing the due
/// review queue). Streak freezes — bought with gold — each cover one fully
/// missed day, consumed automatically on the next launch.
@MainActor
final class StreakStore: ObservableObject {
    static let shared = StreakStore()
    static let freezeCostGold = 200
    static let maxFreezes = 2

    @Published private(set) var count: Int
    @Published private(set) var best: Int
    @Published private(set) var freezes: Int
    @Published private(set) var lastActiveDay: String

    private let defaults = UserDefaults.standard

    private init() {
        count = defaults.integer(forKey: "streak.count")
        best = defaults.integer(forKey: "streak.best")
        freezes = defaults.integer(forKey: "streak.freezes")
        lastActiveDay = defaults.string(forKey: "streak.lastDay") ?? ""
    }

    var isActiveToday: Bool { lastActiveDay == StudyDay.stamp() }

    /// Settle missed days: each fully missed day eats a freeze; if the freezes
    /// run out, the streak resets. Call on launch/foreground so the home
    /// screen never shows a stale flame.
    func reconcile(now: Date = Date()) {
        guard count > 0, !lastActiveDay.isEmpty,
              let gap = StudyDay.daysBetween(lastActiveDay, StudyDay.stamp(now)),
              gap >= 2 else { return }
        let missed = gap - 1
        if missed <= freezes {
            freezes -= missed
            // Freezes bridged the gap — treat yesterday as covered so studying
            // today extends the streak instead of restarting it.
            if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) {
                lastActiveDay = StudyDay.stamp(yesterday)
            }
        } else {
            count = 0
        }
        save()
    }

    /// Credit today's qualifying study activity (idempotent per day).
    func registerActivity(now: Date = Date()) {
        reconcile(now: now)
        let today = StudyDay.stamp(now)
        guard lastActiveDay != today else { return }
        let gap = StudyDay.daysBetween(lastActiveDay, today)
        count = (count > 0 && gap == 1) ? count + 1 : 1
        best = max(best, count)
        lastActiveDay = today
        save()
        NotificationManager.shared.reschedule()
        WidgetBridge.sync()
    }

    /// Add one bought freeze. Returns false at the cap (caller keeps the gold).
    @discardableResult
    func addFreeze() -> Bool {
        guard freezes < Self.maxFreezes else { return false }
        freezes += 1
        save()
        return true
    }

    private func save() {
        defaults.set(count, forKey: "streak.count")
        defaults.set(best, forKey: "streak.best")
        defaults.set(freezes, forKey: "streak.freezes")
        defaults.set(lastActiveDay, forKey: "streak.lastDay")
    }

    /// Wipe streak state (account deletion / privacy).
    func reset() {
        count = 0; best = 0; freezes = 0; lastActiveDay = ""
        save()
        WidgetBridge.sync()
    }
}

// MARK: - Daily quests

/// The daily triad: one focus session, ten card reviews, one battle win.
/// Completing all three unlocks a chest (claimed once per day). Rolls over at
/// local midnight.
@MainActor
final class DailyQuests: ObservableObject {
    static let shared = DailyQuests()
    static let reviewTarget = 10
    static let chestGold = 60
    static let chestGems = 1

    @Published private(set) var focusDone: Bool
    @Published private(set) var reviewsDone: Int
    @Published private(set) var battleWon: Bool
    @Published private(set) var chestClaimed: Bool
    private var day: String

    private let defaults = UserDefaults.standard

    private init() {
        day = defaults.string(forKey: "quests.day") ?? ""
        focusDone = defaults.bool(forKey: "quests.focus")
        reviewsDone = defaults.integer(forKey: "quests.reviews")
        battleWon = defaults.bool(forKey: "quests.battle")
        chestClaimed = defaults.bool(forKey: "quests.chest")
        rollover()
    }

    /// Reset progress when the local day changes. Call on launch/foreground.
    func rollover(now: Date = Date()) {
        let today = StudyDay.stamp(now)
        guard day != today else { return }
        day = today
        focusDone = false
        reviewsDone = 0
        battleWon = false
        chestClaimed = false
        save()
    }

    func noteFocusCompleted() {
        rollover()
        guard !focusDone else { return }
        focusDone = true
        save()
        WidgetBridge.sync()
    }

    func noteCardReviewed() {
        rollover()
        guard reviewsDone < Self.reviewTarget else { return }
        reviewsDone += 1
        save()
    }

    func noteBattleWon() {
        rollover()
        guard !battleWon else { return }
        battleWon = true
        save()
    }

    var completedCount: Int {
        (focusDone ? 1 : 0) + (reviewsDone >= Self.reviewTarget ? 1 : 0) + (battleWon ? 1 : 0)
    }
    var allDone: Bool { completedCount == 3 }
    var chestReady: Bool { allDone && !chestClaimed }

    /// Mark the chest claimed. Returns false if it wasn't claimable; the
    /// caller pays out the gold/gems on true.
    @discardableResult
    func claimChest() -> Bool {
        rollover()
        guard chestReady else { return false }
        chestClaimed = true
        save()
        return true
    }

    private func save() {
        defaults.set(day, forKey: "quests.day")
        defaults.set(focusDone, forKey: "quests.focus")
        defaults.set(reviewsDone, forKey: "quests.reviews")
        defaults.set(battleWon, forKey: "quests.battle")
        defaults.set(chestClaimed, forKey: "quests.chest")
    }

    /// Wipe daily-quest state (account deletion / privacy).
    func reset() {
        day = ""; focusDone = false; reviewsDone = 0; battleWon = false; chestClaimed = false
        save()
        WidgetBridge.sync()
    }
}

// MARK: - Due-count helper

extension ReviewSession {
    /// Cards that will be due (or are still new) by the given moment.
    func dueCount(by date: Date) -> Int {
        allCards().filter { $0.sched.phase == .new || $0.sched.due <= date }.count
    }
}

// MARK: - Local notifications

/// Honest, content-driven nudges, recomputed whenever engagement state
/// changes or the app backgrounds:
///   • default: tomorrow 09:00 — how many cards will be due
///   • optional: hourly due-card nudges while cards are waiting
///   • tonight 20:30 — streak-save, only if the streak is alive and unfed today
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    static let cadenceKey = "notif.dueCadence"

    enum DueCadence: String, CaseIterable {
        case daily, hourly, off

        var label: String {
            switch self {
            case .daily: "DAILY"
            case .hourly: "HOURLY"
            case .off: "OFF"
            }
        }
    }

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    /// Drives the in-app priming screen shown before the OS permission dialog.
    @Published var showPrimer = false

    private init() {}

    /// Called once after the first completed session. Instead of firing the
    /// system dialog directly (a reflexive "Don't Allow" would kill due-card
    /// reminders forever), show our own priming screen first — the actual OS
    /// request only happens if the user opts in there.
    func requestPermissionIfNeeded() {
        guard !defaults.bool(forKey: "notif.requested") else { return }
        showPrimer = true
    }

    /// User tapped "Enable" on the primer → now ask the system.
    func confirmPrimer() {
        defaults.set(true, forKey: "notif.requested")
        showPrimer = false
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { reschedule() }
        }
    }

    /// User declined the primer → don't ask again (they can still enable it in
    /// iOS Settings later).
    func dismissPrimer() {
        defaults.set(true, forKey: "notif.requested")
        showPrimer = false
    }

    /// Replace all pending nudges with fresh ones based on current state.
    func reschedule() {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            center.removeAllPendingNotificationRequests()

            let cal = Calendar.current
            let now = Date()
            let buddy = WidgetBridge.currentBuddy()
            let cadence = DueCadence(rawValue: defaults.string(forKey: Self.cadenceKey) ?? DueCadence.daily.rawValue) ?? .daily

            // Morning review reminder.
            if cadence == .daily,
               let tomorrow9 = cal.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0), matchingPolicy: .nextTime) {
                let due = ReviewSession.shared.dueCount(by: tomorrow9)
                if due > 0 {
                    let content = UNMutableNotificationContent()
                    content.title = buddy.name
                    content.body = due == 1
                        ? "I found 1 card due. Want to clear it together?"
                        : "I found \(due) cards due. Want to clear a few together?"
                    content.sound = .default
                    schedule(id: "mito.due", content: content, at: tomorrow9, calendar: cal)
                }
            }

            if cadence == .hourly {
                let due = ReviewSession.shared.dueCount(by: now)
                if due > 0 {
                    let content = UNMutableNotificationContent()
                    content.title = "\(buddy.name) is waiting"
                    content.body = due == 1
                        ? "One tiny review keeps me company."
                        : "\(due) cards are waiting. One tiny review?"
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: true)
                    center.add(UNNotificationRequest(identifier: "mito.due.hourly", content: content, trigger: trigger))
                }
            }

            // Evening streak save.
            let streak = StreakStore.shared
            if streak.count > 0, !streak.isActiveToday {
                var comps = cal.dateComponents([.year, .month, .day], from: now)
                comps.hour = 20; comps.minute = 30
                if let tonight = cal.date(from: comps), tonight > now {
                    let content = UNMutableNotificationContent()
                    content.title = "🔥 \(streak.count)-day streak on the line"
                    content.body = "\(buddy.name) can help you save it with one quick session."
                    content.sound = .default
                    schedule(id: "mito.streak", content: content, at: tonight, calendar: cal)
                }
            }
        }
    }

    private func schedule(id: String, content: UNNotificationContent, at date: Date, calendar: Calendar) {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

// MARK: - Widget bridge

/// Mirrors the engagement snapshot (streak, due cards, quest progress) into
/// the shared App Group container the home-screen widget reads, then asks
/// WidgetKit to redraw. Call after anything the widget displays changes.
@MainActor
enum WidgetBridge {
    static let suiteName = "group.com.yukinabe.mitov3"

    struct Buddy {
        let id: String
        let name: String
        let asset: String
    }

    static func currentBuddy() -> Buddy {
        let preferred = UserDefaults.standard.string(forKey: "study.companion")
            ?? BattleRules.partyHeroes.first?.id
            ?? RosterStore.starter
        let hero = DataSet.anyHero(id: preferred) ?? DataSet.anyHero(id: RosterStore.starter)
        return Buddy(
            id: hero?.id ?? RosterStore.starter,
            name: hero?.name ?? "Mito",
            asset: hero?.asset ?? "hero-mito-hop"
        )
    }

    static func sync() {
        guard let d = UserDefaults(suiteName: suiteName) else { return }
        let now = Date()
        let dueCards = ReviewSession.shared.allCards()
            .filter { $0.sched.phase == .new || $0.sched.due <= now }
            .sorted { lhs, rhs in
                if (lhs.sched.phase == .new) != (rhs.sched.phase == .new) {
                    return rhs.sched.phase == .new
                }
                return lhs.sched.due < rhs.sched.due
            }
        let buddy = currentBuddy()
        let dueCount = dueCards.count
        let mood = mood(due: dueCount, activeToday: StreakStore.shared.isActiveToday, questsDone: DailyQuests.shared.completedCount, now: now)
        d.set(StreakStore.shared.count, forKey: "widget.streak")
        d.set(StreakStore.shared.isActiveToday, forKey: "widget.activeToday")
        d.set(dueCount, forKey: "widget.due")
        d.set(DailyQuests.shared.completedCount, forKey: "widget.quests")
        d.set(buddy.id, forKey: "widget.buddy.id")
        d.set(buddy.name, forKey: "widget.buddy.name")
        d.set(buddy.asset, forKey: "widget.buddy.asset")
        d.set(mood.label, forKey: "widget.buddy.mood")
        d.set(mood.line, forKey: "widget.buddy.line")
        d.set(now.timeIntervalSince1970, forKey: "widget.syncedAt")
        if let card = dueCards.first {
            d.set(card.id.uuidString, forKey: "widget.card.id")
            d.set(card.deckName.isEmpty ? card.deckID : card.deckName, forKey: "widget.card.deck")
            d.set(card.front, forKey: "widget.card.front")
            d.set(card.back, forKey: "widget.card.back")
        } else {
            d.removeObject(forKey: "widget.card.id")
            d.removeObject(forKey: "widget.card.deck")
            d.removeObject(forKey: "widget.card.front")
            d.removeObject(forKey: "widget.card.back")
            d.removeObject(forKey: "widget.card.revealed")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func mood(due: Int, activeToday: Bool, questsDone: Int, now: Date) -> (label: String, line: String) {
        if due > 0, !activeToday, StreakStore.shared.count > 0 {
            return ("worried", "I saved a card for us.")
        }
        if due > 0 {
            return ("waiting", "One card together?")
        }
        if activeToday || questsDone >= 3 {
            return ("proud", "I'm proud of today.")
        }
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 21 || hour < 7 {
            return ("sleepy", "Resting till review time.")
        }
        return ("relaxed", "No cards due. I'm chilling.")
    }
}

// MARK: - Post-session share card

/// The pixel-art session summary rendered to an image for the share sheet —
/// sized for stories (9:16), drawn over the meadow with the lead hero.
struct SessionShareCard: View {
    let minutes: Int
    let atp: Int
    let streak: Int
    let modeLabel: String

    private var heroAsset: String {
        BattleRules.partyHeroes.first?.asset ?? "hero-mito-hop"
    }

    private var dateText: String {
        Date().formatted(.dateTime.month(.wide).day().year())
    }

    var body: some View {
        ZStack {
            Image("meadow-bg")
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .frame(width: 300, height: 533)
                .clipped()
            Color(hex: "1A1009").opacity(0.55)

            VStack(spacing: 16) {
                Text("MITO")
                    .pixelText(size: 24, color: Color(hex: "F7C943"))
                    .padding(.top, 30)
                Image(heroAsset)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                VStack(spacing: 6) {
                    Text("\(minutes) MIN")
                        .pixelText(size: 30, color: Color(hex: "F4E6C0"))
                    Text("FOCUSED · \(modeLabel)")
                        .pixelText(size: 10, color: Color(hex: "F4E6C0").opacity(0.8))
                }
                HStack(spacing: 12) {
                    statChip("⚡ +\(atp) ATP")
                    statChip("🔥 \(streak) DAY\(streak == 1 ? "" : "S")")
                }
                Spacer()
                Text(dateText)
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(Color(hex: "F4E6C0").opacity(0.75))
                    .padding(.bottom, 24)
            }
            .frame(width: 300, height: 533)
        }
        .frame(width: 300, height: 533)
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 6))
    }

    private func statChip(_ text: String) -> some View {
        Text(text)
            .pixelText(size: 11, color: Color(hex: "F4E6C0"))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(hex: "1A1009").opacity(0.85))
            .overlay(Rectangle().stroke(Color(hex: "F7C943"), lineWidth: 2))
    }

    /// Render the card to a shareable image (3× for crisp pixels).
    @MainActor
    static func render(minutes: Int, atp: Int, streak: Int, modeLabel: String) -> Image? {
        let renderer = ImageRenderer(content: SessionShareCard(
            minutes: minutes, atp: atp, streak: streak, modeLabel: modeLabel))
        renderer.scale = 3
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}
