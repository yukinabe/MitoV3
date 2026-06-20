//  FocusSession.swift
//  Study modes + mode picker + the live focus session view.
//  Extracted from StudyView.swift (behavior-preserving refactor).

import SwiftUI

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
        case .countUp: "Open · 5 min to 2 hr"
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

    @ObservedObject private var trust = TrustStore.shared
    @ObservedObject private var roster = RosterStore.shared
    @ObservedObject private var capture = CaptureStore.shared

    /// Whole owned roster, base heroes then captured creatures.
    private var ownedRoster: [Hero] {
        roster.ownedHeroes + capture.capturedHeroes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("START STUDYING"))
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

            companionPicker

            ForEach(StudyMode.allCases) { mode in
                Button {
                    TutorialManager.shared.complete("study.mode.\(mode.rawValue)")
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
                .tutorialAnchor("study.mode.\(mode.rawValue)")
            }
        }
        .padding(16)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }

    /// "Study with" companion strip — pick one owned character to build Trust
    /// (or Bond, once trusted) with during this session.
    @ViewBuilder
    private var companionPicker: some View {
        if ownedRoster.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("STUDY WITH"))
                    .pixelText(size: 9, color: Color(hex: "6B4324"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ownedRoster) { hero in
                            CompanionChip(hero: hero, selected: trust.companionID == hero.id) {
                                trust.chooseCompanion(trust.companionID == hero.id ? nil : hero.id)
                                Haptics.select()
                                TutorialManager.shared.complete("study.companion.\(hero.id)")
                            }
                            .tutorialAnchor("study.companion.\(hero.id)")
                        }
                    }
                    .padding(.bottom, 2)
                }
                if let cid = trust.companionID, let hero = DataSet.anyHero(id: cid) {
                    Text(companionHint(hero))
                        .font(.custom(MitoFont.regular, size: 12))
                        .foregroundStyle(Color(hex: "6B4324"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 2)
            .tutorialAnchor("study.companion")
        }
    }

    private func companionHint(_ hero: Hero) -> String {
        if trust.isMaxed(hero) {
            return Lf("Already trusted. studying deepens your bond with %@.", L(hero.name))
        }
        return Lf("Study to earn %@'s trust · %ld min to full.", L(hero.name), trust.minutesRemaining(hero))
    }
}

/// One portrait in the companion strip, with a Trust/Bond mini-bar.
private struct CompanionChip: View {
    let hero: Hero
    let selected: Bool
    let tap: () -> Void
    @ObservedObject private var trust = TrustStore.shared

    var body: some View {
        let maxed = trust.isMaxed(hero)
        Button(action: tap) {
            VStack(spacing: 3) {
                SpriteView(asset: hero.asset, size: 38)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(hex: "B89868")).frame(width: 40, height: 5)
                    Rectangle()
                        .fill(maxed ? Color(hex: "C98AE0") : Color(hex: "4A8A3C"))
                        .frame(width: 40 * CGFloat(maxed ? 1 : trust.fraction(hero)), height: 5)
                }
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 1))
                Text(maxed ? "✓" : L(hero.name))
                    .pixelText(size: 6, color: Color(hex: "3A2A18"))
                    .lineLimit(1)
                    .frame(width: 42)
            }
            .padding(5)
            .background(selected ? Color(hex: "F7C943") : Color(hex: "F4E6C0"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: selected ? 3 : 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full-screen focus session

struct FocusSession: View {
    let mode: StudyMode
    let tutorialMode: Bool
    @Binding var presented: StudyMode?
    let onEnd: (_ reward: Int, _ studiedSeconds: Int, _ completed: Bool, _ tutorialMode: Bool) -> Void

    @State private var elapsed = 0          // seconds actually studied
    @State private var finished = false
    @State private var earned = 0
    @State private var shareImage: Image?
    @State private var bailed = false       // left the app mid-session (soft lock)
    @State private var tutorialPromptPulse = false
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

                ForEach(StudyWanderer.focusTeam(companion: TrustStore.shared.companionID)) { wanderer in
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
                        Text("🔒 STAY IN MITO. LEAVING VOIDS THE RUN")
                            .pixelText(size: 8, color: Color(hex: "F4E6C0").opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: "1A1009").opacity(0.66))
                            .padding(.top, 10)
                    }

                    Spacer()

                    if tutorialMode {
                        VStack(spacing: 7) {
                            Text("▼  TAP HERE TO CONTINUE  ▼")
                                .pixelText(size: 9, color: Color(hex: "FFF3C4"))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(hex: "18100A").opacity(0.88))
                                .offset(y: tutorialPromptPulse ? 4 : 0)

                            Button {
                                completeTutorialSession()
                            } label: {
                                VStack(spacing: 4) {
                                    Text("SKIP 25 MINUTES")
                                        .pixelText(size: 14, color: Color(hex: "18100A"))
                                    Text("Tutorial only · instantly receive the full reward")
                                        .font(.custom(MitoFont.regular, size: 11))
                                        .foregroundStyle(Color(hex: "3A2A18"))
                                }
                                .padding(.horizontal, 22)
                                .padding(.vertical, 14)
                                .background(Color(hex: "FFD24D"))
                                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(tutorialPromptPulse ? 1.04 : 0.98)
                            .shadow(color: Color(hex: "FFD24D").opacity(0.8), radius: tutorialPromptPulse ? 12 : 3)
                            .accessibilityLabel("Skip 25 minute tutorial session")
                        }
                        .padding(.bottom, 10)
                    }

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
        .onAppear {
            lock.beginSession()
            MitoFocusActivityController.start(mode: mode)
            if !tutorialMode {
                let m = mode.rawValue
                Task { await MitoBackend.shared.logEvent("focus_session_started", props: ["mode": m]) }
            }
            if tutorialMode {
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                    tutorialPromptPulse = true
                }
            }
            #if DEBUG
            if tutorialMode,
               ProcessInfo.processInfo.arguments.contains("-uitestTutorialFocusComplete") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    completeTutorialSession()
                }
            }
            #endif
        }
        .onDisappear {
            lock.endSession()
            if !finished {
                MitoFocusActivityController.end(elapsed: elapsed, mode: mode, completed: false)
            }
        }
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
                Text(earned > 0 ? "+\(earned) ATP" : (bailed ? "No reward. You left the app" : "No reward (study 5+ min)"))
                    .pixelText(size: 15, color: earned > 0 ? Color(hex: "C8881A") : Color(hex: "8A6A40"))
                if tutorialMode && earned > 0 {
                    VStack(spacing: 5) {
                        Text("+1 EGG  •  +100 GOLD")
                            .pixelText(size: 10, color: Color(hex: "6B4324"))
                        Text("+6 BIOMASS  •  +25 MIN CHLORO TRUST")
                            .pixelText(size: 8, color: Color(hex: "4A8A3C"))
                    }
                }
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
                    onEnd(earned, elapsed, !mode.isCountUp && elapsed >= mode.durationSeconds, tutorialMode)
                    TutorialManager.shared.complete("study.tutorialComplete")
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
        MitoFocusActivityController.update(elapsed: elapsed, mode: mode)
        if !mode.isCountUp && elapsed >= mode.durationSeconds {
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        lock.endSession()
        // Bailing out of a countdown voids the reward (soft-lock accountability).
        earned = bailed ? 0 : mode.atpReward(studiedSeconds: elapsed)
        MitoFocusActivityController.end(elapsed: elapsed, mode: mode, completed: !mode.isCountUp && elapsed >= mode.durationSeconds && !bailed)
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
        if !tutorialMode {
            let evMode = mode.rawValue
            let evMinutes = elapsed / 60
            let evAtp = earned
            let evCompleted = !bailed
            Task {
                await MitoBackend.shared.logEvent("focus_session_completed", props: [
                    "mode": evMode,
                    "minutes": "\(evMinutes)",
                    "atp": "\(evAtp)",
                    "completed": "\(evCompleted)"
                ])
            }
        }
        finished = true
    }

    private func completeTutorialSession() {
        guard tutorialMode, !finished else { return }
        elapsed = mode.durationSeconds
        bailed = false
        finish()
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
        if bailed { return "YOU LEFT. RUN VOID" }
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
