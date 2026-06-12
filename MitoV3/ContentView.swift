import SwiftUI
import Supabase
#if os(iOS)
import FamilyControls
#endif

struct ContentView: View {
    @StateObject private var backend = MitoBackend.shared
    @State private var selectedTab: AppTab = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitestReview") { return .battle }
        if ProcessInfo.processInfo.arguments.contains("-uitestMap") { return .battle }
        if ProcessInfo.processInfo.arguments.contains("-uitestStage") { return .battle }
        if ProcessInfo.processInfo.arguments.contains("-uitestCampaign") { return .battle }
        if ProcessInfo.processInfo.arguments.contains("-uitestShop") { return .shop }
        if ProcessInfo.processInfo.arguments.contains("-uitestTeam") { return .team }
        if ProcessInfo.processInfo.arguments.contains("-uitestCards") { return .cards }
        #endif
        return .home
    }()
    // Wallet is persisted locally (@AppStorage) so currency survives offline play
    // and relaunches with no connection; the cloud is a backup/sync that's
    // merged in via loadWallet (max-wins, so offline gains are never lost).
    @AppStorage("wallet.atp") private var atp = 0
    @AppStorage("wallet.gold") private var gold = 0
    @AppStorage("wallet.gems") private var gems = 0
    @AppStorage("wallet.biomass") private var biomass = 0
    @AppStorage("wallet.shards") private var shards = 0
    @State private var walletSaveTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var notifications = NotificationManager.shared
    @AppStorage("mito.admitted") private var admitted = false
    @AppStorage("mito.onboarded") private var onboarded = false
    @AppStorage("mito.tutorialSeen") private var tutorialSeen = false
    @AppStorage("mito.goal") private var goal = ""

    private var launchArgs: [String] { ProcessInfo.processInfo.arguments }
    private var forceTutorial: Bool {
        #if DEBUG
        return launchArgs.contains("-uitestTutorial")
        #else
        return false
        #endif
    }
    private var forceGate: Bool {
        #if DEBUG
        return launchArgs.contains("-uitestGate")
        #else
        return false
        #endif
    }
    private var forceOnboard: Bool {
        #if DEBUG
        return launchArgs.contains("-uitestOnboard")
        #else
        return false
        #endif
    }
    /// Skip the gate/onboarding for DEBUG screenshot launches (-uitest*), except
    /// the two flags that explicitly want to show them.
    private var bypassGate: Bool {
        #if DEBUG
        return launchArgs.contains { $0.hasPrefix("-uitest") } && !forceGate && !forceOnboard
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            appShell
            // Waitlist / "private beta" gate removed — app opens straight in.
            if forceOnboard || (!bypassGate && !onboarded) {
                OnboardingView(backend: backend, goal: $goal) {
                    withAnimation { onboarded = true }
                    selectedTab = .home
                }
            } else if forceTutorial || (!bypassGate && !tutorialSeen) {
                // First-run tutorial for new users (skippable).
                TutorialOverlay {
                    withAnimation { tutorialSeen = true }
                    selectedTab = .home
                }
            }

            // Notification priming — shown after the first session completes,
            // before the OS permission dialog (revealed once the session sheet
            // dismisses, since it lives below it here).
            if notifications.showPrimer {
                NotificationPrimerView(
                    onEnable: { notifications.confirmPrimer() },
                    onSkip: { notifications.dismissPrimer() }
                )
                .transition(.opacity)
                .zIndex(50)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.2), value: notifications.showPrimer)
    }

    private var appShell: some View {
        GeometryReader { proxy in
            ZStack {
                Color.mitoWoodDarkest.ignoresSafeArea()

                VStack(spacing: 0) {
                    HeaderChrome(atp: atp, gold: gold, gems: gems, topInset: proxy.safeAreaInsets.top)
                        .frame(height: proxy.safeAreaInsets.top + 52)
                        .zIndex(2)
                    
                    TabView(selection: $selectedTab) {
                        ShopScreen(atp: $atp, gold: $gold, gems: $gems, biomass: $biomass, shards: $shards)
                            .tag(AppTab.shop)
                        TeamScreen(atp: $atp, gold: $gold, biomass: $biomass)
                            .tag(AppTab.team)
                        HomeScreen(atp: $atp, gold: $gold, gems: $gems, backend: backend)
                            .tag(AppTab.home)
                        BattleScreen(atp: $atp, gold: $gold, biomass: $biomass)
                            .tag(AppTab.battle)
                        CardsScreen()
                            .tag(AppTab.cards)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    DeviceBottomBar(selectedTab: $selectedTab)
                        .frame(height: 74)
                        .zIndex(2)
                }
                .ignoresSafeArea(edges: [.top, .bottom])
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear { AudioManager.shared.startMusic(.home) }
        .task {
            await backend.bootstrapExistingSession()
            // Load cloud decks/FSRS state and mirror future grades to Supabase.
            await backend.attachSync(to: .shared)
            await loadWallet()
            await backend.logEvent("app_open")
            // Settle yesterday's streak (freezes) and roll daily quests over.
            StreakStore.shared.reconcile()
            DailyQuests.shared.rollover()
            NotificationManager.shared.reschedule()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                StreakStore.shared.reconcile()
                DailyQuests.shared.rollover()
            case .background:
                // Recompute the nudges + widget with the freshest due counts.
                NotificationManager.shared.reschedule()
                WidgetBridge.sync()
            default:
                break
            }
        }
        .onChange(of: backend.accountEmail) { old, new in
            // Signing into a real account → pull THAT account's cloud wallet +
            // decks. Signing out / deleting → drop the previous account's
            // currency from the UI so it isn't shown to the next (anon) user.
            Task {
                if new != nil {
                    await backend.attachSync(to: .shared)
                    await loadWallet()
                } else if old != nil {
                    atp = 0; gold = 0; gems = 0; biomass = 0; shards = 0
                }
            }
        }
        .onChange(of: atp) { _, _ in scheduleWalletSave() }
        .onChange(of: gold) { _, _ in scheduleWalletSave() }
        .onChange(of: gems) { _, _ in scheduleWalletSave() }
        .onChange(of: biomass) { _, _ in scheduleWalletSave() }
        .onChange(of: shards) { _, _ in scheduleWalletSave() }
    }

    /// Merge the cloud wallet into the local one. Offline-first: the local
    /// (@AppStorage) balance is the working copy, so we take the max of each
    /// currency — cloud progress from another device is pulled in, and coins
    /// earned offline (cloud is lower) are kept and pushed back up on change.
    /// No-ops cleanly offline / pre-migration, leaving the local wallet intact.
    private func loadWallet() async {
        guard backend.isReady, let w = try? await backend.fetchWallet() else { return }
        atp = max(atp, w.atp)
        gold = max(gold, w.gold)
        gems = max(gems, w.gems)
        biomass = max(biomass, w.biomass)
        shards = max(shards, w.shards)
    }

    /// Debounced wallet persist — coalesces rapid reward/spend changes into one
    /// write ~1.2s after the last change.
    private func scheduleWalletSave() {
        guard backend.isReady else { return }
        let snapshot = (atp, gold, gems, biomass, shards)
        walletSaveTask?.cancel()
        walletSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            try? await backend.saveWallet(
                atp: snapshot.0, gold: snapshot.1, gems: snapshot.2,
                biomass: snapshot.3, shards: snapshot.4
            )
        }
    }
}

/// Priming screen shown before the OS notification dialog, so a reflexive
/// "Don't Allow" doesn't permanently kill due-card + streak reminders.
struct NotificationPrimerView: View {
    let onEnable: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("🔔").font(.system(size: 40))
                Text("STAY ON TRACK")
                    .pixelText(size: 17, color: Color(hex: "3A2A18"))
                Text("Mito can remind you when your cards are due and when your streak is about to break. Just the two nudges — no spam.")
                    .font(.custom(MitoFont.regular, size: 14))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onEnable) {
                    Text("ENABLE REMINDERS")
                        .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(hex: "4A8A3C"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)

                Button(action: onSkip) {
                    Text("NOT NOW")
                        .pixelText(size: 10, color: Color(hex: "6B4324"))
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .frame(width: 300)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        }
    }
}

struct AuthSheet: View {
    @ObservedObject var backend: MitoBackend
    @Binding var isPresented: Bool

    @State private var email = ""
    @State private var password = ""
    @State private var message = ""
    @State private var isWorking = false
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACCOUNT")
                        .pixelText(size: 17, color: Color(hex: "3A2A18"))
                    Text(accountSubtitle)
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Text("X")
                        .pixelText(size: 13, color: Color(hex: "3A2A18"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            if !backend.isLoggedIn {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EMAIL")
                        .pixelText(size: 9, color: Color(hex: "6B4324"))
                    TextField("you@example.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.emailAddress)
                        .authInputStyle()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("PASSWORD")
                        .pixelText(size: 9, color: Color(hex: "6B4324"))
                    SecureField("minimum 6 characters", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .authInputStyle()
                }
            }

            if !message.isEmpty {
                Text(message)
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !backend.isLoggedIn {
                HStack(spacing: 10) {
                    Button {
                        Task { await submit(.signIn) }
                    } label: {
                        Text(isWorking ? "..." : "SIGN IN")
                            .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(canSubmit ? Color(hex: "4A8A3C") : Color(hex: "8A8A70"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)

                    Button {
                        Task { await submit(.signUp) }
                    } label: {
                        Text("SIGN UP")
                            .pixelText(size: 11, color: Color(hex: "18100A"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(canSubmit ? Color(hex: "F7C943") : Color(hex: "B89868"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
            }

            if backend.isLoggedIn {
                Button {
                    Task { await signOut() }
                } label: {
                    Text("SIGN OUT")
                        .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(hex: "D84A3A"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(isWorking)

                Button {
                    showDeleteConfirm = true
                } label: {
                    Text("DELETE ACCOUNT")
                        .pixelText(size: 9, color: Color(hex: "D84A3A"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .overlay(Rectangle().stroke(Color(hex: "D84A3A"), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
        }
        .padding(16)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .alert("Delete account?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, decks, cards, and all progress. This cannot be undone.")
        }
    }

    private var canSubmit: Bool {
        !isWorking && email.contains("@") && password.count >= 6
    }

    private var accountSubtitle: String {
        if let email = backend.accountEmail {
            return "Signed in as \(email)"
        }
        return "Sign in to sync your decks and progress across devices."
    }

    private func submit(_ action: AuthAction) async {
        guard canSubmit else { return }
        isWorking = true
        message = ""
        do {
            switch action {
            case .signIn:
                try await backend.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                await backend.attachSync(to: .shared)
                isPresented = false
            case .signUp:
                try await backend.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                if backend.isReady {
                    await backend.attachSync(to: .shared)
                    isPresented = false
                } else {
                    message = "Check your email to confirm, then sign in."
                }
            }
        } catch {
            message = error.localizedDescription
        }
        isWorking = false
    }

    private func signOut() async {
        isWorking = true
        message = ""
        do {
            try await backend.signOut()
            message = "Signed out."
        } catch {
            message = error.localizedDescription
        }
        isWorking = false
    }

    private func deleteAccount() async {
        isWorking = true
        message = ""
        do {
            try await backend.deleteAccount()
            message = "Account deleted."
        } catch {
            message = error.localizedDescription
        }
        isWorking = false
    }

    private enum AuthAction {
        case signIn
        case signUp
    }
}

// MARK: - First-run tutorial (skippable)

private struct TutorialStep {
    let icon: String
    let title: String
    let body: String
}

struct TutorialOverlay: View {
    let onClose: () -> Void
    @State private var step = 0

    private let steps: [TutorialStep] = [
        TutorialStep(icon: "📚", title: "WELCOME TO MITO",
                     body: "A study RPG where reviewing flashcards powers a team of cell-heroes in battle."),
        TutorialStep(icon: "🗂️", title: "STUDY = STRENGTH",
                     body: "Tap STUDY to review your decks. Every card you answer fuels your heroes' attacks."),
        TutorialStep(icon: "⚔️", title: "BATTLE",
                     body: "Answer a card, then pick an ability. Support moves buff the team (⚡ATP charge); damage moves strike the enemy."),
        TutorialStep(icon: "🗺️", title: "CAMPAIGN",
                     body: "Clear a stage to unlock the next. Enemies grow stronger as you climb — so keep studying!"),
        TutorialStep(icon: "🎉", title: "YOU'RE READY",
                     body: "Build streaks, earn coins, and grow your team. Good luck, scholar!")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(steps[step].icon).font(.system(size: 50))
                Text(steps[step].title)
                    .pixelText(size: 18, color: Color(hex: "3A2A18"))
                Text(steps[step].body)
                    .font(.custom(MitoFont.regular, size: 14))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color(hex: "4A8A3C") : Color(hex: "C9B086"))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 2)
                HStack(spacing: 10) {
                    Button(action: onClose) {
                        Text("SKIP")
                            .pixelText(size: 12, color: Color(hex: "6B4324"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(hex: "D8C29A"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    Button {
                        if step < steps.count - 1 { withAnimation { step += 1 } } else { onClose() }
                    } label: {
                        Text(step < steps.count - 1 ? "NEXT" : "START")
                            .pixelText(size: 12, color: .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(hex: "4A8A3C"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(width: 300)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
        }
    }
}

struct GeneralSettingsSheet: View {
    @ObservedObject var backend: MitoBackend
    @Binding var isPresented: Bool
    let showAuth: () -> Void

    @AppStorage("audio.sfx") private var soundEnabled = true
    @AppStorage("audio.music") private var musicEnabled = true
    @AppStorage("settings.animations") private var animationsEnabled = true
    @ObservedObject private var lock = FocusLockManager.shared
    @State private var showingAppPicker = false
    #if os(iOS)
    @State private var pickerSelection = FocusBlockSelection.load()
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SETTINGS")
                    .pixelText(size: 17, color: Color(hex: "3A2A18"))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Text("X")
                        .pixelText(size: 13, color: Color(hex: "3A2A18"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                SettingsActionRow(
                    title: backend.isLoggedIn ? "ACCOUNT" : "LOGIN",
                    detail: backend.isLoggedIn
                        ? "Signed in as \(backend.accountEmail ?? "you") · sign out or delete"
                        : "Sign in to sync decks and progress.",
                    value: backend.isLoggedIn ? "MANAGE" : "SIGN IN",
                    action: showAuth
                )

                SettingsToggleRow(title: "SOUND", detail: "Menu and battle effects.", isOn: $soundEnabled)
                SettingsToggleRow(title: "MUSIC", detail: "Background music.", isOn: $musicEnabled)
                SettingsToggleRow(title: "ANIMATION", detail: "Idle character movement.", isOn: $animationsEnabled)

                Text("FOCUS LOCK")
                    .pixelText(size: 10, color: Color(hex: "3A2A18"))
                    .padding(.top, 6)
                SettingsToggleRow(
                    title: "STAY-IN-APP LOCK",
                    detail: "Leaving Mito during a timed session voids the run.",
                    isOn: $lock.softLockEnabled)
                #if os(iOS)
                // The OS-level app shield is hidden until the Family Controls
                // entitlement is granted (see BetaConfig.appShieldEnabled).
                if BetaConfig.appShieldEnabled {
                    SettingsToggleRow(
                        title: "BLOCK APPS",
                        detail: "Shield distracting apps with Screen Time during focus. Needs permission.",
                        isOn: $lock.shieldEnabled)
                    if lock.shieldEnabled {
                        SettingsActionRow(
                            title: "CHOOSE BLOCKED APPS",
                            detail: "\(FocusBlockSelection.count()) app group(s) blocked during focus.",
                            value: "PICK",
                            action: {
                                lock.requestShieldAuthorization()
                                showingAppPicker = true
                            })
                    }
                }
                #endif
            }
        }
        #if os(iOS)
        .familyActivityPicker(isPresented: $showingAppPicker, selection: $pickerSelection)
        .onChange(of: pickerSelection) { _, sel in
            FocusBlockSelection.save(sel)
        }
        #endif
        .onChange(of: soundEnabled) { _, on in
            AudioManager.shared.sfxEnabled = on
            if on { AudioManager.shared.play(.uiTap) }
        }
        .onChange(of: musicEnabled) { _, on in
            AudioManager.shared.musicEnabled = on
        }
        .padding(16)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

private struct SettingsActionRow: View {
    let title: String
    let detail: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .pixelText(size: 11, color: Color(hex: "3A2A18"))
                    Text(detail)
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(value)
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

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .pixelText(size: 11, color: Color(hex: "3A2A18"))
                    Text(detail)
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(isOn ? "ON" : "OFF")
                    .pixelText(size: 9, color: isOn ? Color(hex: "F4E6C0") : Color(hex: "3A2A18"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(isOn ? Color(hex: "4A8A3C") : Color(hex: "B89868"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }
            .padding(10)
            .background(Color(hex: "F4E6C0"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

private struct HeaderChrome: View {
    let atp: Int
    let gold: Int
    let gems: Int
    let topInset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color(hex: "1A1009")

                TopHUD(atp: atp, gold: gold, gems: gems)
                    .frame(height: 36)
                    .padding(.horizontal, 4)
                    .position(x: proxy.size.width / 2, y: topInset + 26)
            }
        }
    }
}

private struct DeviceBottomBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "1A1009")
            VStack(spacing: 0) {
                BottomTray(selectedTab: $selectedTab)
                    .frame(height: 74)
            }
        }
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case shop
    case team
    case home
    case battle
    case cards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shop: "Shop"
        case .team: "Team"
        case .home: "Home"
        case .battle: "Battle"
        case .cards: "Cards"
        }
    }
}










private struct TopHUD: View {
    let atp: Int
    let gold: Int
    let gems: Int

    var body: some View {
        HStack(spacing: 6) {
            HUDAsset(asset: "hud-gem", value: "\(gems)", color: Color(hex: "BFF5C2"), left: 0.40, right: 0.07)
                .frame(width: 106)
            Spacer(minLength: 6)
            HUDAsset(asset: "hud-atp", value: "\(atp)", color: Color(hex: "FFD24D"), left: 0.26, right: 0.05)
                .frame(width: 122)
            HUDAsset(asset: "hud-coin", value: "\(gold)", color: Color(hex: "F9E9B8"), left: 0.30, right: 0.06)
                .frame(width: 106)
        }
    }
}

private struct HUDAsset: View {
    let asset: String
    let value: String
    let color: Color
    let left: CGFloat
    let right: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image(asset)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                Text(value)
                    .pixelText(size: 10, color: color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(
                        width: proxy.size.width * max(0.1, 1 - left - right),
                        height: proxy.size.height * 0.62
                    )
                    .position(
                        x: proxy.size.width * (left + (1 - left - right) / 2),
                        y: proxy.size.height * 0.50
                    )
            }
        }
    }
}

private struct BottomTray: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("nav-tray")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                HStack(spacing: 0) {
                    ForEach(AppTab.allCases) { tab in
                        Button {
                            if selectedTab != tab {
                                AudioManager.shared.play(.uiTap, volume: 0.7)
                                Haptics.select()
                            }
                            withAnimation(.snappy(duration: 0.28)) {
                                selectedTab = tab
                            }
                        } label: {
                            ZStack {
                                if selectedTab == tab {
                                    CornerBrackets()
                                        .stroke(Color(hex: "FFD24D"), lineWidth: 2)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 12)
                                    Rectangle()
                                        .fill(Color(hex: "FFD24D").opacity(0.10))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 14)
                                } else {
                                    Color.black.opacity(0.36)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.title)
                    }
                }
            }
        }
    }
}

// MARK: - Waitlist gate

struct WaitlistGate: View {
    @ObservedObject var backend: MitoBackend
    let onAdmit: () -> Void

    @State private var email = ""
    @State private var referral = ""
    @State private var code = ""
    @State private var joined = false
    @State private var working = false
    @State private var message = ""

    private var emailValid: Bool { email.contains("@") && email.contains(".") }

    var body: some View {
        ZStack {
            Color.mitoWoodDarkest.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    SpriteView(asset: "hero-mito-hop", size: 84)
                        .padding(.top, 40)
                    Text("MITO")
                        .pixelText(size: 30, color: Color(hex: "F7C943"))
                        .shadow(color: .black, radius: 0, x: 2, y: 2)
                    Text("A study RPG · private beta")
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "EAD4A4"))

                    VStack(spacing: 10) {
                        GateField(label: "EMAIL", placeholder: "you@example.com", text: $email, email: true)
                        GateField(label: "HOW DID YOU HEAR? (optional)", placeholder: "TikTok, friend…", text: $referral)
                        GateField(label: "INVITE CODE (optional)", placeholder: "enter code to skip the line", text: $code)
                        if !message.isEmpty {
                            Text(message)
                                .font(.custom(MitoFont.regular, size: 13))
                                .foregroundStyle(Color(hex: "6B4324"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .background(Color(hex: "EAD4A4"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                    Button { Task { await enter() } } label: {
                        Text(working ? "…" : "ENTER WITH CODE")
                            .pixelText(size: 14, color: Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(canEnter ? Color(hex: "4A8A3C") : Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEnter || working)

                    Button { Task { await join() } } label: {
                        Text(joined ? "ON THE LIST ✓" : "JOIN WAITLIST")
                            .pixelText(size: 12, color: joined ? Color(hex: "9FE08C") : Color(hex: "F7C943"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(hex: "2A1B0E"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!emailValid || working || joined)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var canEnter: Bool { emailValid && !code.trimmingCharacters(in: .whitespaces).isEmpty }

    private func enter() async {
        guard canEnter else { return }
        working = true
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        await backend.submitWaitlist(email: email, referral: referral, inviteCode: trimmedCode, cohort: "invited")
        await backend.logEvent("admitted", props: ["code": trimmedCode])
        working = false
        onAdmit()
    }

    private func join() async {
        guard emailValid else { return }
        working = true
        let ok = await backend.submitWaitlist(email: email, referral: referral, inviteCode: "", cohort: "waitlist")
        await backend.logEvent("waitlist_joined")
        working = false
        joined = ok
        message = ok ? "You're on the list — we'll email your invite. Have a code? Enter it above to jump in now."
                     : "Couldn't reach the server. Check your connection and try again."
    }
}

private struct GateField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var email = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .pixelText(size: 8, color: Color(hex: "6B4324"))
            TextField(placeholder, text: $text)
                .font(.custom(MitoFont.regular, size: 16))
                .foregroundStyle(Color(hex: "3A2A18"))
                .textInputAutocapitalization(email ? .never : .sentences)
                .autocorrectionDisabled(email)
                .keyboardType(email ? .emailAddress : .default)
                .padding(9)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @ObservedObject var backend: MitoBackend
    @Binding var goal: String
    let onComplete: () -> Void

    @State private var step = 0
    @State private var creating = false
    @State private var createdDeckName: String?

    private let goals = ["Biology", "Languages", "Test Prep", "Med / Nursing", "History", "Other"]

    var body: some View {
        ZStack {
            Color.mitoWoodDarkest.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle()
                            .fill(i <= step ? Color(hex: "F7C943") : Color(hex: "6B4324"))
                            .frame(height: 5)
                    }
                }
                .padding(.top, 50)

                Spacer(minLength: 0)

                switch step {
                case 0: goalStep
                case 1: deckStep
                default: focusStep
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 30)
        }
        .task { await backend.logEvent("onboarding_started") }
    }

    private var goalStep: some View {
        VStack(spacing: 16) {
            Text("WHAT ARE YOU STUDYING?")
                .pixelText(size: 18, color: Color(hex: "F4E6C0"))
                .multilineTextAlignment(.center)
            Text("We'll tune your starter content.")
                .font(.custom(MitoFont.regular, size: 15))
                .foregroundStyle(Color(hex: "EAD4A4"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(goals, id: \.self) { item in
                    Button {
                        goal = item
                        Task { await backend.logEvent("onboarding_goal", props: ["goal": item]) }
                        withAnimation { step = 1 }
                    } label: {
                        Text(item.uppercased())
                            .pixelText(size: 10, color: Color(hex: "3A2A18"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(goal == item ? Color(hex: "F7C943") : Color(hex: "EAD4A4"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var deckStep: some View {
        VStack(spacing: 14) {
            Text("ADD YOUR FIRST DECK")
                .pixelText(size: 18, color: Color(hex: "F4E6C0"))
            Text("Pick a starter deck to study right away.")
                .font(.custom(MitoFont.regular, size: 15))
                .foregroundStyle(Color(hex: "EAD4A4"))
                .multilineTextAlignment(.center)
            ForEach(DeckTemplate.all) { template in
                Button {
                    Task { await addStarter(template) }
                } label: {
                    HStack {
                        Text(template.name.uppercased())
                            .pixelText(size: 12, color: Color(hex: "3A2A18"))
                        Spacer()
                        Text("\(template.cards.count) CARDS")
                            .pixelText(size: 8, color: Color(hex: "6B4324"))
                    }
                    .padding(14)
                    .background(createdDeckName == template.name ? Color(hex: "CFE49C") : Color(hex: "EAD4A4"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(creating)
            }
            Button { withAnimation { step = 2 } } label: {
                Text("SKIP FOR NOW")
                    .pixelText(size: 10, color: Color(hex: "EAD4A4"))
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var focusStep: some View {
        VStack(spacing: 16) {
            SpriteView(asset: "hero-mito-hop", size: 96)
            Text("YOU'RE ALL SET")
                .pixelText(size: 20, color: Color(hex: "F7C943"))
            Text(createdDeckName == nil
                 ? "Start a focus session to earn ATP, then review your cards in battle."
                 : "“\(createdDeckName!)” is ready. Start a focus session to earn ATP, then review it in battle.")
                .font(.custom(MitoFont.regular, size: 16))
                .foregroundStyle(Color(hex: "EAD4A4"))
                .multilineTextAlignment(.center)
            Button {
                Task { await backend.logEvent("onboarding_completed", props: ["goal": goal]) }
                onComplete()
            } label: {
                Text("START STUDYING")
                    .pixelText(size: 16, color: Color(hex: "F4E6C0"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "4A8A3C"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
        }
    }

    /// Create the chosen starter deck in the cloud + review session, then advance.
    private func addStarter(_ template: DeckTemplate) async {
        guard !creating else { return }
        creating = true
        if backend.isReady, let record = try? await backend.createDeck(named: template.name) {
            for card in template.cards {
                let tags = card.tags.isEmpty ? ["new"] : card.tags
                if let created = try? await backend.createCard(deckID: record.id, front: card.front, back: card.back, tags: tags) {
                    ReviewSession.shared.upsertContent(ReviewCard(
                        id: created.id, deckID: record.id.uuidString, deckName: template.name,
                        front: card.front, back: card.back, tags: tags
                    ))
                }
            }
            await backend.logEvent("deck_created", props: ["name": template.name, "via": "onboarding"])
        }
        createdDeckName = template.name
        creating = false
        withAnimation { step = 2 }
    }
}

// MARK: - Friends (premium social)

/// Premium social hub: share your friend code, add friends, accept requests, and
/// (after the multiplayer update is deployed) start co-op and versus sessions.
/// Gated behind a premium flag — payments (RevenueCat) are a later step, so a
/// dev unlock is provided for now.
struct FriendsView: View {
    @ObservedObject var backend: MitoBackend
    @Binding var isPresented: Bool

    @AppStorage("premium.social") private var premium = false
    @State private var myCode = "…"
    @State private var addCode = ""
    @State private var friends: [FriendEdge] = []
    @State private var league: [LeagueRow] = []
    @State private var message = ""
    @State private var loading = false
    @State private var showingLobby = false

    private var accepted: [FriendEdge] { friends.filter(\.isAccepted) }
    private var incoming: [FriendEdge] { friends.filter(\.isIncomingRequest) }
    private var outgoing: [FriendEdge] { friends.filter(\.isOutgoingRequest) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.64).ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text("FRIENDS")
                        .pixelText(size: 17, color: Color(hex: "3A2A18"))
                    Spacer()
                    Button { isPresented = false } label: {
                        Text("X").pixelText(size: 13, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                if !BetaConfig.premiumActive {
                    paywall
                } else if !backend.isReady {
                    Text("Sign in (Settings → Login) to use friends and co-op.")
                        .font(.custom(MitoFont.regular, size: 14))
                        .foregroundStyle(Color(hex: "6B4324"))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 20)
                } else {
                    content
                }
            }
            .padding(16)
            .frame(width: 340)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))

            if showingLobby {
                LobbyView(backend: backend, isPresented: $showingLobby)
            }
        }
        .task { await load() }
    }

    private var paywall: some View {
        VStack(spacing: 12) {
            Text("✦ MITO+ ✦").pixelText(size: 16, color: Color(hex: "B8860B"))
            Text("Study with friends. Unlock co-op focus sessions, shared endless runs, and head-to-head deck duels.")
                .font(.custom(MitoFont.regular, size: 14))
                .foregroundStyle(Color(hex: "4A2F1C"))
                .multilineTextAlignment(.center)
            VStack(spacing: 6) {
                Label("Friends & lobbies", systemImage: "person.2.fill")
                Label("Co-op focus + endless", systemImage: "bolt.heart.fill")
                Label("PvP deck duels", systemImage: "flag.checkered")
            }
            .font(.custom(MitoFont.regular, size: 13))
            .foregroundStyle(Color(hex: "4A2F1C"))
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                // TODO: replace with RevenueCat purchase. Dev unlock for now.
                premium = true
                Haptics.success()
            } label: {
                Text("UNLOCK MITO+")
                    .pixelText(size: 14, color: .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Color(hex: "B8860B"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
            Text("Payments coming soon — this dev build unlocks instantly.")
                .font(.custom(MitoFont.regular, size: 11))
                .foregroundStyle(Color(hex: "6B4324"))
        }
        .padding(.vertical, 6)
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                // My code
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR FRIEND CODE").pixelText(size: 9, color: Color(hex: "6B4324"))
                    HStack(spacing: 10) {
                        Text(myCode)
                            .pixelText(size: 22, color: Color(hex: "3A2A18"))
                            .textSelection(.enabled)
                        Spacer()
                        if !myCode.isEmpty {
                            ShareLink(item: "Study with me on Mito, the pixel study RPG! 🔥 Add me with friend code \(myCode) — we can run co-op focus sessions and deck duels.") {
                                Text("INVITE")
                                    .pixelText(size: 11, color: .white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .background(Color(hex: "4A7BA8"))
                                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Add by code
                VStack(alignment: .leading, spacing: 6) {
                    Text("ADD A FRIEND").pixelText(size: 9, color: Color(hex: "6B4324"))
                    HStack(spacing: 8) {
                        TextField("CODE", text: $addCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .authInputStyle()
                        Button { Task { await add() } } label: {
                            Text("ADD").pixelText(size: 12, color: .white)
                                .padding(.horizontal, 14).frame(height: 40)
                                .background(Color(hex: "4A8A3C"))
                                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !message.isEmpty {
                    Text(message).font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
                }

                if !incoming.isEmpty {
                    sectionHeader("REQUESTS")
                    ForEach(incoming) { edge in
                        friendRow(edge, trailing: AnyView(
                            Button { Task { await accept(edge) } } label: {
                                Text("ACCEPT").pixelText(size: 10, color: .white)
                                    .padding(.horizontal, 10).frame(height: 30)
                                    .background(Color(hex: "4A8A3C"))
                                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                            }.buttonStyle(.plain)
                        ))
                    }
                }

                sectionHeader("FRIENDS (\(accepted.count))")
                if loading && friends.isEmpty {
                    HStack { Spacer(); ProgressView().tint(Color(hex: "6B4324")); Spacer() }
                        .padding(.vertical, 6)
                } else if accepted.isEmpty {
                    Text("No friends yet — share your code above.")
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
                }
                ForEach(accepted) { edge in
                    friendRow(edge, trailing: AnyView(
                        Text("ONLINE?").pixelText(size: 8, color: Color(hex: "8A6B42"))
                    ))
                }

                if !outgoing.isEmpty {
                    sectionHeader("PENDING")
                    ForEach(outgoing) { edge in
                        friendRow(edge, trailing: AnyView(
                            Text("SENT").pixelText(size: 9, color: Color(hex: "8A6B42"))
                        ))
                    }
                }

                // Weekly league: focus minutes, me + accepted friends, resets Monday.
                if league.count > 1 {
                    sectionHeader("THIS WEEK'S LEAGUE")
                    ForEach(Array(league.enumerated()), id: \.element.id) { rank, row in
                        HStack(spacing: 8) {
                            Text(rank == 0 ? "👑" : "#\(rank + 1)")
                                .pixelText(size: 11, color: rank == 0 ? Color(hex: "C8881A") : Color(hex: "8A6B42"))
                                .frame(width: 32, alignment: .leading)
                            Text(row.is_me ? "\(row.displayName) (you)" : row.displayName)
                                .font(.custom(row.is_me ? MitoFont.bold : MitoFont.regular, size: 15))
                                .foregroundStyle(Color(hex: "3A2A18"))
                            Spacer()
                            Text("\(row.minutes) MIN")
                                .pixelText(size: 10, color: Color(hex: "3A2A18"))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(hex: row.is_me ? "F7C943" : "DCC79A").opacity(row.is_me ? 0.55 : 1))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    Text("Focus minutes this week. Resets Monday.")
                        .font(.custom(MitoFont.regular, size: 11))
                        .foregroundStyle(Color(hex: "6B4324"))
                }

                // Co-op & versus entry point → lobby (realtime presence).
                sectionHeader("CO-OP & VERSUS")
                Button { showingLobby = true } label: {
                    Text("OPEN LOBBY").pixelText(size: 13, color: .white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color(hex: "4A7BA8"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                Text("Study together (your friends' characters join your meadow) or duel a deck head-to-head. Needs migrations 0008/0009 deployed.")
                    .font(.custom(MitoFont.regular, size: 11))
                    .foregroundStyle(Color(hex: "6B4324"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 420)
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t).pixelText(size: 10, color: Color(hex: "3A2A18"))
            .padding(.top, 4)
    }

    private func friendRow(_ edge: FriendEdge, trailing: AnyView) -> some View {
        HStack {
            Text(edge.displayName).font(.custom(MitoFont.regular, size: 15))
                .foregroundStyle(Color(hex: "3A2A18"))
            Spacer()
            trailing
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(hex: "DCC79A"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }

    private func load() async {
        guard BetaConfig.premiumActive, backend.isReady, !loading else { return }
        loading = true; defer { loading = false }
        myCode = (try? await backend.myFriendCode()) ?? "—"
        friends = (try? await backend.fetchFriends()) ?? []
        league = (try? await backend.fetchLeague()) ?? []
    }

    private func add() async {
        let code = addCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count >= 4 else { message = "Enter a friend code."; return }
        do {
            guard let found = try await backend.findFriend(byCode: code) else {
                message = "No scholar with that code."; return
            }
            try await backend.sendFriendRequest(to: found.id)
            message = "Request sent to \(found.displayName)."
            addCode = ""
            await load()
        } catch {
            message = "Couldn't send request."
        }
    }

    private func accept(_ edge: FriendEdge) async {
        try? await backend.acceptFriendRequest(from: edge.friend_id)
        await load()
    }
}

// MARK: - Lobby realtime service

/// One member's live presence in a lobby: who they are + which characters of
/// theirs should spawn for everyone.
struct LobbyPresence: Codable, Identifiable {
    let userId: String
    let displayName: String
    let characterIds: [String]
    var id: String { userId }
}

/// A live in-lobby game event (co-op focus ticks, PvP answer/damage/turn).
/// Deliberately flat + flexible so one broadcast event covers every mode.
struct LobbyEvent: Codable {
    let kind: String          // "focusStart" | "answer" | "damage" | "turn" | "ready" | "start" | "win"
    let from: String          // sender userId
    var number: Int?          // damage / hp / index
    var text: String?         // card id / ability id
    var flag: Bool?           // correct? / ready?
}

/// Wraps a Supabase Realtime channel for a lobby: tracks presence (the live
/// roster + everyone's characters) and relays game events. Co-op spawn, co-op
/// sessions, and PvP all read from this one object.
@MainActor
final class LobbyService: ObservableObject {
    static let shared = LobbyService()

    @Published private(set) var members: [LobbyPresence] = []
    @Published private(set) var lobby: LobbyRecord?
    @Published private(set) var connected = false
    /// Most recent game event received (PvP/coop sessions observe this).
    @Published var lastEvent: LobbyEvent?

    private var channel: RealtimeChannelV2?
    private var roster: [String: LobbyPresence] = [:]
    private var streamTasks: [Task<Void, Never>] = []
    private var me: LobbyPresence?

    var isHost: Bool {
        guard let lobby, let me else { return false }
        return lobby.host.uuidString == me.userId
    }

    var myUserID: String { me?.userId ?? "" }

    func connect(to lobby: LobbyRecord, me: LobbyPresence) async {
        await disconnect()
        self.lobby = lobby
        self.me = me
        roster = [:]
        members = []

        let ch = MitoBackend.shared.client.channel("lobby:\(lobby.code)")
        channel = ch

        let presenceTask = Task { [weak self] in
            for await change in ch.presenceChange() {
                await self?.applyPresence(change)
            }
        }
        let eventTask = Task { [weak self] in
            for await json in ch.broadcastStream(event: "game") {
                await self?.applyEvent(json)
            }
        }
        streamTasks = [presenceTask, eventTask]

        await ch.subscribe()
        try? await ch.track(me)
        connected = true
    }

    func disconnect() async {
        streamTasks.forEach { $0.cancel() }
        streamTasks = []
        if let ch = channel {
            await ch.untrack()
            await ch.unsubscribe()
        }
        channel = nil
        connected = false
        lobby = nil
        roster = [:]
        members = []
    }

    func send(_ event: LobbyEvent) async {
        try? await channel?.broadcast(event: "game", message: event)
    }

    private func applyPresence(_ action: any PresenceAction) {
        for (key, presence) in action.joins {
            if let p = try? presence.decodeState(as: LobbyPresence.self) {
                roster[key] = p
            }
        }
        for (key, _) in action.leaves {
            roster.removeValue(forKey: key)
        }
        members = Array(roster.values)
    }

    private func applyEvent(_ json: JSONObject) {
        // The broadcast callback yields the outer envelope {type,event,payload};
        // our LobbyEvent is the inner `payload`.
        guard let inner = json["payload"],
              let data = try? JSONEncoder().encode(inner),
              let event = try? JSONDecoder().decode(LobbyEvent.self, from: data) else { return }
        lastEvent = event
    }

    /// Build my presence from the signed-in user + active party.
    func makePresence() async -> LobbyPresence? {
        guard let id = MitoBackend.shared.currentUserID else { return nil }
        let name = await MitoBackend.shared.myDisplayName()
        return LobbyPresence(userId: id.uuidString, displayName: name,
                             characterIds: BattleRules.partyHeroes.map(\.id))
    }
}

// MARK: - Lobby UI

/// Create or join a lobby, see the live roster, and launch co-op / versus.
struct LobbyView: View {
    @ObservedObject var backend: MitoBackend
    @Binding var isPresented: Bool
    @ObservedObject private var service = LobbyService.shared

    @State private var joinCode = ""
    @State private var busy = false
    @State private var message = ""
    @State private var duel: DuelStart?

    var body: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    Text(service.lobby == nil ? "CO-OP & VERSUS" : "LOBBY \(service.lobby!.code)")
                        .pixelText(size: 15, color: Color(hex: "3A2A18"))
                    Spacer()
                    Button { Task { await close() } } label: {
                        Text("X").pixelText(size: 13, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                    }.buttonStyle(.plain)
                }

                if service.lobby == nil {
                    lobbyPicker
                } else {
                    lobbyRoom
                }

                if !message.isEmpty {
                    Text(message).font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324")).multilineTextAlignment(.center)
                }
            }
            .padding(18)
            .frame(width: 330)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
        }
        .onReceive(service.$lastEvent) { ev in
            // Guest side: host picked a deck → drop into the duel.
            guard let ev, ev.kind == "start", ev.from != service.myUserID,
                  let deckID = ev.text, let seed = ev.number, duel == nil else { return }
            duel = DuelStart(deckID: deckID, seed: UInt64(seed))
        }
        .fullScreenCover(item: $duel) { d in
            PvPDuelView(start: d, lobby: service.lobby, duel: $duel)
        }
    }

    private var lobbyPicker: some View {
        VStack(spacing: 12) {
            Text("Invite a friend to study together or duel a deck head-to-head.")
                .font(.custom(MitoFont.regular, size: 14))
                .foregroundStyle(Color(hex: "4A2F1C")).multilineTextAlignment(.center)

            bigButton("✦ CREATE CO-OP ROOM", Color(hex: "4A8A3C")) { Task { await create(mode: "coop") } }
            bigButton("⚔ CREATE VERSUS ROOM", Color(hex: "C84A3A")) { Task { await create(mode: "pvp") } }

            Text("OR JOIN A CODE").pixelText(size: 9, color: Color(hex: "6B4324")).padding(.top, 4)
            HStack(spacing: 8) {
                TextField("CODE", text: $joinCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .authInputStyle()
                Button { Task { await join() } } label: {
                    Text("JOIN").pixelText(size: 12, color: .white)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(Color(hex: "4A7BA8"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }.buttonStyle(.plain)
            }
        }
        .disabled(busy)
    }

    private var lobbyRoom: some View {
        VStack(spacing: 10) {
            Text("SHARE CODE").pixelText(size: 9, color: Color(hex: "6B4324"))
            Text(service.lobby?.code ?? "")
                .pixelText(size: 26, color: Color(hex: "3A2A18")).textSelection(.enabled)

            Text("IN THE ROOM (\(service.members.count))")
                .pixelText(size: 9, color: Color(hex: "6B4324")).padding(.top, 4)
            ForEach(service.members) { m in
                HStack {
                    Text(m.displayName).font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "3A2A18"))
                    Spacer()
                    Text("\(m.characterIds.count) heroes").pixelText(size: 8, color: Color(hex: "8A6B42"))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color(hex: "DCC79A"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }

            if service.lobby?.mode == "coop" {
                Text("Your friends' characters now wander your home meadow. Start a focus session together from the home screen!")
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "4A2F1C")).multilineTextAlignment(.center).padding(.top, 4)
            } else if service.isHost {
                Text("PICK A DECK TO DUEL").pixelText(size: 9, color: Color(hex: "6B4324")).padding(.top, 4)
                ForEach(ReviewSession.shared.deckSummaries) { deck in
                    Button { startDuel(deckID: deck.id) } label: {
                        HStack {
                            Text(deck.name).font(.custom(MitoFont.regular, size: 14))
                                .foregroundStyle(Color(hex: "3A2A18"))
                            Spacer()
                            Text("\(deck.cardCount) cards").pixelText(size: 8, color: Color(hex: "8A6B42"))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(hex: "C7D7B0"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.members.count < 2)
                }
                if service.members.count < 2 {
                    Text("Waiting for an opponent to join…")
                        .font(.custom(MitoFont.regular, size: 12)).foregroundStyle(Color(hex: "6B4324"))
                }
            } else {
                Text("Waiting for the host to pick a deck…")
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "4A2F1C")).multilineTextAlignment(.center).padding(.top, 4)
            }

            bigButton("LEAVE ROOM", Color(hex: "6B4324")) { Task { await leave() } }
        }
    }

    private func startDuel(deckID: String) {
        let seed = Int.random(in: 1...2_000_000_000)
        duel = DuelStart(deckID: deckID, seed: UInt64(seed))
        Task { await service.send(LobbyEvent(kind: "start", from: service.myUserID, number: seed, text: deckID)) }
    }

    private func bigButton(_ title: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).pixelText(size: 13, color: .white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(color).overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        }.buttonStyle(.plain)
    }

    private func create(mode: String) async {
        guard backend.isReady, !busy else { message = "Sign in first."; return }
        busy = true; defer { busy = false }
        do {
            let party = BattleRules.partyHeroes.map(\.id)
            let lobby = try await backend.createLobby(mode: mode, characterIDs: party)
            guard let me = await service.makePresence() else { return }
            await service.connect(to: lobby, me: me)
        } catch { message = "Couldn't create room." }
    }

    private func join() async {
        let code = joinCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard backend.isReady, code.count >= 4, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let party = BattleRules.partyHeroes.map(\.id)
            guard let _ = try await backend.joinLobby(code: code, characterIDs: party),
                  let lobby = try await backend.fetchLobby(code: code) else {
                message = "No open room with that code."; return
            }
            guard let me = await service.makePresence() else { return }
            await service.connect(to: lobby, me: me)
        } catch { message = "Couldn't join room." }
    }

    private func leave() async {
        if let id = service.lobby?.id {
            if service.isHost { try? await backend.closeLobby(id) }
            else { try? await backend.leaveLobby(id) }
        }
        await service.disconnect()
    }

    private func close() async {
        // Leaving the sheet keeps you connected (co-op spawn persists on home);
        // only fully leave via the LEAVE button.
        isPresented = false
    }
}

// MARK: - PvP duel

struct DuelStart: Identifiable, Equatable {
    let deckID: String
    let seed: UInt64
    var id: String { "\(deckID)-\(seed)" }
}

/// Multiple-choice options for a card outside the battle screen (PvP). Correct
/// answer + up to three distractors (cached or sibling-card answers), shuffled
/// deterministically per card.
func multipleChoiceOptions(for card: ReviewCard, in pool: [ReviewCard]) -> [String] {
    let correctKey = AnswerGrading.normalize(card.back)
    var distractors: [String] = (card.choices?.isEmpty == false) ? card.choices! : []
    if distractors.count < 3 {
        var rng = SeededGenerator(seed: card.id)
        let siblings = pool
            .filter { $0.id != card.id && AnswerGrading.normalize($0.back) != correctKey }
            .map(\.back)
            .shuffled(using: &rng)
        distractors += siblings
    }
    var seen: Set<String> = [correctKey]
    var picked: [String] = []
    for d in distractors {
        let k = AnswerGrading.normalize(d)
        guard !k.isEmpty, !seen.contains(k) else { continue }
        seen.insert(k); picked.append(d)
        if picked.count == 3 { break }
    }
    var rng = SeededGenerator(seed: card.id)
    return ([card.back] + picked).shuffled(using: &rng)
}

/// Head-to-head deck duel. Both players answer the SAME deck in the same seeded
/// order; a correct answer damages the opponent. Wrong answers recirculate
/// (Quizlet-Learn mastery) and deal no damage. First to drain the opponent's HP
/// wins. Ephemeral — never touches FSRS. Each client is authoritative over the
/// damage it deals and relays it over the lobby's realtime channel.
struct PvPDuelView: View {
    let start: DuelStart
    let lobby: LobbyRecord?
    @Binding var duel: DuelStart?
    @ObservedObject private var service = LobbyService.shared

    @State private var queue: [ReviewCard] = []
    @State private var myHP = 100
    @State private var oppHP = 100
    @State private var finished = false
    @State private var won = false
    @State private var resolving = false

    private let maxHP = 100
    private let hitDamage = 18

    private var opponentID: UUID? {
        service.members.first { $0.userId != service.myUserID }.flatMap { UUID(uuidString: $0.userId) }
    }
    private var opponentName: String {
        service.members.first { $0.userId != service.myUserID }?.displayName ?? "Opponent"
    }

    var body: some View {
        ZStack {
            Color(hex: "1A130A").ignoresSafeArea()
            VStack(spacing: 12) {
                hpBar(label: opponentName.uppercased(), hp: oppHP, color: Color(hex: "C84A3A"))
                Spacer(minLength: 8)

                if finished {
                    resultCard
                } else if let card = queue.first {
                    VStack(spacing: 10) {
                        Text("ANSWER TO ATTACK").pixelText(size: 10, color: Color(hex: "FFD24D"))
                        Text(card.front)
                            .font(.custom(MitoFont.regular, size: 18))
                            .foregroundStyle(Color(hex: "F4E6C0"))
                            .multilineTextAlignment(.center)
                            .padding().frame(maxWidth: .infinity)
                            .background(Color(hex: "2A1B0E"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        MultipleChoicePanel(
                            options: multipleChoiceOptions(for: card, in: queue),
                            correctAnswer: card.back,
                            onReveal: {},
                            onResolved: { rating in resolve(correct: rating != .again) }
                        )
                        .id(card.id)
                    }
                    .padding(.horizontal, 16)
                } else {
                    Text("Loading deck…").pixelText(size: 12, color: .white)
                }

                Spacer(minLength: 8)
                hpBar(label: "YOU", hp: myHP, color: Color(hex: "4A9B3F"))
                Button { Task { await quit() } } label: {
                    Text(finished ? "BACK TO LOBBY" : "FORFEIT")
                        .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color(hex: "6B4324"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .onAppear(perform: loadDeck)
        .onReceive(service.$lastEvent) { ev in handle(ev) }
    }

    private func hpBar(label: String, hp: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).pixelText(size: 10, color: Color(hex: "F4E6C0"))
                Spacer()
                Text("\(max(0, hp))/\(maxHP)").pixelText(size: 9, color: Color(hex: "F4E6C0"))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(hex: "2A1A0D"))
                    Rectangle().fill(color)
                        .frame(width: geo.size.width * CGFloat(max(0, hp)) / CGFloat(maxHP))
                }
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }
            .frame(height: 16)
        }
    }

    private var resultCard: some View {
        VStack(spacing: 12) {
            Text(won ? "VICTORY!" : "DEFEAT")
                .pixelText(size: 22, color: won ? Color(hex: "FFD24D") : Color(hex: "C84A3A"))
            Text(won ? "You out-studied \(opponentName)." : "\(opponentName) was faster this time.")
                .font(.custom(MitoFont.regular, size: 15))
                .foregroundStyle(Color(hex: "F4E6C0")).multilineTextAlignment(.center)
        }
        .padding(20)
        .background(Color(hex: "2A1B0E"))
        .overlay(Rectangle().stroke(Color(hex: won ? "FFD24D" : "C84A3A"), lineWidth: 4))
    }

    private func loadDeck() {
        guard queue.isEmpty else { return }
        let pool = ReviewSession.shared.allCards()
        var cards = pool.filter { $0.deckID == start.deckID }
        if cards.isEmpty { cards = pool }
        var rng = SeededGenerator(seed: start.seed == 0 ? 1 : start.seed)
        queue = cards.shuffled(using: &rng)
    }

    private func resolve(correct: Bool) {
        guard !finished, !queue.isEmpty else { return }
        if correct {
            oppHP = max(0, oppHP - hitDamage)
            AudioManager.shared.play(.gradeGood); Haptics.success()
            let dmg = hitDamage
            Task { await service.send(LobbyEvent(kind: "damage", from: service.myUserID, number: dmg)) }
            queue.removeFirst()
            if oppHP <= 0 {
                finished = true; won = true
                Task {
                    await service.send(LobbyEvent(kind: "win", from: service.myUserID))
                    await recordResult(win: true)
                }
            }
        } else {
            // Missed card recirculates to the back; no damage.
            let missed = queue.removeFirst()
            queue.append(missed)
            AudioManager.shared.play(.gradeAgain); Haptics.warning()
        }
        if queue.isEmpty { loadDeck() } // refill so the duel never stalls
    }

    private func handle(_ ev: LobbyEvent?) {
        guard let ev, ev.from != service.myUserID, !finished else { return }
        switch ev.kind {
        case "damage":
            myHP = max(0, myHP - (ev.number ?? 0))
            if myHP <= 0 { finished = true; won = false }
        case "win":
            finished = true; won = false
        default:
            break
        }
    }

    private func recordResult(win: Bool) async {
        guard let opp = opponentID else { return }
        try? await MitoBackend.shared.recordPvPResult(
            lobbyID: lobby?.id, deckID: UUID(uuidString: start.deckID), opponent: opp, didWin: win)
    }

    private func quit() async {
        if !finished, let opp = opponentID {
            try? await MitoBackend.shared.recordPvPResult(
                lobbyID: lobby?.id, deckID: UUID(uuidString: start.deckID), opponent: opp, didWin: false)
        }
        duel = nil
    }
}



















































