import SwiftUI

struct HomeScreen: View {
    @Binding var atp: Int
    @Binding var gold: Int
    @Binding var gems: Int
    @ObservedObject var backend: MitoBackend
    var selectedTab: AppTab = .home
    @State private var showPicker = false
    @State private var sessionMode: StudyMode?
    @State private var showingSettings = false
    @State private var showingAuth = false
    @State private var showingFriends = false
    @State private var showingClasses = false
    @State private var showingStreak = false
    @State private var showingQuests = false
    @State private var showingHatch = false
    @ObservedObject private var eggs = EggStore.shared
    @ObservedObject private var lobby = LobbyService.shared
    @ObservedObject private var streak = StreakStore.shared
    @ObservedObject private var quests = DailyQuests.shared
    @ObservedObject private var party = PartyStore.shared
    @ObservedObject private var tutorial = TutorialManager.shared
    @ObservedObject private var story = CampaignStoryManager.shared
    @AppStorage("settings.animations") private var animationsEnabled = true

    /// A dimmed tutorial/story dialogue is on screen — hide the meadow chrome
    /// (STUDY button etc.) so it doesn't bleed through behind the dialogue.
    private var dialogueActive: Bool { tutorial.isSaying || story.isSaying }

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

                        Button {
                            showingHatch = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("🥚").font(.system(size: 14))
                                Text("\(eggs.eggs)")
                                    .pixelText(size: 11, color: eggs.eggs > 0 ? Color(hex: "F7C943") : Color(hex: "F4E6C0"))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(Color(hex: "1A1009").opacity(0.82))
                            .overlay(Rectangle().stroke(eggs.eggs > 0 ? Color(hex: "F7C943") : Color(hex: "18100A"), lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Eggs: \(eggs.eggs). Tap to hatch.")

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
                    } else if !dialogueActive {
                        Button {
                            TutorialManager.shared.complete("study")
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
                        .tutorialAnchor("study")
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
                    .frame(width: min(proxy.size.width * 0.86, 360),
                           height: min(580, proxy.size.height * 0.82))
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.5)
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
                    let minutes = max(0, seconds / 60)
                    let legit = completed || (mode.isCountUp && minutes >= 5)
                    // A real session hatches an egg (or more, for longer focus).
                    if legit { EggStore.shared.awardEggs(forMinutes: minutes) }
                    // Trust: a finished session builds the companion's trust;
                    // bailing early (or a sub-5-min count-up) breaks it.
                    if let cid = TrustStore.shared.companionID,
                       let companion = DataSet.anyHero(id: cid) {
                        if legit {
                            TrustStore.shared.addStudyMinutes(minutes, to: companion)
                        } else {
                            TrustStore.shared.penalizeCancel(companion)
                        }
                    }
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
            .fullScreenCover(isPresented: $showingHatch) {
                HatchView(isPresented: $showingHatch)
            }
            .onChange(of: selectedTab) { _, tab in
                // Close transient sheets/popovers when leaving Home (an active
                // focus session is a full-screen cover, so it can't be left here).
                if tab != .home {
                    showPicker = false
                    showingSettings = false
                    showingAuth = false
                    showingFriends = false
                    showingClasses = false
                    showingStreak = false
                    showingQuests = false
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
                HStack(spacing: 6) {
                    Text(streak.freezes >= StreakStore.maxFreezes ? "FREEZES FULL" : "BUY FREEZE")
                        .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                    if streak.freezes < StreakStore.maxFreezes {
                        Image("currency-coin")
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        Text("\(StreakStore.freezeCostGold)")
                            .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                    }
                }
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
                chestLabel
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

    @ViewBuilder
    private var chestLabel: some View {
        if quests.chestClaimed {
            Text("CHEST CLAIMED")
                .pixelText(size: 11, color: Color(hex: "F4E6C0"))
        } else if quests.chestReady {
            HStack(spacing: 6) {
                Text("OPEN CHEST")
                    .pixelText(size: 11, color: Color(hex: "18100A"))
                Image("currency-coin")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text("\(DailyQuests.chestGold)")
                    .pixelText(size: 10, color: Color(hex: "18100A"))
                Image("currency-gem")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text("\(DailyQuests.chestGems)")
                    .pixelText(size: 10, color: Color(hex: "18100A"))
            }
        } else {
            Text("FINISH ALL 3 TO OPEN THE CHEST")
                .pixelText(size: 11, color: Color(hex: "F4E6C0"))
        }
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

