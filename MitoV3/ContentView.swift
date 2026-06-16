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
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var tutorialMgr = TutorialManager.shared
    @ObservedObject private var storyMgr = CampaignStoryManager.shared
    /// A dimmed dialogue is on screen — hide the app chrome (header + nav tray)
    /// so it doesn't bleed through behind the dialogue card.
    private var dialogueActive: Bool { tutorialMgr.isSaying || storyMgr.isSaying }
    /// Launch-time tasks must run once, even though `.id(language)` rebuilds the
    /// tree on a language switch.
    private static var didRunLaunchTasks = false
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
                .overlayPreferenceValue(TutorialAnchorKey.self) { prefs in
                    GeometryReader { geo in
                        // Resolve anchors AND draw the overlay in the same full-screen
                        // coordinate space so spotlight holes line up with real controls.
                        TutorialHost(anchors: prefs.mapValues { geo[$0] }, size: geo.size)
                    }
                    .ignoresSafeArea()
                }

            // Campaign story scenes (inter-character dialogue around stages).
            CampaignStoryHost()
                .ignoresSafeArea()
                .zIndex(70)

            // Waitlist / "private beta" gate removed — app opens straight in.
            if forceOnboard || (!bypassGate && !onboarded) {
                OnboardingView(backend: backend, goal: $goal) {
                    withAnimation { onboarded = true }
                    selectedTab = .home
                    TutorialManager.shared.start(goal: goal)
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
        .environment(\.locale, Locale(identifier: loc.language.rawValue))
        // Rebuild the whole tree when the language changes so every `L(...)`
        // lookup re-evaluates instantly.
        .id(loc.language)
        .animation(.easeOut(duration: 0.2), value: notifications.showPrimer)
        .onAppear {
            GameMigration.runIfNeeded()
            GameMigration.runTrustMigrationIfNeeded()
            if forceTutorial || (!bypassGate && onboarded && !tutorialSeen) {
                TutorialManager.shared.start(goal: goal)
            }
        }
    }

    private var appShell: some View {
        GeometryReader { proxy in
            ZStack {
                Color.mitoWoodDarkest.ignoresSafeArea()

                VStack(spacing: 0) {
                    HeaderChrome(atp: atp, gold: gold, gems: gems, topInset: proxy.safeAreaInsets.top)
                        .frame(height: proxy.safeAreaInsets.top + 52)
                        .opacity(dialogueActive ? 0 : 1)
                        .zIndex(2)
                    
                    TabView(selection: $selectedTab) {
                        ShopScreen(atp: $atp, gold: $gold, gems: $gems, biomass: $biomass, shards: $shards)
                            .tag(AppTab.shop)
                        TeamScreen(atp: $atp, gold: $gold, biomass: $biomass, selectedTab: selectedTab)
                            .tag(AppTab.team)
                        HomeScreen(atp: $atp, gold: $gold, gems: $gems, backend: backend, selectedTab: selectedTab)
                            .tag(AppTab.home)
                        BattleScreen(atp: $atp, gold: $gold, biomass: $biomass, selectedTab: selectedTab)
                            .tag(AppTab.battle)
                        CardsScreen(selectedTab: selectedTab)
                            .tag(AppTab.cards)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    DeviceBottomBar(selectedTab: $selectedTab)
                        .frame(height: 74)
                        .opacity(dialogueActive ? 0 : 1)
                        .zIndex(2)
                }
                .ignoresSafeArea(edges: [.top, .bottom])
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear { AudioManager.shared.startMusic(.home) }
        .task {
            guard !Self.didRunLaunchTasks else { return }
            Self.didRunLaunchTasks = true
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
                ReviewSession.shared.reloadPersisted()
                StreakStore.shared.reconcile()
                DailyQuests.shared.rollover()
                WidgetBridge.sync()
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
        .onChange(of: selectedTab) { old, new in
            guard old != new else { return }
            AudioManager.shared.play(.uiTap, volume: 0.7)
            Haptics.select()
            TutorialManager.shared.complete("tab.\(new.rawValue)")
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
