import SwiftUI

struct HomeScreen: View {
    @Binding var atp: Int
    @Binding var gold: Int
    @Binding var gems: Int
    @ObservedObject var backend: MitoBackend
    @State private var showPicker = false
    @State private var sessionMode: StudyMode?
    @State private var showingSettings = false
    @State private var showingAuth = false
    @State private var showingFriends = false
    @State private var showingClasses = false
    @State private var showingStreak = false
    @State private var showingQuests = false
    @ObservedObject private var lobby = LobbyService.shared
    @ObservedObject private var streak = StreakStore.shared
    @ObservedObject private var quests = DailyQuests.shared
    @ObservedObject private var party = PartyStore.shared
    @AppStorage("settings.animations") private var animationsEnabled = true

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("meadow-bg")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                // Hidden while a focus session is active so their wander tasks
                // pause and the session's own characters own the registry.
                if sessionMode == nil && animationsEnabled {
                    ForEach(StudyWanderer.forActiveTeam()) { wanderer in
                        StudyWanderingCharacter(wanderer: wanderer, canvasSize: proxy.size)
                    }
                    // Co-op: a friend's team wanders your meadow while you're in a lobby.
                    ForEach(StudyWanderer.forLobbyGuests(lobby.members, myUserID: lobby.myUserID)) { wanderer in
                        StudyWanderingCharacter(wanderer: wanderer, canvasSize: proxy.size)
                    }
                }

                VStack {
                    HStack(spacing: 8) {
                        Button {
                            showingStreak = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("🔥").font(.system(size: 14))
                                Text("\(streak.count)")
                                    .pixelText(size: 13, color: streak.isActiveToday ? Color(hex: "F7C943") : Color(hex: "F4E6C0"))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(Color(hex: "1A1009").opacity(0.82))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Streak: \(streak.count) days")

                        Button {
                            showingQuests = true
                        } label: {
                            HStack(spacing: 5) {
                                Text("DAILY")
                                    .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                                Text("\(quests.completedCount)/3")
                                    .pixelText(size: 11, color: quests.chestReady ? Color(hex: "F7C943") : Color(hex: "F4E6C0"))
                                if quests.chestReady {
                                    Text("!").pixelText(size: 12, color: Color(hex: "F7C943"))
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(Color(hex: "1A1009").opacity(0.82))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Daily quests: \(quests.completedCount) of 3 done")

                        Spacer()
                        Button {
                            showingClasses = true
                        } label: {
                            Image(systemName: "graduationcap.fill")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(Color(hex: "F4E6C0"))
                                .frame(width: 38, height: 34)
                                .background(Color(hex: "4A8A3C"))
                                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Classes")

                        Button {
                            showingFriends = true
                        } label: {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(Color(hex: "F4E6C0"))
                                .frame(width: 38, height: 34)
                                .background(Color(hex: "4A7BA8"))
                                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Friends")

                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(Color(hex: "F4E6C0"))
                                .frame(width: 38, height: 34)
                                .background(Color(hex: "6B4324"))
                                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")
                    }
                    .padding(.top, 10)
                    .padding(.leading, 16)
                    .padding(.trailing, 28)
                    Spacer()
                }
                .zIndex(2)

                VStack {
                    Spacer()
                    if showPicker {
                        ModePickerPanel(
                            close: {
                                withAnimation(.easeOut(duration: 0.18)) { showPicker = false }
                            },
                            start: { mode in
                                showPicker = false
                                sessionMode = mode
                                Task { await backend.logEvent("study_start", props: ["mode": mode.rawValue]) }
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                showPicker = true
                            }
                        } label: {
                            Image("study-btn")
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                        }
                        .buttonStyle(.plain)
                        .frame(width: min(330, proxy.size.width * 0.88))
                        .padding(.bottom, 12)
                    }
                }

                if showPicker {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.18)) {
                                showPicker = false
                            }
                        }
                        .zIndex(-1)
                }

                if showingSettings {
                    Color.black.opacity(0.58)
                        .ignoresSafeArea()
                        .zIndex(4)

                    GeneralSettingsSheet(
                        backend: backend,
                        isPresented: $showingSettings,
                        showAuth: {
                            showingSettings = false
                            showingAuth = true
                        }
                    )
                    .frame(width: min(proxy.size.width * 0.86, 360))
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.38)
                    .zIndex(5)
                }

                if showingAuth {
                    Color.black.opacity(0.64)
                        .ignoresSafeArea()
                        .zIndex(6)

                    AuthSheet(backend: backend, isPresented: $showingAuth)
                        .frame(width: min(proxy.size.width * 0.86, 360))
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
                        .zIndex(7)
                }

                if showingFriends {
                    FriendsView(backend: backend, isPresented: $showingFriends)
                        .zIndex(8)
                        .transition(.opacity)
                }

                if showingClasses {
                    ClassesView(backend: backend, isPresented: $showingClasses)
                        .zIndex(8)
                        .transition(.opacity)
                }

                if showingStreak {
                    Color.black.opacity(0.58)
                        .ignoresSafeArea()
                        .zIndex(9)
                        .onTapGesture { showingStreak = false }
                    StreakSheet(gold: $gold, isPresented: $showingStreak)
                        .frame(width: min(proxy.size.width * 0.86, 360))
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.40)
                        .zIndex(10)
                }

                if showingQuests {
                    Color.black.opacity(0.58)
                        .ignoresSafeArea()
                        .zIndex(9)
                        .onTapGesture { showingQuests = false }
                    DailyQuestSheet(gold: $gold, gems: $gems, isPresented: $showingQuests)
                        .frame(width: min(proxy.size.width * 0.86, 360))
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.40)
                        .zIndex(10)
                }
            }
            .fullScreenCover(item: $sessionMode) { mode in
                FocusSession(mode: mode, presented: $sessionMode) { reward, seconds, completed in
                    atp += reward
                    Task {
                        try? await backend.recordStudySession(
                            mode: mode.rawValue,
                            durationMinutes: max(0, seconds / 60),
                            completed: completed,
                            focusEnergy: reward,
                            coins: 0,
                            gems: 0
                        )
                        await backend.logEvent("study_end", props: [
                            "mode": mode.rawValue,
                            "seconds": "\(seconds)",
                            "atp": "\(reward)"
                        ])
                    }
                }
            }
        }
    }
}

// MARK: - Streak sheet

struct StreakSheet: View {
    @Binding var gold: Int
    @Binding var isPresented: Bool
    @ObservedObject private var streak = StreakStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("STREAK")
                    .pixelText(size: 17, color: Color(hex: "3A2A18"))
                Spacer()
                Button { isPresented = false } label: {
                    Text("X")
                        .pixelText(size: 13, color: Color(hex: "3A2A18"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Text("🔥").font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streak.count) DAY\(streak.count == 1 ? "" : "S")")
                        .pixelText(size: 20, color: Color(hex: "3A2A18"))
                    Text(streak.isActiveToday
                         ? "Today is in the bag."
                         : "Study today to keep it alive.")
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
                }
            }

            Text("BEST: \(streak.best) · FREEZES: \(streak.freezes)/\(StreakStore.maxFreezes)")
                .pixelText(size: 9, color: Color(hex: "6B4324"))

            Text("A freeze covers one fully missed day so your streak survives.")
                .font(.custom(MitoFont.regular, size: 13))
                .foregroundStyle(Color(hex: "6B4324"))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard streak.freezes < StreakStore.maxFreezes,
                      gold >= StreakStore.freezeCostGold else { return }
                if streak.addFreeze() {
                    gold -= StreakStore.freezeCostGold
                    Haptics.success()
                }
            } label: {
                Text(streak.freezes >= StreakStore.maxFreezes
                     ? "FREEZES FULL"
                     : "BUY FREEZE · \(StreakStore.freezeCostGold) GOLD")
                    .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canBuyFreeze ? Color(hex: "4A7BA8") : Color(hex: "8A8A70"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
            .disabled(!canBuyFreeze)
        }
        .padding(16)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }

    private var canBuyFreeze: Bool {
        streak.freezes < StreakStore.maxFreezes && gold >= StreakStore.freezeCostGold
    }
}

// MARK: - Daily quest sheet

struct DailyQuestSheet: View {
    @Binding var gold: Int
    @Binding var gems: Int
    @Binding var isPresented: Bool
    @ObservedObject private var quests = DailyQuests.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("DAILY QUESTS")
                    .pixelText(size: 17, color: Color(hex: "3A2A18"))
                Spacer()
                Button { isPresented = false } label: {
                    Text("X")
                        .pixelText(size: 13, color: Color(hex: "3A2A18"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            questRow(done: quests.focusDone,
                     title: "Complete a focus session",
                     detail: "5+ minutes in any mode")
            questRow(done: quests.reviewsDone >= DailyQuests.reviewTarget,
                     title: "Review \(DailyQuests.reviewTarget) cards",
                     detail: "\(min(quests.reviewsDone, DailyQuests.reviewTarget))/\(DailyQuests.reviewTarget) done")
            questRow(done: quests.battleWon,
                     title: "Win a battle",
                     detail: "Clear a stage or an endless wave")

            Button {
                if quests.claimChest() {
                    gold += DailyQuests.chestGold
                    gems += DailyQuests.chestGems
                    Haptics.success()
                    AudioManager.shared.play(.reward)
                }
            } label: {
                Text(chestLabel)
                    .pixelText(size: 11, color: Color(hex: quests.chestReady ? "18100A" : "F4E6C0"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(quests.chestReady ? Color(hex: "F7C943") : Color(hex: "8A8A70"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
            .disabled(!quests.chestReady)
        }
        .padding(16)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }

    private var chestLabel: String {
        if quests.chestClaimed { return "CHEST CLAIMED" }
        if quests.chestReady { return "OPEN CHEST · +\(DailyQuests.chestGold) GOLD +\(DailyQuests.chestGems) GEM" }
        return "FINISH ALL 3 TO OPEN THE CHEST"
    }

    private func questRow(done: Bool, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Text(done ? "✓" : "·")
                .pixelText(size: 14, color: done ? Color(hex: "4A8A3C") : Color(hex: "8A6A40"))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom(MitoFont.bold, size: 14))
                    .foregroundStyle(Color(hex: "3A2A18"))
                Text(detail)
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "6B4324"))
            }
            Spacer()
        }
        .padding(10)
        .background(Color(hex: "F4E6C0").opacity(done ? 0.55 : 1))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }
}

enum StudyMode: String, CaseIterable, Identifiable {
    case focus
    case deepFocus
    case countUp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focus: "FOCUS"
        case .deepFocus: "DEEP FOCUS"
        case .countUp: "COUNT UP"
        }
    }

    var subtitle: String {
        switch self {
        case .focus: "25 minute sprint"
        case .deepFocus: "50 minute deep work"
        case .countUp: "Open · 5 min – 2 hr"
        }
    }

    /// Reward chip shown on the picker.
    var rewardLabel: String {
        switch self {
        case .focus: "+12 ATP"
        case .deepFocus: "+25 ATP"
        case .countUp: "UP TO +60"
        }
    }

    var isCountUp: Bool { self == .countUp }

    /// Target length for countdown modes (ignored by count-up).
    var durationSeconds: Int {
        switch self {
        case .focus: 25 * 60
        case .deepFocus: 50 * 60
        case .countUp: 0
        }
    }

    /// ATP awarded for a given amount of studied time — proportional at
    /// ~0.5 ATP per minute. Count-up needs 5 minutes to earn and caps at 2 hr.
    func atpReward(studiedSeconds: Int) -> Int {
        let minutes = Double(studiedSeconds) / 60
        if isCountUp && minutes < 5 { return 0 }
        let capped = isCountUp ? min(minutes, 120) : minutes
        return Int(capped * 0.5)
    }
}

// MARK: - Mode picker

struct ModePickerPanel: View {
    let close: () -> Void
    let start: (StudyMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("START STUDYING")
                    .pixelText(size: 15, color: Color(hex: "3A2A18"))
                Spacer()
                Button(action: close) {
                    Text("X")
                        .pixelText(size: 13, color: Color(hex: "3A2A18"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            ForEach(StudyMode.allCases) { mode in
                Button {
                    start(mode)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.label)
                                .pixelText(size: 13, color: Color(hex: "3A2A18"))
                            Text(mode.subtitle)
                                .font(.custom(MitoFont.regular, size: 13))
                                .foregroundStyle(Color(hex: "6B4324"))
                        }
                        Spacer()
                        Text(mode.rewardLabel)
                            .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(Color(hex: "4A8A3C"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .padding(10)
                    .background(Color(hex: "F4E6C0"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

// MARK: - Full-screen focus session

struct FocusSession: View {
    let mode: StudyMode
    @Binding var presented: StudyMode?
    let onEnd: (_ reward: Int, _ studiedSeconds: Int, _ completed: Bool) -> Void

    @State private var elapsed = 0          // seconds actually studied
    @State private var finished = false
    @State private var earned = 0
    @State private var shareImage: Image?
    @State private var bailed = false       // left the app mid-session (soft lock)
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var lock = FocusLockManager.shared

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("meadow-bg")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                ForEach(StudyWanderer.focusTeam()) { wanderer in
                    StudyWanderingCharacter(wanderer: wanderer, canvasSize: proxy.size)
                }

                VStack {
                    VStack(spacing: 8) {
                        Text(mode.label)
                            .pixelText(size: 11, color: Color(hex: "F4E6C0").opacity(0.85))
                        Text(timeText)
                            .font(.custom(MitoFont.bold, size: 54))
                            .foregroundStyle(Color(hex: "F4E6C0"))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                    .background(Color(hex: "1A1009").opacity(0.82))
                    .overlay(Rectangle().stroke(Color(hex: "F4E6C0").opacity(0.45), lineWidth: 2))
                    .padding(.top, 64)

                    if lock.softLockEnabled && !mode.isCountUp {
                        Text("🔒 STAY IN MITO — LEAVING VOIDS THE RUN")
                            .pixelText(size: 8, color: Color(hex: "F4E6C0").opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: "1A1009").opacity(0.66))
                            .padding(.top, 10)
                    }

                    Spacer()

                    Button {
                        finish()
                    } label: {
                        Text("END SESSION")
                            .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 13)
                            .background(Color(hex: "C84A3A"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 44)
                }

                if finished {
                    completionOverlay
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .onReceive(ticker) { _ in tick() }
        .onAppear { lock.beginSession() }
        .onDisappear { lock.endSession() }
        .onChange(of: scenePhase) { _, phase in
            lock.scenePhaseChanged(to: phase)
            // Soft lock: bailing to another app during a countdown voids the
            // run so the reward/streak can't be farmed by leaving.
            if lock.didLeaveDuringSession, !finished, !mode.isCountUp {
                bailed = true
                finish()   // end the run; reward is voided in finish()
            }
        }
    }

    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(headline)
                    .pixelText(size: 18, color: Color(hex: "3A2A18"))
                Text("Studied \(studiedText)")
                    .font(.custom(MitoFont.regular, size: 14))
                    .foregroundStyle(Color(hex: "6B4324"))
                Text(earned > 0 ? "+\(earned) ATP" : (bailed ? "No reward — you left the app" : "No reward (study 5+ min)"))
                    .pixelText(size: 15, color: earned > 0 ? Color(hex: "C8881A") : Color(hex: "8A6A40"))
                if let shareImage, earned > 0 {
                    ShareLink(
                        item: shareImage,
                        preview: SharePreview("My Mito study session", image: shareImage)
                    ) {
                        Text("SHARE")
                            .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color(hex: "4A7BA8"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    onEnd(earned, elapsed, !mode.isCountUp && elapsed >= mode.durationSeconds)
                    presented = nil
                } label: {
                    Text("DONE")
                        .pixelText(size: 13, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(hex: "4A8A3C"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .frame(width: 280)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        }
    }

    private func tick() {
        guard !finished else { return }
        elapsed += 1
        if !mode.isCountUp && elapsed >= mode.durationSeconds {
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        lock.endSession()
        // Bailing out of a countdown voids the reward (soft-lock accountability).
        earned = bailed ? 0 : mode.atpReward(studiedSeconds: elapsed)
        // A real session (5+ minutes, earned something) feeds the streak and
        // daily quest, and is the moment we first ask for notifications —
        // right when the user has a streak to protect.
        if earned > 0 && elapsed >= 300 {
            StreakStore.shared.registerActivity()
            DailyQuests.shared.noteFocusCompleted()
            NotificationManager.shared.requestPermissionIfNeeded()
        }
        shareImage = SessionShareCard.render(
            minutes: max(1, elapsed / 60),
            atp: earned,
            streak: StreakStore.shared.count,
            modeLabel: mode.label
        )
        finished = true
    }

    /// Big timer readout: remaining for countdowns, elapsed for count-up.
    private var timeText: String {
        let shown = mode.isCountUp ? elapsed : max(0, mode.durationSeconds - elapsed)
        return Self.clockText(shown)
    }

    private var studiedText: String {
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        if minutes == 0 { return "\(seconds)s" }
        return "\(minutes)m \(seconds)s"
    }

    private var headline: String {
        if bailed { return "YOU LEFT — RUN VOID" }
        if !mode.isCountUp && elapsed >= mode.durationSeconds {
            return "SESSION COMPLETE"
        }
        return "SESSION ENDED"
    }

    private static func clockText(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
