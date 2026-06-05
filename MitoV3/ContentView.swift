import SwiftUI

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
    // Players start empty and earn their way up; the real values load from the
    // profile wallet once signed in (see loadWallet).
    @State private var atp = 0
    @State private var gold = 0
    @State private var gems = 0
    @State private var biomass = 0
    @State private var shards = 0
    @State private var walletSaveTask: Task<Void, Never>?
    @AppStorage("mito.admitted") private var admitted = false
    @AppStorage("mito.onboarded") private var onboarded = false
    @AppStorage("mito.goal") private var goal = ""

    private var launchArgs: [String] { ProcessInfo.processInfo.arguments }
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
            if forceGate || (!bypassGate && !admitted && !forceOnboard) {
                WaitlistGate(backend: backend) { withAnimation { admitted = true } }
            } else if forceOnboard || (!bypassGate && !onboarded) {
                OnboardingView(backend: backend, goal: $goal) {
                    withAnimation { onboarded = true }
                    selectedTab = .home
                }
            }
        }
        .preferredColorScheme(.dark)
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
                        HomeScreen(atp: $atp, backend: backend)
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
        .task {
            await backend.bootstrapExistingSession()
            // Load cloud decks/FSRS state and mirror future grades to Supabase.
            await backend.attachSync(to: .shared)
            await loadWallet()
            await backend.logEvent("app_open")
        }
        .onChange(of: atp) { _, _ in scheduleWalletSave() }
        .onChange(of: gold) { _, _ in scheduleWalletSave() }
        .onChange(of: gems) { _, _ in scheduleWalletSave() }
        .onChange(of: biomass) { _, _ in scheduleWalletSave() }
        .onChange(of: shards) { _, _ in scheduleWalletSave() }
    }

    /// Pull the persisted wallet once signed in; no-ops offline / pre-migration.
    private func loadWallet() async {
        guard backend.isReady, let w = try? await backend.fetchWallet() else { return }
        atp = w.atp; gold = w.gold; gems = w.gems; biomass = w.biomass; shards = w.shards
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

struct AuthSheet: View {
    @ObservedObject var backend: MitoBackend
    @Binding var isPresented: Bool

    @State private var email = ""
    @State private var password = ""
    @State private var message = ""
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACCOUNT")
                        .pixelText(size: 17, color: Color(hex: "3A2A18"))
                    Text(backend.isReady ? "Cloud save connected." : "Sign in to sync decks and progress.")
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
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

            if !message.isEmpty {
                Text(message)
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .fixedSize(horizontal: false, vertical: true)
            }

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

            if backend.isReady {
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
            }
        }
        .padding(16)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }

    private var canSubmit: Bool {
        !isWorking && email.contains("@") && password.count >= 6
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

    private enum AuthAction {
        case signIn
        case signUp
    }
}

struct GeneralSettingsSheet: View {
    @ObservedObject var backend: MitoBackend
    @Binding var isPresented: Bool
    let showAuth: () -> Void

    @State private var soundEnabled = true
    @State private var animationsEnabled = true

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
                    title: backend.isReady ? "ACCOUNT SYNCED" : "LOGIN",
                    detail: backend.isReady ? "Manage cloud save account." : "Sign in to sync decks and progress.",
                    value: backend.isReady ? "OPEN" : "SIGN IN",
                    action: showAuth
                )

                SettingsToggleRow(title: "SOUND", detail: "Menu and battle effects.", isOn: $soundEnabled)
                SettingsToggleRow(title: "ANIMATION", detail: "Idle character movement.", isOn: $animationsEnabled)
            }
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



















































