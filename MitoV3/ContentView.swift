import SwiftUI

struct ContentView: View {
    @StateObject private var backend = MitoBackend.shared
    @State private var selectedTab: AppTab = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitestReview") { return .battle }
        if ProcessInfo.processInfo.arguments.contains("-uitestCards") { return .cards }
        #endif
        return .home
    }()
    @State private var atp = 9999
    @State private var gold = 9927
    @State private var gems = 120
    @State private var biomass = 60
    @State private var shards = 24

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.mitoWoodDarkest.ignoresSafeArea()

                VStack(spacing: 0) {
                    HeaderChrome(atp: atp, gold: gold, gems: gems, topInset: proxy.safeAreaInsets.top)
                        .frame(height: proxy.safeAreaInsets.top + 52)
                        .zIndex(2)
                    
                    TabView(selection: $selectedTab) {
                        ShopScreen(gold: $gold, gems: $gems, biomass: $biomass, shards: $shards)
                            .tag(AppTab.shop)
                        TeamScreen(atp: $atp, gold: $gold)
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
        }
    }
}

private struct AuthSheet: View {
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

private struct GeneralSettingsSheet: View {
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

private struct Hero: Identifiable {
    let id: String
    let asset: String
    let name: String
    let role: String
    let level: Int
    let hp: Int
    let attack: Int
    let defense: Int
    let color: Color
    let lore: String

    func applying(_ progress: CharacterProgress) -> Hero {
        Hero(
            id: id,
            asset: asset,
            name: name,
            role: role,
            level: progress.level,
            hp: progress.hp,
            attack: progress.attack,
            defense: progress.defense,
            color: color,
            lore: lore
        )
    }
}

private struct CharacterProgress {
    var level: Int
    var hp: Int
    var attack: Int
    var defense: Int

    init(level: Int, hp: Int, attack: Int, defense: Int) {
        self.level = level
        self.hp = hp
        self.attack = attack
        self.defense = defense
    }

    init(hero: Hero) {
        self.init(level: hero.level, hp: hero.hp, attack: hero.attack, defense: hero.defense)
    }

    init(record: CharacterProgressRecord) {
        self.init(level: record.level, hp: record.hp, attack: record.attack, defense: record.defense)
    }

    mutating func levelUp() {
        level += 1
        hp += 5
        attack += 3
        defense += 2
    }
}

private struct BattleAbility: Identifiable, Equatable {
    let id: String
    let name: String
    let damage: Int
    let detail: String
    let color: Color
}

private enum BattleAbilityBook {
    static func abilities(for hero: Hero) -> [BattleAbility] {
        switch hero.id {
        case "mito":
            return [
                BattleAbility(id: "mito-atp-spark", name: "ATP Spark", damage: 24, detail: "Mito zaps the target with stored focus energy.", color: Color(hex: "F48FB1")),
                BattleAbility(id: "mito-cristae-burst", name: "Cristae Burst", damage: 34, detail: "A charged burst erupts from Mito's folds.", color: Color(hex: "FFD24D")),
                BattleAbility(id: "mito-powerhouse", name: "Powerhouse", damage: 46, detail: "Mito overclocks for a heavy strike.", color: Color(hex: "E77878"))
            ]
        case "cloro":
            return [
                BattleAbility(id: "cloro-sunbeam", name: "Sunbeam", damage: 22, detail: "Chloro fires a clean beam of light.", color: Color(hex: "A8D95B")),
                BattleAbility(id: "cloro-growth-pop", name: "Growth Pop", damage: 31, detail: "Stored light pops into rapid damage.", color: Color(hex: "7BB55C")),
                BattleAbility(id: "cloro-photon-bloom", name: "Photon Bloom", damage: 42, detail: "A bright bloom hits the whole field.", color: Color(hex: "CFEF74"))
            ]
        case "astro":
            return [
                BattleAbility(id: "astro-signal-tap", name: "Signal Tap", damage: 23, detail: "Astro taps a fast support signal.", color: Color(hex: "A98FD0")),
                BattleAbility(id: "astro-memory-web", name: "Memory Web", damage: 33, detail: "A web of recall snaps onto the enemy.", color: Color(hex: "C7A6F2")),
                BattleAbility(id: "astro-neural-assist", name: "Neural Assist", damage: 40, detail: "Astro boosts the team's next thought.", color: Color(hex: "8B6BD9"))
            ]
        case "dendri":
            return [
                BattleAbility(id: "dendri-scout-ping", name: "Scout Ping", damage: 20, detail: "Dendri marks a weak point.", color: Color(hex: "E8C64A")),
                BattleAbility(id: "dendri-branch-snap", name: "Branch Snap", damage: 30, detail: "A branching strike catches the enemy.", color: Color(hex: "F2D85B")),
                BattleAbility(id: "dendri-antigen-call", name: "Antigen Call", damage: 39, detail: "Dendri calls in a focused response.", color: Color(hex: "D7A72F"))
            ]
        case "neuro":
            return [
                BattleAbility(id: "neuro-spark", name: "Neuro Spark", damage: 21, detail: "Neuro sends a sharp signal forward.", color: Color(hex: "5FA3D4")),
                BattleAbility(id: "neuro-axon-rush", name: "Axon Rush", damage: 32, detail: "A signal rush slams into the target.", color: Color(hex: "7EB9F0")),
                BattleAbility(id: "neuro-synapse-storm", name: "Synapse Storm", damage: 41, detail: "Neuro chains a storm of tiny sparks.", color: Color(hex: "4D7FD4"))
            ]
        default:
            return [
                BattleAbility(id: "\(hero.id)-tap", name: "Study Tap", damage: 20, detail: "\(hero.name) keeps the review moving.", color: hero.color),
                BattleAbility(id: "\(hero.id)-burst", name: "Focus Burst", damage: 30, detail: "\(hero.name) turns recall into damage.", color: hero.color),
                BattleAbility(id: "\(hero.id)-combo", name: "Recall Combo", damage: 40, detail: "\(hero.name) lands a clean combo.", color: hero.color)
            ]
        }
    }
}

private struct Deck: Identifiable {
    let id: String
    let name: String
    let cards: Int
    let tags: [String]
    let color: Color
}

private struct Flashcard: Identifiable, Equatable {
    let id: String
    var front: String
    var back: String
    var tags: [String]
}

private struct Stage: Identifiable {
    let id: Int
    let name: String
    let status: StageStatus
    let x: CGFloat
    let y: CGFloat
    let difficulty: String
}

private enum StageStatus {
    case cleared
    case active
    case locked

    var asset: String {
        switch self {
        case .cleared: "node-cleared"
        case .active: "node-active"
        case .locked: "node-locked"
        }
    }
}

private enum DataSet {
    static let heroes: [Hero] = [
        Hero(id: "mito", asset: "hero-mito-hop", name: "Mito", role: "Support", level: 12, hp: 48, attack: 18, defense: 14, color: Color(hex: "E77878"), lore: "A bean-shaped mitochondria helper with bright cristae. Turns focus into ATP and keeps the party steady when long study sessions get rough."),
        Hero(id: "cloro", asset: "hero-chloroplast-hop", name: "Chloro", role: "Striker", level: 11, hp: 42, attack: 22, defense: 11, color: Color(hex: "7BB55C"), lore: "A chloroplast striker who stores momentum between waves. Quick, bright, and built for clean bursts of damage."),
        Hero(id: "astro", asset: "hero-astrocyte-hop", name: "Astro", role: "Mage", level: 10, hp: 36, attack: 24, defense: 9, color: Color(hex: "A98FD0"), lore: "A star-shaped astrocyte mage who supports sharp thinking with quick bursts of cellular energy."),
        Hero(id: "dendri", asset: "hero-dendritic-cell-hop", name: "Dendri", role: "Support", level: 9, hp: 38, attack: 16, defense: 12, color: Color(hex: "E8C64A"), lore: "A branching dendritic-cell scout who keeps the team alert and turns small wins into streaks."),
        Hero(id: "neuro", asset: "hero-neuron-hop", name: "Neuro", role: "Tank", level: 13, hp: 56, attack: 14, defense: 22, color: Color(hex: "5FA3D4"), lore: "A sturdy neuron buffer with branching signals. Soaks pressure while fragile allies line up the next answer."),
        Hero(id: "bcell", asset: "hero-b-cell-hop", name: "B Cell", role: "Scholar", level: 8, hp: 34, attack: 17, defense: 10, color: Color(hex: "F4C6B8"), lore: "A careful immune scholar who translates effort into growth. Not flashy, but every session becomes something useful.")
    ]

    static let decks: [Deck] = [
        Deck(id: "bio", name: "Biology 220", cards: 6, tags: ["cell", "dna", "mitosis"], color: Color(hex: "6DB04C")),
        Deck(id: "phys", name: "Physics formulas", cards: 4, tags: ["kinematics", "energy", "waves"], color: Color(hex: "5FA3D4")),
        Deck(id: "jp", name: "Japanese vocab", cards: 3, tags: ["n5", "verbs", "nouns"], color: Color(hex: "E7A0B8")),
        Deck(id: "orgo", name: "Organic mechanisms", cards: 2, tags: ["sn1", "sn2", "e1"], color: Color(hex: "D4873A"))
    ]

    static let stages: [Stage] = [
        Stage(id: 1, name: "Petri Plain", status: .cleared, x: 0.50, y: 0.92, difficulty: "EASY"),
        Stage(id: 2, name: "Membrane Marsh", status: .cleared, x: 0.80, y: 0.80, difficulty: "EASY"),
        Stage(id: 3, name: "Nucleus Hollow", status: .cleared, x: 0.32, y: 0.70, difficulty: "NORMAL"),
        Stage(id: 4, name: "Mitochondria Cave", status: .active, x: 0.65, y: 0.58, difficulty: "NORMAL"),
        Stage(id: 5, name: "Ribosome Ridge", status: .locked, x: 0.30, y: 0.47, difficulty: "HARD"),
        Stage(id: 6, name: "Lysosome Lair", status: .locked, x: 0.64, y: 0.35, difficulty: "HARD"),
        Stage(id: 7, name: "Vacuole Vale", status: .locked, x: 0.32, y: 0.23, difficulty: "BOSS"),
        Stage(id: 8, name: "Spike Citadel", status: .locked, x: 0.68, y: 0.10, difficulty: "BOSS")
    ]
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

private struct HomeScreen: View {
    @Binding var atp: Int
    @ObservedObject var backend: MitoBackend
    @State private var timerOpen = false
    @State private var mode: StudyMode = .focus
    @State private var remaining = StudyMode.focus.seconds
    @State private var isRunning = false
    @State private var completed = false
    @State private var showingSettings = false
    @State private var showingAuth = false

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

                ForEach(StudyWanderer.all) { wanderer in
                    StudyWanderingCharacter(wanderer: wanderer, canvasSize: proxy.size)
                }

                VStack {
                    HStack {
                        Spacer()
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
                    .padding(.trailing, 28)
                    Spacer()
                }
                .zIndex(2)

                VStack {
                    Spacer()
                    if timerOpen {
                        TimerPanel(
                            mode: $mode,
                            remaining: $remaining,
                            isRunning: $isRunning,
                            completed: $completed,
                            close: { timerOpen = false },
                            reward: { atp += mode.reward }
                        )
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                timerOpen = true
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

                if timerOpen && !isRunning {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.18)) {
                                timerOpen = false
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
            }
            .onReceive(ticker) { _ in
                guard isRunning else { return }
                if remaining > 0 {
                    remaining -= 1
                } else {
                    isRunning = false
                    completed = true
                    if mode != .breakTime {
                        atp += mode.reward
                    }
                }
            }
        }
    }
}

private enum StudyMode: String, CaseIterable, Identifiable {
    case focus
    case deep
    case breakTime

    var id: String { rawValue }
    var label: String {
        switch self {
        case .focus: "FOCUS"
        case .deep: "DEEP"
        case .breakTime: "BREAK"
        }
    }

    var seconds: Int {
        switch self {
        case .focus: 25 * 60
        case .deep: 50 * 60
        case .breakTime: 5 * 60
        }
    }

    var reward: Int {
        switch self {
        case .focus: 12
        case .deep: 28
        case .breakTime: 0
        }
    }
}

private struct TimerPanel: View {
    @Binding var mode: StudyMode
    @Binding var remaining: Int
    @Binding var isRunning: Bool
    @Binding var completed: Bool
    let close: () -> Void
    let reward: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("timer-panel")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()

                if !isRunning {
                    Button(action: close) {
                        Text("X")
                            .pixelText(size: 13, color: Color(hex: "3A2A18"))
                    }
                        .buttonStyle(.plain)
                        .position(x: proxy.size.width * 0.93, y: proxy.size.height * 0.10)
                }

                Rectangle()
                    .fill(Color(hex: "F4E6C0"))
                    .frame(width: proxy.size.width * 0.74, height: proxy.size.height * 0.24)
                    .position(x: proxy.size.width * 0.50, y: proxy.size.height * 0.30)

                Text(timeText)
                    .font(.custom(MitoFont.bold, size: min(44, proxy.size.width * 0.11)))
                    .foregroundStyle(Color(hex: "1F1408"))
                    .position(x: proxy.size.width * 0.50, y: proxy.size.height * 0.31)

                ForEach(Array(StudyMode.allCases.enumerated()), id: \.element.id) { index, item in
                    Button {
                        guard !isRunning else { return }
                        mode = item
                        remaining = item.seconds
                        completed = false
                    } label: {
                        Rectangle()
                            .fill(mode == item ? Color(hex: "FFD24D").opacity(0.18) : Color.clear)
                            .overlay(Rectangle().stroke(mode == item ? Color(hex: "FFD24D") : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .frame(width: proxy.size.width * 0.23, height: proxy.size.height * 0.12)
                    .position(x: proxy.size.width * (0.195 + CGFloat(index) * 0.26), y: proxy.size.height * 0.63)
                    .accessibilityLabel(item.label)
                }

                HStack(spacing: 10) {
                    ForEach(StudyMode.allCases) { item in
                        Button {
                            guard !isRunning else { return }
                            mode = item
                            remaining = item.seconds
                            completed = false
                        } label: {
                            Text(item.label)
                                .pixelText(size: 10, color: mode == item ? .white : Color(hex: "3A2A18"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(mode == item ? Color(hex: "6B9C4A") : Color(hex: "D8B884"))
                                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, proxy.size.width * 0.08)
                .position(x: proxy.size.width * 0.50, y: proxy.size.height * 0.64)
                .opacity(0.001)

                Button {
                    if completed {
                        completed = false
                        remaining = mode.seconds
                    } else {
                        isRunning.toggle()
                        if remaining <= 0 {
                            remaining = mode.seconds
                        }
                    }
                } label: {
                    Text(completed ? "AGAIN" : isRunning ? "PAUSE" : "STUDY")
                        .pixelText(size: 18, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(isRunning ? Color(hex: "C84A3A") : Color(hex: "4A8A3C"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, proxy.size.width * 0.08)
                .position(x: proxy.size.width * 0.50, y: proxy.size.height * 0.82)

                if !isRunning && !completed && mode.reward > 0 {
                    Text("+\(mode.reward) ATP")
                        .pixelText(size: 9, color: Color(hex: "FFD24D"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.45))
                        .position(x: proxy.size.width * 0.50, y: proxy.size.height * 0.94)
                }
            }
        }
        .aspectRatio(991.0 / 857.0, contentMode: .fit)
    }

    private var timeText: String {
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct ShopScreen: View {
    @Binding var gold: Int
    @Binding var gems: Int
    @Binding var biomass: Int
    @Binding var shards: Int

    var body: some View {
        ZStack {
            WoodBackground()
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Character(asset: "hero-mito-hop", size: 48)
                        .frame(width: 52, height: 52)
                        .background(Color(hex: "F0D6A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RIBO'S SHOP")
                            .pixelText(size: 15, color: Color(hex: "3A2A18"))
                        Text("\"Coins for the journey, gems for flair - but ATP? You earn that.\"")
                            .font(.custom(MitoFont.regular, size: 13))
                            .foregroundStyle(Color(hex: "5B442A"))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                .padding(.horizontal, 12)
                .padding(.top, 10)

                HStack(spacing: 6) {
                    ShopTab("DAILY", active: true)
                    ShopTab("RESOURCES", active: false)
                    ShopTab("COSMETICS", active: false)
                    ShopTab("SEASONAL", active: false)
                }
                .padding(.horizontal, 12)

                VStack(spacing: 12) {
                    ShopItemRow(icon: "treasure chest.fill", title: "Focus Chest", detail: "Free reward - unlocked by finishing a focus session.", price: "FREE\nCLAIM", accent: Color(hex: "F7C943")) {}
                    ShopItemRow(icon: "flask.fill", title: "ATP Flask", detail: "A small bottled boost. Once per day, coins only - studying still rules.", price: "100\nBUY", accent: Color(hex: "F7C943")) {
                        if gold >= 100 {
                            gold -= 100
                        }
                    }
                    ShopItemRow(icon: "circle.circle.fill", title: "Biomass Pouch", detail: "Today's discounted pouch for creature growth.", price: "60\n80", accent: Color(hex: "CFE49C")) {
                        if gold >= 60 {
                            gold -= 60
                            biomass += 12
                        }
                    }
                    ShopItemRow(icon: "diamond.fill", title: "Cloro Shard", detail: "Rotating shard offer - refreshes daily.", price: "220\nBUY", accent: Color(hex: "E3B8B8")) {
                        if gold >= 220 {
                            gold -= 220
                            shards += 3
                        }
                    }
                }
                .padding(.horizontal, 12)

                Text("Coins to progress · Gems to personalize")
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "B89868"))
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct TeamScreen: View {
    @Binding var atp: Int
    @Binding var gold: Int
    @State private var activePartySlots: [String?] = ["mito", "cloro", "astro", "dendri"]
    @State private var selectedHeroID: String?
    @State private var infoHero: Hero?
    @State private var characterProgress: [String: CharacterProgress] = [:]
    private let maxPartySize = 4
    private let upgradeCost = 340

    private var heroes: [Hero] {
        DataSet.heroes.map { hero in
            if let progress = characterProgress[hero.id] {
                return hero.applying(progress)
            }
            return hero
        }
    }

    private var activePartyIDs: [String] {
        activePartySlots.compactMap { $0 }
    }

    private var partyHeroes: [Hero] {
        activePartyIDs.compactMap { id in
            hero(for: id)
        }
    }

    private var reserveHeroes: [Hero] {
        heroes.filter { !activePartyIDs.contains($0.id) }
    }

    private var partyHP: Int {
        partyHeroes.reduce(0) { $0 + $1.hp }
    }

    private var partyAttack: Int {
        partyHeroes.reduce(0) { $0 + $1.attack }
    }

    private var partyDefense: Int {
        partyHeroes.reduce(0) { $0 + $1.defense }
    }

    private func hero(for id: String) -> Hero? {
        heroes.first { $0.id == id }
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "263544"), location: 0),
                        .init(color: Color(hex: "9ED1EE"), location: 0.34),
                        .init(color: Color(hex: "70BF4F"), location: 0.48),
                        .init(color: Color(hex: "2A6428"), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 7) {
                        HStack {
                            StatBlock(label: "HP", value: "\(partyHP)", color: Color(hex: "3F8A3D"))
                            Spacer()
                            StatBlock(label: "ATK", value: "\(partyAttack)", color: Color(hex: "D4873A"))
                            Spacer()
                            StatBlock(label: "DEF", value: "\(partyDefense)", color: Color(hex: "4277D9"))
                        }
                        .padding(.horizontal, 34)
                        .padding(.vertical, 7)
                        .background(Color(hex: "EAD4A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        .padding(.horizontal, 12)
                        .padding(.top, 6)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 2), alignment: .center, spacing: 8) {
                            ForEach(0..<maxPartySize, id: \.self) { slotIndex in
                                if
                                    slotIndex < activePartySlots.count,
                                    let heroID = activePartySlots[slotIndex],
                                    let hero = hero(for: heroID)
                                {
                                    let isSelected = selectedHeroID == hero.id

                                    Button {
                                        selectedHeroID = isSelected ? nil : hero.id
                                    } label: {
                                        TeamRosterCard(
                                            hero: hero,
                                            isInParty: true,
                                            isSelected: isSelected,
                                            compact: false
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(hero.name), active party slot \(slotIndex + 1)")
                                    .accessibilityIdentifier("team-character-\(hero.id)")
                                    .anchorPreference(key: TeamCardBoundsKey.self, value: .bounds) { [hero.id: $0] }
                                    .zIndex(isSelected ? 10 : 0)
                                } else {
                                    EmptyTeamSlot(slotNumber: slotIndex + 1)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel("Empty party slot \(slotIndex + 1)")
                                        .accessibilityIdentifier("team-empty-slot-\(slotIndex + 1)")
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 0)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("RESERVES  \(reserveHeroes.count)")
                                .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                                .padding(.horizontal, 12)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3), alignment: .center, spacing: 8) {
                                ForEach(reserveHeroes) { hero in
                                    let isSelected = selectedHeroID == hero.id

                                    Button {
                                        selectedHeroID = isSelected ? nil : hero.id
                                    } label: {
                                        TeamRosterCard(
                                            hero: hero,
                                            isInParty: false,
                                            isSelected: isSelected,
                                            compact: true
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(hero.name), reserve")
                                    .accessibilityIdentifier("team-reserve-\(hero.id)")
                                    .anchorPreference(key: TeamCardBoundsKey.self, value: .bounds) { [hero.id: $0] }
                                    .zIndex(isSelected ? 10 : 0)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                        .padding(.bottom, 104)
                    }
                    .overlayPreferenceValue(TeamCardBoundsKey.self) { anchors in
                        GeometryReader { overlayProxy in
                            if
                                let selectedHeroID,
                                infoHero == nil,
                                let selectedHero = hero(for: selectedHeroID),
                                let selectedAnchor = anchors[selectedHeroID]
                            {
                                let rect = overlayProxy[selectedAnchor]
                                let showActionsAbove = rect.maxY > overlayProxy.size.height - 180
                                InlineCharacterActions(
                                    inParty: activePartySlots.contains { $0 == selectedHeroID },
                                    canAdd: activePartyIDs.count < maxPartySize,
                                    pointerOnTop: !showActionsAbove,
                                    onInfo: { infoHero = selectedHero },
                                    onToggleParty: { togglePartyMembership(for: selectedHero) }
                                )
                                .frame(width: 124)
                                .position(x: rect.midX, y: showActionsAbove ? rect.minY - 36 : rect.maxY + 36)
                                .zIndex(100)
                            }
                        }
                    }
                }

                if let infoHero {
                    Color.black.opacity(0.62)
                        .ignoresSafeArea()
                        .onTapGesture {
                            self.infoHero = nil
                            selectedHeroID = nil
                        }

                    CharacterInfoModal(
                        hero: infoHero,
                        inParty: activePartySlots.contains { $0 == infoHero.id },
                        upgradeCost: upgradeCost,
                        canUpgrade: gold >= upgradeCost,
                        onClose: {
                            self.infoHero = nil
                            selectedHeroID = nil
                        },
                        onUpgrade: {
                            upgrade(hero: infoHero)
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 88)
                    .zIndex(20)
                }
            }
            .animation(.spring(response: 0.24, dampingFraction: 0.86), value: selectedHeroID)
            .task {
                await loadCharacterProgress()
            }
        }
    }

    private func togglePartyMembership(for hero: Hero) {
        if let index = activePartySlots.firstIndex(where: { $0 == hero.id }) {
            activePartySlots[index] = nil
        } else if let emptyIndex = activePartySlots.firstIndex(where: { $0 == nil }) {
            activePartySlots[emptyIndex] = hero.id
        }
        selectedHeroID = nil
    }

    private func loadCharacterProgress() async {
        guard characterProgress.isEmpty else { return }
        do {
            let records = try await MitoBackend.shared.fetchCharacterProgress()
            characterProgress = Dictionary(
                records.map { ($0.characterID, CharacterProgress(record: $0)) },
                uniquingKeysWith: { _, new in new }
            )
        } catch {
            // The local base roster still works when offline or before the
            // character_progress migration has been applied.
        }
    }

    private func upgrade(hero: Hero) {
        guard gold >= upgradeCost else { return }
        gold -= upgradeCost

        var progress = characterProgress[hero.id] ?? CharacterProgress(hero: hero)
        progress.levelUp()
        characterProgress[hero.id] = progress

        if infoHero?.id == hero.id, let baseHero = DataSet.heroes.first(where: { $0.id == hero.id }) {
            infoHero = baseHero.applying(progress)
        }

        Task {
            try? await MitoBackend.shared.upsertCharacterProgress(
                characterID: hero.id,
                level: progress.level,
                hp: progress.hp,
                attack: progress.attack,
                defense: progress.defense
            )
        }
    }
}

private enum BattleMode {
    case endless
    case campaign
}

private enum BattleRating: CaseIterable, Equatable {
    case again
    case hard
    case good
    case easy

    var title: String {
        switch self {
        case .again: "AGAIN"
        case .hard: "HARD"
        case .good: "GOOD"
        case .easy: "EASY"
        }
    }

    var color: Color {
        switch self {
        case .again: Color(hex: "C84535")
        case .hard: Color(hex: "E87818")
        case .good: Color(hex: "4A9B3F")
        case .easy: Color(hex: "1E73CC")
        }
    }

    var damage: Int {
        switch self {
        case .again: 8
        case .hard: 16
        case .good: 28
        case .easy: 40
        }
    }

    var recoil: Int {
        switch self {
        case .again: 16
        case .hard: 10
        case .good: 4
        case .easy: 0
        }
    }

    /// Maps the battle grade onto the FSRS rating that schedules the card.
    var fsrs: Rating {
        switch self {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }
}

private struct BattleScreen: View {
    @Binding var atp: Int
    @Binding var gold: Int
    @Binding var biomass: Int

    @State private var route: BattleRoute = .landing
    @State private var battleMode: BattleMode = .endless
    @State private var selectedStage = DataSet.stages[3]
    @State private var selectedDecks: Set<String> = ["bio"]
    @State private var selectedTags: Set<String> = []
    @State private var mobHP = 132
    @State private var teamHP = 164
    @State private var currentCard = 0
    @State private var showingAnswer = false
    @State private var reviewedCards = 15
    @State private var streak = 2
    @State private var activeHeroIndex = 0
    @State private var lastActorIndex = 0
    @State private var lastAbility: BattleAbility?
    @ObservedObject private var session = ReviewSession.shared

    var body: some View {
        ZStack {
            switch route {
            case .landing:
                battleLanding
            case .reviewSetup:
                reviewSetup
            case .map:
                campaignMap
            case .stageSetup:
                stageSetup
            case .combat:
                combat
            case .result:
                result
            }
        }
        .onAppear(perform: maybeJumpToReviewForUITest)
    }

    /// UI-test affordance only (DEBUG builds): with `-uitestReview`, drop
    /// straight into an endless-review combat so screenshots can capture the
    /// live FSRS loop. Compiles to a no-op in release.
    @State private var didUITestJump = false
    private func maybeJumpToReviewForUITest() {
        #if DEBUG
        guard !didUITestJump,
              ProcessInfo.processInfo.arguments.contains("-uitestReview") else { return }
        didUITestJump = true
        battleMode = .endless
        mobHP = 132
        teamHP = 164
        reviewedCards = 15
        streak = 2
        session.start(deckIDs: [])
        showingAnswer = ProcessInfo.processInfo.arguments.contains("-uitestReveal")
        route = ProcessInfo.processInfo.arguments.contains("-uitestPicker") ? .reviewSetup : .combat

        if ProcessInfo.processInfo.arguments.contains("-uitestCloudCheck") {
            Task {
                let result = await MitoBackend.shared.runCloudSelfTest(session: session)
                let url = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("uitest_cloud.txt")
                try? result.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-uitestCardEditor") {
            Task {
                let result = await MitoBackend.shared.runCardEditorSelfTest()
                let url = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("uitest_cardeditor.txt")
                try? result.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        #endif
    }

    private var battleLanding: some View {
        GeometryReader { proxy in
            ZStack {
                Image("map-bg")
                    .screenBackground()
                LinearGradient(colors: [.black.opacity(0.12), .clear, .black.opacity(0.44)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 3) {
                    Text("BATTLE")
                        .pixelText(size: 22, color: Color(hex: "F4E6C0"))
                    Text("Study freely - your team fights alongside you.")
                        .font(.custom(MitoFont.regular, size: 12))
                        .foregroundStyle(Color(hex: "F4E6C0"))
                }
                .frame(maxWidth: .infinity)
                .position(x: proxy.size.width / 2, y: 28)

                VStack(spacing: 8) {
                    Button {
                        selectedDecks = []
                        selectedTags = []
                        route = .reviewSetup
                    } label: {
                        FeatureButton(title: "ENDLESS REVIEW", badge: "RECOMMENDED", detail: "No limits · no ATP · earn gold, XP & recruits", tint: Color(hex: "4A8A3C"), height: 100)
                    }
                    .buttonStyle(.plain)
                    Button {
                        selectedDecks = []
                        selectedTags = []
                        route = .map
                    } label: {
                        FeatureButton(title: "CAMPAIGN MAP", badge: nil, detail: "Regions, bosses and unlockable stages", tint: Color(hex: "6B4324"), height: 66)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .position(x: proxy.size.width / 2, y: proxy.size.height - 100)
            }
        }
    }

    private var reviewSetup: some View {
        EndlessReviewSetup(
            decks: pickerDecks,
            selectedDecks: $selectedDecks,
            selectedTags: $selectedTags,
            onBack: { route = .landing },
            onStart: {
                battleMode = .endless
                mobHP = 132
                teamHP = 164
                currentCard = 0
                reviewedCards = 15
                streak = 2
                activeHeroIndex = 0
                lastActorIndex = 0
                lastAbility = nil
                showingAnswer = false
                session.start(deckIDs: selectedDecks, tags: selectedTags)
                route = .combat
            }
        )
    }

    private var campaignMap: some View {
        GeometryReader { proxy in
            ZStack {
                Image("map-bg")
                    .screenBackground()
                Color.black.opacity(0.18).ignoresSafeArea()
                VStack(spacing: 10) {
                    HStack {
                        BackButton { route = .landing }
                        ScreenTitle("CAMPAIGN", subtitle: "Pick a stage")
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    ZStack {
                        ForEach(DataSet.stages) { stage in
                            Button {
                                guard stage.status != .locked else { return }
                                selectedStage = stage
                                route = .stageSetup
                            } label: {
                                VStack(spacing: 3) {
                                    Image(stage.status.asset)
                                        .resizable()
                                        .interpolation(.none)
                                        .scaledToFit()
                                        .frame(width: 62, height: 62)
                                    Text("\(stage.id)")
                                        .pixelText(size: 8, color: .white)
                                }
                            }
                            .buttonStyle(.plain)
                            .position(x: proxy.size.width * stage.x, y: proxy.size.height * stage.y)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var stageSetup: some View {
        CampaignStageSetup(
            decks: pickerDecks,
            selectedDecks: $selectedDecks,
            selectedTags: $selectedTags,
            onBack: { route = .map },
            onStart: {
                guard !selectedDecks.isEmpty else { return }
                battleMode = .campaign
                mobHP = 110
                teamHP = 164
                currentCard = 1
                reviewedCards = 0
                streak = 0
                activeHeroIndex = 0
                lastActorIndex = 0
                lastAbility = nil
                showingAnswer = false
                session.start(deckIDs: selectedDecks, tags: selectedTags)
                route = .combat
            }
        )
    }

    private var combat: some View {
        BattleCombatView(
            mode: battleMode,
            mobHP: mobHP,
            teamHP: teamHP,
            reviewedCards: reviewedCards,
            streak: streak,
            currentCard: currentCard,
            showingAnswer: showingAnswer,
            questionText: session.current?.front ?? "No cards due — add a deck to keep studying.",
            answerText: session.current?.back ?? "",
            cardTag: session.current?.tags.first?.uppercased() ?? "REVIEW",
            activeHeroIndex: activeHeroIndex,
            lastActorIndex: lastActorIndex,
            lastAbility: lastAbility,
            onReveal: { showingAnswer = true },
            onDone: { route = .landing },
            onGrade: grade
        )
    }

    private var result: some View {
        ZStack {
            Image("map-bg")
                .screenBackground()
            Color.black.opacity(0.42).ignoresSafeArea()
            ParchmentBox {
                VStack(spacing: 16) {
                    Text(mobHP <= 0 ? "STAGE CLEAR" : "TEAM FAINTED")
                        .pixelText(size: 18, color: Color(hex: "3A2A18"))
                    Text(mobHP <= 0 ? "+120 gold  +8 biomass" : "Review more cards and try again.")
                        .font(.custom(MitoFont.regular, size: 18))
                        .foregroundStyle(Color(hex: "4A2F1C"))
                    PixelButton(title: "CONTINUE") {
                        if mobHP <= 0 {
                            gold += 120
                            biomass += 8
                        }
                        route = .landing
                    }
                }
                .padding(8)
            }
            .padding(22)
        }
    }

    private var selectedCardCount: Int {
        pickerDecks.filter { selectedDecks.contains($0.id) }.reduce(0) { $0 + $1.cards }
    }

    /// Decks for the pickers, derived from the live review queue so their ids
    /// always match the cards being scheduled (seed cards or Supabase cards).
    private var pickerDecks: [Deck] {
        _ = session.catalogVersion // re-derive when the pool changes
        return BattleScreen.decks(from: session.deckSummaries)
    }

    static func decks(from summaries: [DeckSummary]) -> [Deck] {
        let known: [String: Color] = [
            "bio": Color(hex: "6DB04C"),
            "phys": Color(hex: "5FA3D4"),
            "jp": Color(hex: "E7A0B8"),
            "orgo": Color(hex: "D4873A"),
        ]
        let palette = [
            Color(hex: "6DB04C"), Color(hex: "5FA3D4"), Color(hex: "E7A0B8"),
            Color(hex: "D4873A"), Color(hex: "A98FD0"), Color(hex: "E8C64A"),
        ]
        return summaries.enumerated().map { index, deck in
            Deck(
                id: deck.id,
                name: deck.name,
                cards: deck.cardCount,
                tags: deck.tags,
                color: known[deck.id] ?? palette[index % palette.count]
            )
        }
    }

    private func grade(_ rating: BattleRating) {
        // Schedule the current card with FSRS and persist before advancing.
        session.grade(rating.fsrs)
        // Endless review loops forever: rebuild the queue once it drains.
        if session.current == nil {
            session.start(deckIDs: selectedDecks, tags: selectedTags)
        }

        let ability = battleMode == .endless ? rollEndlessAbility() : nil
        let damage = ability?.damage ?? rating.damage
        let recoil = battleMode == .campaign ? rating.recoil : 0
        let enemyDefeated = mobHP - damage <= 0
        let teamDefeated = teamHP - recoil <= 0
        mobHP = max(0, mobHP - damage)
        teamHP = max(0, teamHP - recoil)
        reviewedCards += 1
        streak = battleMode == .endless ? streak + 1 : (rating == .again ? 0 : streak + 1)
        currentCard += 1
        showingAnswer = false
        if battleMode == .endless, enemyDefeated {
            mobHP = 132
            gold += 30
            biomass += 2
        } else if enemyDefeated || teamDefeated {
            route = .result
        }
    }

    private func rollEndlessAbility() -> BattleAbility {
        let team = Array(DataSet.heroes.prefix(3))
        let boundedIndex = min(max(activeHeroIndex, 0), max(team.count - 1, 0))
        let hero = team[boundedIndex]
        let ability = BattleAbilityBook.abilities(for: hero).randomElement()
            ?? BattleAbility(id: "fallback", name: "Study Strike", damage: 28, detail: "A steady review strike lands.", color: hero.color)
        lastActorIndex = boundedIndex
        lastAbility = ability
        activeHeroIndex = (boundedIndex + 1) % max(team.count, 1)
        return ability
    }

    private enum BattleRoute {
        case landing
        case reviewSetup
        case map
        case stageSetup
        case combat
        case result
    }
}

private struct BattleCombatView: View {
    let mode: BattleMode
    let mobHP: Int
    let teamHP: Int
    let reviewedCards: Int
    let streak: Int
    let currentCard: Int
    let showingAnswer: Bool
    let questionText: String
    let answerText: String
    let cardTag: String
    let activeHeroIndex: Int
    let lastActorIndex: Int
    let lastAbility: BattleAbility?
    let onReveal: () -> Void
    let onDone: () -> Void
    let onGrade: (BattleRating) -> Void

    private var enemyName: String {
        mode == .endless ? "Mutagem" : "Spikevyrus"
    }

    private var enemyMaxHP: Int {
        mode == .endless ? 132 : 110
    }

    private var enemyRarity: String? {
        mode == .endless ? "EPIC" : nil
    }

    private var heroCount: Int {
        mode == .endless ? 3 : 4
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("dungeon-bg")
                    .screenBackground()
                LinearGradient(
                    colors: [Color.black.opacity(0.08), Color.black.opacity(0.02), Color.black.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    statusRow
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    Spacer().frame(height: mode == .endless ? 24 : 24)

                    enemyBlock
                        .padding(.horizontal, 46)

                    Spacer().frame(height: mode == .endless ? 11 : 14)

                    partyRow
                        .padding(.horizontal, mode == .endless ? 72 : 42)
                        .padding(.bottom, mode == .campaign ? 3 : 10)

                    abilityBanner
                        .padding(.horizontal, 34)
                        .padding(.bottom, 7)

                    if mode == .campaign {
                        teamHPBar
                            .padding(.horizontal, 26)
                            .padding(.bottom, 8)
                    }

                    BattleFlashcardPanel(
                        mode: mode,
                        currentCard: currentCard,
                        showingAnswer: showingAnswer,
                        questionText: questionText,
                        answerText: answerText,
                        cardTag: cardTag,
                        onReveal: onReveal
                    )
                    .padding(.horizontal, 12)

                    Text(showingAnswer ? "Grade honestly - ability RNG is separate" : "Recall the answer, then reveal")
                        .font(.custom(MitoFont.regular, size: 14))
                        .foregroundStyle(Color(hex: "F4E6C0").opacity(0.86))
                        .shadow(color: .black.opacity(0.65), radius: 0, x: 1, y: 1)
                        .padding(.top, 8)
                        .padding(.bottom, 7)

                    gradeRow
                        .padding(.horizontal, 12)
                        .padding(.bottom, 82)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 7) {
            if mode == .endless {
                BattleStatusChip("WAVE 5")
                BattleStatusChip("REVIEWED \(reviewedCards)")
                BattleStatusChip("CHAIN \(streak)")
            } else {
                BattleStatusChip("STAGE 4 · WAVE 1/2")
            }

            Spacer(minLength: 0)

            Button(action: onDone) {
                Text(mode == .endless ? "DONE" : "FLEE")
                    .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color(hex: "182116").opacity(0.88))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
        }
    }

    private var enemyBlock: some View {
        VStack(spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                Text(enemyName)
                    .pixelText(size: mode == .endless ? 17 : 12, color: Color(hex: "F4E6C0"))
                if let enemyRarity {
                    Text(enemyRarity)
                        .pixelText(size: 8, color: .white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(hex: "A56AD8"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                if mode == .campaign {
                    Spacer(minLength: 0)
                    Text("\(mobHP)/\(enemyMaxHP)")
                        .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                }
            }

            HPBar(value: mobHP, max: enemyMaxHP, tint: Color(hex: "58C054"))
                .frame(height: mode == .endless ? 15 : 13)

            Image("mob_1")
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: mode == .endless ? 124 : 118, height: mode == .endless ? 124 : 118)
                .shadow(color: .black.opacity(0.34), radius: 0, x: 4, y: 5)
        }
    }

    private var partyRow: some View {
        HStack(alignment: .bottom, spacing: mode == .endless ? 24 : 18) {
            ForEach(Array(DataSet.heroes.prefix(heroCount).enumerated()), id: \.element.id) { index, hero in
                VStack(spacing: -1) {
                    Character(asset: hero.asset, size: heroSize(for: index))
                        .scaleEffect(heroScale(for: index), anchor: .bottom)
                    Text(hero.name)
                        .pixelText(size: 7, color: Color(hex: "F4E6C0"))
                        .shadow(color: .black.opacity(0.85), radius: 0, x: 1, y: 1)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.22, dampingFraction: 0.68), value: lastActorIndex)
            }
        }
    }

    private var abilityBanner: some View {
        let hero = DataSet.heroes[min(max(lastActorIndex, 0), DataSet.heroes.count - 1)]
        let ability = lastAbility

        return HStack(spacing: 7) {
            Text(ability == nil ? "NEXT" : hero.name.uppercased())
                .pixelText(size: 8, color: Color(hex: "F4E6C0"))
                .frame(width: 58)
                .padding(.vertical, 5)
                .background((ability?.color ?? hero.color).opacity(0.88))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))

            VStack(alignment: .leading, spacing: 1) {
                Text(ability?.name.uppercased() ?? "RANDOM ABILITY READY")
                    .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                    .lineLimit(1)
                Text(ability?.detail ?? "Endless rolls one of the active hero's three abilities after each card.")
                    .font(.custom(MitoFont.regular, size: 10))
                    .foregroundStyle(Color(hex: "F4E6C0").opacity(0.88))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let ability {
                Text("-\(ability.damage)")
                    .pixelText(size: 9, color: Color(hex: "FFD24D"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 35)
        .background(Color(hex: "182116").opacity(0.84))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }

    private func heroSize(for index: Int) -> CGFloat {
        mode == .endless ? (index == highlightedHeroIndex ? 49 : 43) : 40
    }

    private func heroScale(for index: Int) -> CGFloat {
        mode == .endless && index == highlightedHeroIndex ? 1.08 : 1
    }

    private var highlightedHeroIndex: Int {
        lastAbility == nil ? activeHeroIndex : lastActorIndex
    }

    private var teamHPBar: some View {
        HStack(spacing: 7) {
            Text("♥ TEAM")
                .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                .frame(width: 64, alignment: .leading)
            HPBar(value: teamHP, max: 164, tint: Color(hex: "58C054"))
            Text("\(teamHP)/164")
                .pixelText(size: 8, color: Color(hex: "F4E6C0"))
        }
        .padding(.horizontal, 8)
        .frame(height: 25)
        .background(Color(hex: "18100A").opacity(0.90))
        .frame(maxWidth: .infinity)
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }

    private var gradeRow: some View {
        HStack(spacing: 10) {
            ForEach(BattleRating.allCases, id: \.self) { rating in
                BattleGradeButton(rating: rating, enabled: showingAnswer) {
                    onGrade(rating)
                }
            }
        }
        .opacity(showingAnswer ? 1 : 0.48)
    }
}

private struct BattleStatusChip: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .pixelText(size: 9, color: Color(hex: "F4E6C0"))
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(Color(hex: "182116").opacity(0.86))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct BattleFlashcardPanel: View {
    let mode: BattleMode
    let currentCard: Int
    let showingAnswer: Bool
    let questionText: String
    let answerText: String
    let cardTag: String
    let onReveal: () -> Void

    private var label: String {
        showingAnswer ? "ANSWER" : "QUESTION"
    }

    private var tag: String { cardTag }

    private var text: String {
        showingAnswer ? answerText : questionText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BattlePanelTag(label)
                Spacer()
                BattlePanelTag(tag)
            }

            Text(text)
                .font(.custom(MitoFont.regular, size: showingAnswer ? 20 : 21))
                .foregroundStyle(Color(hex: "3A2A18"))
                .multilineTextAlignment(.leading)
                .lineSpacing(7)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 24)

            if showingAnswer {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 18)
            } else {
                Button(action: onReveal) {
                    Text("SHOW ANSWER")
                        .pixelText(size: 16, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 39)
                        .background(Color(hex: "6B4324"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .padding(8)
        .frame(height: 188)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color(hex: "B89868"))
                .frame(width: 11, height: 11)
                .padding(9)
        }
    }
}

private struct BattlePanelTag: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .pixelText(size: 8, color: Color(hex: "F4E6C0"))
            .padding(.horizontal, 8)
            .frame(height: 21)
            .background(Color(hex: "8A6B42"))
            .overlay(Rectangle().stroke(Color(hex: "F4E6C0"), lineWidth: 1))
    }
}

private struct BattleGradeButton: View {
    let rating: BattleRating
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(rating.title)
                .pixelText(size: 17, color: Color(hex: "F4E6C0"))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(rating.color)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 0, x: 2, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct CardsScreen: View {
    @ObservedObject private var session = ReviewSession.shared
    @ObservedObject private var backend = MitoBackend.shared
    @State private var decks = CardsScreen.seedDecks
    @State private var cardsByDeckID: [String: [Flashcard]] = CardsScreen.sampleCards
    @State private var route: CardsRoute = .library
    @State private var showingNewDeck = false
    @State private var newDeckName = ""
    @State private var didLoad = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                switch route {
                case .library:
                    cardsLibrary(proxy: proxy)
                case .detail(let deckID):
                    DeckDetailScreen(
                        deck: deck(for: deckID),
                        cards: cardsByDeckID[deckID, default: []],
                        onBack: { route = .library },
                        onAdd: { route = .editor(deckID: deckID, cardID: nil) },
                        onEdit: { card in route = .editor(deckID: deckID, cardID: card.id) },
                        onDeleteDeck: { Task { await deleteDeck(deckID: deckID) } }
                    )
                case .editor(let deckID, let cardID):
                    FlashcardEditorScreen(
                        deckName: deck(for: deckID).name,
                        existingCard: cardID.flatMap { card(in: deckID, cardID: $0) },
                        onBack: { route = .detail(deckID: deckID) },
                        onSave: { front, back, tags in
                            Task {
                                await saveCard(deckID: deckID, cardID: cardID, front: front, back: back, tags: tags)
                                route = .detail(deckID: deckID)
                            }
                        },
                        onDelete: cardID.map { id in
                            { Task {
                                await deleteCard(deckID: deckID, cardID: id)
                                route = .detail(deckID: deckID)
                            } }
                        }
                    )
                }

                if showingNewDeck {
                    Color.black.opacity(0.62).ignoresSafeArea()
                    NewDeckModal(
                        name: $newDeckName,
                        onCancel: { showingNewDeck = false },
                        onCreate: {
                            let clean = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !clean.isEmpty else { return }
                            newDeckName = ""
                            showingNewDeck = false
                            Task { await createDeck(named: clean) }
                        }
                    )
                    .frame(width: proxy.size.width * 0.82)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.40)
                }
            }
            .task(id: backend.isReady) { await loadLibrary() }
        }
    }

    @ViewBuilder
    private func cardsLibrary(proxy: GeometryProxy) -> some View {
        Image("library-bg")
            .screenBackground()
        Color.black.opacity(0.20).ignoresSafeArea()

        HStack {
            Text("DECK LIBRARY")
                .pixelText(size: 18, color: Color(hex: "F4E6C0"))
            Spacer()
            Button {
                newDeckName = ""
                showingNewDeck = true
            } label: {
                Text("+ NEW DECK")
                    .pixelText(size: 11, color: Color(hex: "18100A"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color(hex: "F7C943"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(width: proxy.size.width)
        .position(x: proxy.size.width / 2, y: 42)

        VStack(spacing: 9) {
            ForEach(decks) { deck in
                Button {
                    route = .detail(deckID: deck.id)
                } label: {
                    DeckLibraryRow(deck: deck, progress: progress(for: deck.id))
                }
                .buttonStyle(.plain)
            }

            Text("\(decks.count) decks · \(decks.reduce(0) { $0 + $1.cards }) cards")
                .font(.custom(MitoFont.regular, size: 13))
                .foregroundStyle(Color(hex: "EAD4A4"))
                .padding(.top, 8)
        }
        .position(x: proxy.size.width / 2, y: 300)
    }

    private enum CardsRoute {
        case library
        case detail(deckID: String)
        case editor(deckID: String, cardID: String?)
    }

    private func deck(for deckID: String) -> Deck {
        decks.first { $0.id == deckID } ?? decks[0]
    }

    private func card(in deckID: String, cardID: String) -> Flashcard? {
        cardsByDeckID[deckID, default: []].first { $0.id == cardID }
    }

    private func progress(for deckID: String) -> Double {
        let count = Double(cardsByDeckID[deckID, default: []].count)
        return min(count / 12, 1)
    }

    /// Load the user's real decks from Supabase (cards come from the already-
    /// synced review session). Falls back to the bundled samples when offline.
    private func loadLibrary() async {
        guard !didLoad, backend.isReady else { return }
        didLoad = true
        await backend.attachSync(to: session) // make sure cloud cards are loaded
        guard let remote = try? await backend.fetchDecks(), !remote.isEmpty else { return }

        var loadedDecks: [Deck] = []
        var byDeck: [String: [Flashcard]] = [:]
        for record in remote {
            let id = record.id.uuidString
            let cards = session.cards(in: id)
            byDeck[id] = cards.map { Flashcard(id: $0.id.uuidString, front: $0.front, back: $0.back, tags: $0.tags) }
            let tags = Array(Set(cards.flatMap(\.tags))).sorted()
            loadedDecks.append(Deck(id: id, name: record.name, cards: cards.count,
                                    tags: tags.isEmpty ? ["new"] : tags, color: Self.deckColor(id)))
        }
        decks = loadedDecks
        cardsByDeckID = byDeck
        #if DEBUG
        // Deep-link straight into the editor for screenshots, only once cards
        // are actually loaded, and without an animated transition (no blank
        // flash on a cold launch).
        if ProcessInfo.processInfo.arguments.contains("-uitestEditor"),
           let d = decks.first, let c = cardsByDeckID[d.id]?.first {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { route = .editor(deckID: d.id, cardID: c.id) }
        }
        #endif
    }

    /// Create a deck on the backend (or locally when offline), then open it.
    private func createDeck(named name: String) async {
        var deckID = UUID().uuidString
        if backend.isReady, let record = try? await backend.createDeck(named: name) {
            deckID = record.id.uuidString
        }
        if !decks.contains(where: { $0.id == deckID }) {
            decks.append(Deck(id: deckID, name: name, cards: 0, tags: ["new"], color: Self.deckColor(deckID)))
        }
        cardsByDeckID[deckID] = []
        route = .detail(deckID: deckID)
    }

    private func saveCard(deckID: String, cardID: String?, front: String, back: String, tags: [String]) async {
        let cleanFront = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBack = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanFront.isEmpty, !cleanBack.isEmpty else { return }

        var cards = cardsByDeckID[deckID, default: []]
        let cleanTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        let finalTags = cleanTags.isEmpty ? ["new"] : Array(Set(cleanTags)).sorted()
        let deckUUID = UUID(uuidString: deckID)
        let name = decks.first { $0.id == deckID }?.name ?? ""

        // Resolve the card id: edit keeps it; create makes a new one (using the
        // backend-assigned id when signed in, so cloud + session stay aligned).
        var resolvedID = cardID.flatMap(UUID.init(uuidString:)) ?? UUID()
        // Branch on edit-intent (a valid existing id), not on whether the card
        // happens to be in the in-memory list — otherwise an edit whose card
        // isn't loaded locally would fall through and create a duplicate.
        if let cardID, let uuid = UUID(uuidString: cardID) {
            if let index = cards.firstIndex(where: { $0.id == cardID }) {
                cards[index].front = cleanFront
                cards[index].back = cleanBack
                cards[index].tags = finalTags
            } else {
                cards.append(Flashcard(id: cardID, front: cleanFront, back: cleanBack, tags: finalTags))
            }
            try? await backend.updateCard(id: uuid, front: cleanFront, back: cleanBack, tags: finalTags)
        } else {
            if backend.isReady, let deckUUID,
               let record = try? await backend.createCard(deckID: deckUUID, front: cleanFront, back: cleanBack, tags: finalTags) {
                resolvedID = record.id
            }
            cards.append(Flashcard(id: resolvedID.uuidString, front: cleanFront, back: cleanBack, tags: finalTags))
        }
        cardsByDeckID[deckID] = cards

        // Make the card immediately reviewable through the shared session.
        session.upsertContent(ReviewCard(id: resolvedID, deckID: deckID, deckName: name,
                                         front: cleanFront, back: cleanBack, tags: finalTags))
        refreshDeckMeta(deckID: deckID)
    }

    /// Delete a card from the deck list, backend, and review session.
    private func deleteCard(deckID: String, cardID: String) async {
        cardsByDeckID[deckID] = cardsByDeckID[deckID, default: []].filter { $0.id != cardID }
        if let uuid = UUID(uuidString: cardID) {
            session.remove(cardID: uuid)
            try? await backend.deleteCard(id: uuid)
        }
        refreshDeckMeta(deckID: deckID)
    }

    /// Delete an entire deck (and its cards) from the library, backend, session.
    private func deleteDeck(deckID: String) async {
        decks.removeAll { $0.id == deckID }
        cardsByDeckID[deckID] = nil
        session.remove(deckID: deckID)
        if let uuid = UUID(uuidString: deckID) {
            try? await backend.deleteDeck(id: uuid)
        }
        route = .library
    }

    /// Recompute a deck's card count + tag summary after a card change.
    private func refreshDeckMeta(deckID: String) {
        guard let index = decks.firstIndex(where: { $0.id == deckID }) else { return }
        let cards = cardsByDeckID[deckID, default: []]
        let deck = decks[index]
        let uniqueTags = Array(Set(cards.flatMap(\.tags))).sorted()
        decks[index] = Deck(
            id: deck.id,
            name: deck.name,
            cards: cards.count,
            tags: uniqueTags.isEmpty ? ["new"] : uniqueTags,
            color: deck.color
        )
    }

    private static func deckColor(_ id: String) -> Color {
        let known: [String: Color] = [
            "bio": Color(hex: "6DB04C"), "phys": Color(hex: "5FA3D4"),
            "jp": Color(hex: "E7A0B8"), "orgo": Color(hex: "D4873A"),
        ]
        if let c = known[id] { return c }
        let palette = [
            Color(hex: "6DB04C"), Color(hex: "5FA3D4"), Color(hex: "E7A0B8"),
            Color(hex: "D4873A"), Color(hex: "A98FD0"), Color(hex: "E8C64A"),
        ]
        return palette[abs(id.hashValue) % palette.count]
    }

    private static let sampleCards: [String: [Flashcard]] = [
        "bio": [
            Flashcard(id: "bio-1", front: "What organelle produces most cellular ATP?", back: "The mitochondrion produces ATP through cellular respiration.", tags: ["cell", "dna", "mitosis"]),
            Flashcard(id: "bio-2", front: "What happens during mitosis?", back: "One cell divides its duplicated chromosomes into two identical daughter nuclei.", tags: ["cell", "mitosis"]),
            Flashcard(id: "bio-3", front: "What does DNA store?", back: "DNA stores genetic instructions used to build and regulate living cells.", tags: ["dna"])
        ],
        "phys": [
            Flashcard(id: "phys-1", front: "What is the kinetic energy formula?", back: "Kinetic energy equals one half times mass times velocity squared.", tags: ["kinematics", "energy"]),
            Flashcard(id: "phys-2", front: "What does frequency measure?", back: "Frequency measures cycles per second, in hertz.", tags: ["waves"])
        ],
        "jp": [
            Flashcard(id: "jp-1", front: "What does taberu mean?", back: "Taberu means to eat.", tags: ["n5", "verbs"]),
            Flashcard(id: "jp-2", front: "What does mizu mean?", back: "Mizu means water.", tags: ["n5", "nouns"])
        ],
        "orgo": [
            Flashcard(id: "orgo-1", front: "What stereochemistry does SN2 give?", back: "SN2 reactions invert stereochemistry at the reacting center.", tags: ["sn2"]),
            Flashcard(id: "orgo-2", front: "What favors SN1?", back: "Stable carbocations, polar protic solvent, and good leaving groups favor SN1.", tags: ["sn1"])
        ]
    ]

    private static let seedDecks: [Deck] = DataSet.decks.map { deck in
        Deck(
            id: deck.id,
            name: deck.name,
            cards: sampleCards[deck.id, default: []].count,
            tags: deck.tags,
            color: deck.color
        )
    }
}

private struct DeckDetailScreen: View {
    let deck: Deck
    let cards: [Flashcard]
    let onBack: () -> Void
    let onAdd: () -> Void
    let onEdit: (Flashcard) -> Void
    let onDeleteDeck: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        ZStack {
            DottedDarkBackground()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(action: onBack) {
                        Text("< BACK")
                            .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    Text(deck.name)
                        .pixelText(size: 17, color: Color(hex: "F4E6C0"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Text("\(cards.count) CARDS")
                        .pixelText(size: 10, color: Color(hex: "B89868"))
                }

                HStack {
                    SmallToggle("ALL", active: true)
                    SmallToggle("NEW", active: false)
                }

                if cards.isEmpty {
                    Spacer()
                    Text("No cards in this deck yet.")
                        .font(.custom(MitoFont.regular, size: 17))
                        .foregroundStyle(Color(hex: "B89868"))
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(cards) { card in
                                Button {
                                    onEdit(card)
                                } label: {
                                    FlashcardListRow(card: card)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Button(action: onAdd) {
                    Text("+ ADD FLASHCARD")
                        .pixelText(size: 14, color: Color(hex: "3A2A18"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "EAD4A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)

                Button { confirmingDelete = true } label: {
                    Text("DELETE DECK")
                        .pixelText(size: 11, color: .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(hex: "C4452F"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Delete \(deck.name) and all its cards?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete deck", role: .destructive) { onDeleteDeck() }
                    Button("Cancel", role: .cancel) {}
                }
            }
            .padding(18)
        }
    }
}

private struct FlashcardListRow: View {
    let card: Flashcard

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color(hex: "6DB04C"))
                .frame(width: 7)
            VStack(alignment: .leading, spacing: 5) {
                Text(card.front)
                    .pixelText(size: 12, color: Color(hex: "3A2A18"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(card.back)
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    ForEach(card.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .pixelText(size: 7, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: "F4E6C0"))
                            .overlay(Rectangle().stroke(Color(hex: "B89868"), lineWidth: 1))
                    }
                }
            }
            Spacer()
            Text("EDIT")
                .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(hex: "6B4324"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .frame(minHeight: 76)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

private struct NewDeckModal: View {
    @Binding var name: String
    let onCancel: () -> Void
    let onCreate: () -> Void

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NEW DECK")
                    .pixelText(size: 17, color: Color(hex: "3A2A18"))
                Spacer()
                Button(action: onCancel) {
                    Text("×")
                        .font(.custom(MitoFont.regular, size: 28))
                        .foregroundStyle(Color(hex: "3A2A18"))
                }
                .buttonStyle(.plain)
            }
            Text("DECK NAME")
                .pixelText(size: 10, color: Color(hex: "6B4324"))
            TextField("e.g. Organic mechanisms", text: $name)
                .font(.custom(MitoFont.regular, size: 20))
                .foregroundStyle(Color(hex: "3A2A18"))
                .padding(10)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            Text("You'll be able to add cards and tags after creating.")
                .font(.custom(MitoFont.regular, size: 13))
                .foregroundStyle(Color(hex: "8A6B42"))
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("CANCEL")
                        .pixelText(size: 12, color: Color(hex: "3A2A18"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(hex: "EAD4A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                Button(action: onCreate) {
                    Text("CREATE")
                        .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(canCreate ? Color(hex: "4A8A3C") : Color(hex: "9EB46F"))
                        .overlay(Rectangle().stroke(canCreate ? Color(hex: "18100A") : Color(hex: "8A9A62"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(!canCreate)
            }
        }
        .padding(16)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

private struct FlashcardEditorScreen: View {
    let deckName: String
    let existingCard: Flashcard?
    let onBack: () -> Void
    let onSave: (String, String, [String]) -> Void
    let onDelete: (() -> Void)?
    @State private var front: String
    @State private var back: String
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var confirmingDelete = false
    @State private var activeSide: FlashcardSide = .front

    init(
        deckName: String,
        existingCard: Flashcard?,
        onBack: @escaping () -> Void,
        onSave: @escaping (String, String, [String]) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.deckName = deckName
        self.existingCard = existingCard
        self.onBack = onBack
        self.onSave = onSave
        self.onDelete = onDelete
        _front = State(initialValue: existingCard?.front ?? "")
        _back = State(initialValue: existingCard?.back ?? "")
        // Don't surface the placeholder "new" tag in the editor.
        _tags = State(initialValue: (existingCard?.tags ?? []).filter { $0 != "new" })
    }

    private var canSave: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty, !tags.contains(t) else { newTag = ""; return }
        tags.append(t)
        newTag = ""
    }

    var body: some View {
        ZStack {
            DottedDarkBackground()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: onBack) {
                        Text("< BACK")
                            .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(deckName)
                            .pixelText(size: 17, color: Color(hex: "F4E6C0"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(existingCard == nil ? "NEW FLASHCARD" : "EDIT FLASHCARD")
                            .font(.custom(MitoFont.regular, size: 13))
                            .foregroundStyle(Color(hex: "B89868"))
                    }
                    Spacer()
                    Button {
                        onSave(front, back, tags)
                    } label: {
                        Text(existingCard == nil ? "CREATE" : "SAVE")
                            .pixelText(size: 11, color: canSave ? Color(hex: "F4E6C0") : Color(hex: "3A2A18"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(canSave ? Color(hex: "4A8A3C") : Color(hex: "B89868"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        FlashcardSideTabs(activeSide: $activeSide)
                        FlippingFlashcardEditor(activeSide: activeSide, front: $front, back: $back)
                            .frame(minHeight: 340)
                            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: activeSide)

                        tagEditor
                    }
                    .padding(14)
                    .padding(.bottom, 18)
                }
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                if onDelete != nil {
                    Button {
                        confirmingDelete = true
                    } label: {
                        Text("DELETE CARD")
                            .pixelText(size: 12, color: .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color(hex: "C4452F"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Delete this flashcard?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) { onDelete?() }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .padding(18)
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
                        Text("TAGS")
                            .pixelText(size: 9, color: Color(hex: "6B4324"))
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Button {
                                    tags.removeAll { $0 == tag }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(tag.uppercased())
                                            .pixelText(size: 8, color: .white)
                                        Text("×")
                                            .font(.custom(MitoFont.regular, size: 14))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "6B9C4A"))
                                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("add a tag", text: $newTag)
                                .font(.custom(MitoFont.regular, size: 15))
                                .foregroundStyle(Color(hex: "3A2A18"))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit(addTag)
                                .padding(8)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                            Button(action: addTag) {
                                Text("+ ADD")
                                    .pixelText(size: 9, color: Color(hex: "3A2A18"))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(Color(hex: "F7C943"))
                                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
        }
        .padding(10)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "B89868"), lineWidth: 2))
    }
}

private enum FlashcardSide {
    case front
    case back

    var title: String {
        switch self {
        case .front: "FRONT"
        case .back: "BACK"
        }
    }

    var placeholder: String {
        switch self {
        case .front: "Write the question or prompt..."
        case .back: "Write the answer..."
        }
    }
}

private struct FlashcardSideTabs: View {
    @Binding var activeSide: FlashcardSide

    var body: some View {
        HStack(spacing: 10) {
            FlashcardSideTab(side: .front, activeSide: $activeSide)
            Spacer(minLength: 0)
            FlashcardSideTab(side: .back, activeSide: $activeSide)
        }
    }
}

private struct FlashcardSideTab: View {
    let side: FlashcardSide
    @Binding var activeSide: FlashcardSide

    private var isActive: Bool {
        activeSide == side
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                activeSide = side
            }
        } label: {
            Text(side.title)
                .pixelText(size: 13, color: isActive ? Color(hex: "F4E6C0") : Color(hex: "8A6B42"))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isActive ? Color(hex: "4A8A3C") : Color(hex: "6B4324").opacity(0.42))
                .overlay(Rectangle().stroke(isActive ? Color(hex: "18100A") : Color(hex: "8A6B42"), lineWidth: isActive ? 3 : 2))
                .opacity(isActive ? 1 : 0.72)
        }
        .buttonStyle(.plain)
    }
}

private struct FlippingFlashcardEditor: View {
    let activeSide: FlashcardSide
    @Binding var front: String
    @Binding var back: String

    var body: some View {
        ZStack {
            FlashcardSidePage(side: .front, text: $front)
                .opacity(activeSide == .front ? 1 : 0)
                .animation(nil, value: activeSide)

            FlashcardSidePage(side: .back, text: $back)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(activeSide == .back ? 1 : 0)
                .animation(nil, value: activeSide)
        }
        .rotation3DEffect(.degrees(activeSide == .back ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
    }
}

private struct FlashcardSidePage: View {
    let side: FlashcardSide
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(side.title)
                    .pixelText(size: 14, color: Color(hex: "3A2A18"))
                Spacer()
                Text(side == .front ? "QUESTION" : "ANSWER")
                    .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(hex: "6B4324"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.custom(MitoFont.regular, size: 23))
                    .foregroundStyle(Color(hex: "3A2A18"))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if text.isEmpty {
                    Text(side.placeholder)
                        .font(.custom(MitoFont.regular, size: 20))
                        .foregroundStyle(Color(hex: "8A6B42"))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color(hex: "B89868"))
                .frame(width: 14, height: 14)
                .padding(10)
        }
    }
}

private struct DottedDarkBackground: View {
    var body: some View {
        Color(hex: "20150D")
            .overlay {
                GeometryReader { proxy in
                    Path { path in
                        let step: CGFloat = 8
                        for x in stride(from: CGFloat(0), through: proxy.size.width, by: step) {
                            for y in stride(from: CGFloat(0), through: proxy.size.height, by: step) {
                                path.addEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                            }
                        }
                    }
                    .fill(Color(hex: "3A2A18").opacity(0.55))
                }
            }
            .ignoresSafeArea()
    }
}

private struct SmallToggle: View {
    let title: String
    let active: Bool

    init(_ title: String, active: Bool) {
        self.title = title
        self.active = active
    }

    var body: some View {
        Text(title)
            .pixelText(size: 10, color: active ? Color(hex: "F4E6C0") : Color(hex: "3A2A18"))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(active ? Color(hex: "4A8A3C") : Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }
}

private struct CampaignStageSetup: View {
    let decks: [Deck]
    @Binding var selectedDecks: Set<String>
    @Binding var selectedTags: Set<String>
    let onBack: () -> Void
    let onStart: () -> Void

    private var selectedCount: Int {
        decks.filter { selectedDecks.contains($0.id) }.reduce(0) { $0 + $1.cards }
    }

    private var availableTags: [String] {
        var seen = Set<String>()
        var tags: [String] = []
        for deck in decks where selectedDecks.contains(deck.id) {
            for tag in deck.tags where !seen.contains(tag) {
                seen.insert(tag)
                tags.append(tag)
            }
        }
        return tags
    }

    private var canStart: Bool {
        !selectedDecks.isEmpty
    }

    var body: some View {
        ZStack {
            WoodBackground()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button(action: onBack) {
                        Text("< BACK")
                            .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    Text("STAGE 4 · NORMAL")
                        .pixelText(size: 16, color: Color(hex: "FFD24D"))
                    Spacer()
                }

                HStack(spacing: 10) {
                    Image("mob_1")
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .background(Color(hex: "F4E6C0"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MITOCHONDRIA CAVE")
                            .pixelText(size: 13, color: Color(hex: "3A2A18"))
                        Text("Spikevyrus · 3 waves")
                            .font(.custom(MitoFont.regular, size: 15))
                            .foregroundStyle(Color(hex: "6B4324"))
                    }
                    Spacer()
                    Text("NORMAL")
                        .pixelText(size: 8, color: .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(hex: "4D6BA5"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .padding(8)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                HStack {
                    Text("PICK YOUR DECKS")
                        .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                    Spacer()
                    Text("SELECT ALL")
                        .pixelText(size: 10, color: Color(hex: "3A2A18"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: "EAD4A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }

                VStack(spacing: 8) {
                    ForEach(decks) { deck in
                        EndlessDeckRow(deck: deck, isSelected: selectedDecks.contains(deck.id), highlightSelected: true) {
                            toggleDeck(deck)
                        }
                    }
                }

                Spacer(minLength: 0)

                Text("FILTER BY TAG (optional)")
                    .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                if availableTags.isEmpty {
                    Text("Select a deck to reveal its tags.")
                        .font(.custom(MitoFont.regular, size: 14))
                        .foregroundStyle(Color(hex: "F4E6C0").opacity(0.78))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(availableTags, id: \.self) { tag in
                            Button {
                                toggleTag(tag)
                            } label: {
                                SmallTag(tag.uppercased(), active: selectedTags.contains(tag))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(spacing: 8) {
                    HStack {
                        Text("\(selectedDecks.count) \(selectedDecks.count == 1 ? "deck" : "decks") · \(selectedCount) cards")
                            .font(.custom(MitoFont.regular, size: 15))
                            .foregroundStyle(Color(hex: "3A2A18"))
                        Spacer()
                        Text("FREE ENTRY")
                            .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: "4A8A3C"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    HStack {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        Text("Focus Energy - better catch odds & bonus loot")
                            .font(.custom(MitoFont.regular, size: 14))
                            .foregroundStyle(Color(hex: "3A2A18"))
                            .lineLimit(2)
                        Spacer()
                        Text("⚡ 20")
                            .pixelText(size: 10, color: Color(hex: "3A2A18"))
                    }
                    .padding(8)
                    .background(Color(hex: "F4E6C0"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .padding(8)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                Button(action: {
                    if canStart {
                        onStart()
                    }
                }) {
                    Text(canStart ? "⚔ ENTER DUNGEON" : "PICK A DECK")
                        .pixelText(size: 18, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(canStart ? Color(hex: "D84A3A") : Color(hex: "6B4324"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.62)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    private func toggleDeck(_ deck: Deck) {
        if selectedDecks.contains(deck.id) {
            selectedDecks.remove(deck.id)
        } else {
            selectedDecks.insert(deck.id)
        }
        selectedTags.formIntersection(Set(availableTags))
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

private struct EndlessReviewSetup: View {
    let decks: [Deck]
    @Binding var selectedDecks: Set<String>
    @Binding var selectedTags: Set<String>
    let onBack: () -> Void
    let onStart: () -> Void

    private var selectedCount: Int {
        decks.filter { selectedDecks.contains($0.id) }.reduce(0) { $0 + $1.cards }
    }

    private var allSelected: Bool {
        !decks.isEmpty && selectedDecks.count == decks.count
    }

    private var availableTags: [String] {
        var seen = Set<String>()
        var tags: [String] = []
        for deck in decks where selectedDecks.contains(deck.id) {
            for tag in deck.tags where !seen.contains(tag) {
                seen.insert(tag)
                tags.append(tag)
            }
        }
        return tags
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("map-bg")
                    .screenBackground()
                Color(hex: "123D2F").opacity(0.66).ignoresSafeArea()
                LinearGradient(colors: [.clear, Color.black.opacity(0.30)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                HStack(spacing: 8) {
                    Button(action: onBack) {
                        Text("< BACK")
                            .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)

                    Text("ENDLESS REVIEW")
                        .pixelText(size: 17, color: Color(hex: "FFD24D"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(width: proxy.size.width)
                .position(x: proxy.size.width / 2, y: 24)

                HStack {
                    Text("PICK YOUR DECKS")
                        .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                    Spacer()
                    Button {
                        if allSelected {
                            selectedDecks.removeAll()
                        } else {
                            selectedDecks = Set(decks.map(\.id))
                        }
                        selectedTags.formIntersection(Set(availableTags))
                    } label: {
                        Text("SELECT ALL")
                            .pixelText(size: 10, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(hex: "EAD4A4"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .frame(width: proxy.size.width)
                .position(x: proxy.size.width / 2, y: 68)

                VStack(spacing: 10) {
                    ForEach(decks) { deck in
                        EndlessDeckRow(deck: deck, isSelected: selectedDecks.contains(deck.id)) {
                            toggleDeck(deck)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .position(x: proxy.size.width / 2, y: 216)

                VStack(alignment: .leading, spacing: 8) {
                    Text("FILTER BY TAG (optional)")
                        .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                    if availableTags.isEmpty {
                        Text("Select a deck to reveal its tags.")
                            .font(.custom(MitoFont.regular, size: 14))
                            .foregroundStyle(Color(hex: "F4E6C0").opacity(0.80))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(availableTags, id: \.self) { tag in
                                Button {
                                    toggleTag(tag)
                                } label: {
                                    SmallTag(tag.uppercased(), active: selectedTags.contains(tag))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(width: proxy.size.width, alignment: .leading)
                .position(x: proxy.size.width / 2, y: proxy.size.height - 168)

                HStack {
                    Text("\(selectedDecks.count) decks · \(selectedCount) cards")
                        .font(.custom(MitoFont.regular, size: 16))
                        .foregroundStyle(Color(hex: "3A2A18"))
                    Spacer()
                    Text("FREE · NO LIMITS")
                        .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color(hex: "4A8A3C"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                .padding(.horizontal, 16)
                .frame(width: proxy.size.width)
                .position(x: proxy.size.width / 2, y: proxy.size.height - 84)

                Button(action: onStart) {
                    HStack(spacing: 12) {
                        Text("▣")
                            .pixelText(size: 15, color: selectedDecks.isEmpty ? Color(hex: "D8CBA6") : Color(hex: "F4E6C0"))
                        Text(selectedDecks.isEmpty ? "PICK AT LEAST ONE DECK" : "START ENDLESS REVIEW")
                            .pixelText(size: 15, color: selectedDecks.isEmpty ? Color(hex: "D8CBA6") : Color(hex: "F4E6C0"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedDecks.isEmpty ? Color(hex: "47505A").opacity(0.78) : Color(hex: "4A8A3C"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(selectedDecks.isEmpty)
                .padding(.horizontal, 16)
                .frame(width: proxy.size.width)
                .position(x: proxy.size.width / 2, y: proxy.size.height - 30)
            }
        }
    }

    private func toggleDeck(_ deck: Deck) {
        if selectedDecks.contains(deck.id) {
            selectedDecks.remove(deck.id)
        } else {
            selectedDecks.insert(deck.id)
        }
        selectedTags.formIntersection(Set(availableTags))
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

private struct EndlessDeckRow: View {
    let deck: Deck
    let isSelected: Bool
    var highlightSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle()
                        .fill(isSelected ? Color(hex: "4A8A3C") : Color.white)
                    if isSelected {
                        Text("✓")
                            .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                    }
                }
                .frame(width: 24, height: 24)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                VStack(alignment: .leading, spacing: 5) {
                    Text(deck.name)
                        .pixelText(size: 13, color: Color(hex: "3A2A18"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        ForEach(deck.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .pixelText(size: 7, color: Color(hex: "3A2A18"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "F4E6C0"))
                        }
                        if deck.id == "bio" || deck.id == "orgo" {
                            Text("+1")
                                .font(.custom(MitoFont.regular, size: 12))
                                .foregroundStyle(Color(hex: "6B4324"))
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(deck.cards)")
                        .pixelText(size: 17, color: Color(hex: "3A2A18"))
                    Text("cards")
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "5B442A"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 72)
            .background(isSelected && highlightSelected ? Color(hex: "F4E6C0") : Color(hex: "B99868"))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(deck.color)
                    .frame(width: 8)
            }
            .overlay(Rectangle().stroke(isSelected && highlightSelected ? Color(hex: "FFD24D") : Color(hex: "18100A"), lineWidth: isSelected && highlightSelected ? 4 : 3))
        }
        .buttonStyle(.plain)
    }
}

private struct SetupScreen<Content: View>: View {
    let title: String
    let subtitle: String
    let back: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Image("map-bg")
                .screenBackground()
            Color.black.opacity(0.44).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        BackButton(action: back)
                        ScreenTitle(title, subtitle: subtitle)
                        Spacer()
                    }
                    content
                }
                .padding(14)
                .padding(.bottom, 18)
            }
        }
    }
}

private struct DeckPicker: View {
    @Binding var selectedDecks: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("CHOOSE DECKS")
            ForEach(DataSet.decks) { deck in
                Button {
                    if selectedDecks.contains(deck.id) {
                        selectedDecks.remove(deck.id)
                    } else {
                        selectedDecks.insert(deck.id)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(selectedDecks.contains(deck.id) ? Color(hex: "4A8A3C") : Color(hex: "F4E6C0"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(deck.name.uppercased())
                                .pixelText(size: 10, color: Color(hex: "3A2A18"))
                            HStack {
                                ForEach(deck.tags.prefix(3), id: \.self) { tag in
                                    SmallTag(tag.uppercased(), active: false)
                                }
                            }
                        }
                        Spacer()
                        Text("\(deck.cards)")
                            .pixelText(size: 13, color: Color(hex: "3A2A18"))
                    }
                    .padding(12)
                    .background(selectedDecks.contains(deck.id) ? Color(hex: "F4E6C0") : Color(hex: "B89868"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct TagPicker: View {
    @Binding var selectedTags: Set<String>
    private let tags = ["cell", "exam", "organelles", "vectors", "enzymes", "due"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("FILTER BY TAG")
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        if selectedTags.contains(tag) {
                            selectedTags.remove(tag)
                        } else {
                            selectedTags.insert(tag)
                        }
                    } label: {
                        SmallTag(tag.uppercased(), active: selectedTags.contains(tag))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CardEditor: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("FLASHCARD")
                .pixelText(size: 16, color: Color(hex: "3A2A18"))
            TextField("Front", text: .constant("What is the powerhouse of the cell?"))
                .textFieldStyle(.roundedBorder)
            TextField("Back", text: .constant("Mitochondria produces ATP."))
                .textFieldStyle(.roundedBorder)
            PixelButton(title: "SAVE") {
                dismiss()
            }
        }
        .padding(20)
        .background(Color(hex: "EAD4A4"))
    }
}

private struct WoodBackground: View {
    var body: some View {
        ZStack {
            Color(hex: "1D130A").ignoresSafeArea()
            VStack(spacing: 0) {
                ForEach(0..<18, id: \.self) { index in
                    Rectangle()
                        .fill(index % 2 == 0 ? Color(hex: "241508") : Color(hex: "1A0F06"))
                        .frame(height: 28)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.black.opacity(0.22)).frame(height: 1)
                        }
                }
                Spacer(minLength: 0)
            }
            .opacity(0.72)
            .ignoresSafeArea()
        }
    }
}

private struct ShopTab: View {
    let title: String
    let active: Bool

    init(_ title: String, active: Bool) {
        self.title = title
        self.active = active
    }

    var body: some View {
        Text(title)
            .pixelText(size: 9, color: active ? Color(hex: "18100A") : Color(hex: "F4E6C0"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(active ? Color(hex: "F7C943") : Color(hex: "6B4324"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

private struct ShopItemRow: View {
    let icon: String
    let title: String
    let detail: String
    let price: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(Color(hex: "18100A"))
                    .frame(width: 44, height: 44)
                    .background(accent)
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .pixelText(size: 12, color: Color(hex: "3A2A18"))
                    Text(detail)
                        .font(.custom(MitoFont.regular, size: 12))
                        .foregroundStyle(Color(hex: "6B4324"))
                        .lineLimit(2)
                    Text(title == "Focus Chest" ? "" : title == "ATP Flask" ? "⚡ + 30" : title == "Biomass Pouch" ? "● + 12" : "♦ + 3")
                        .font(.custom(MitoFont.regular, size: 10))
                        .foregroundStyle(title == "Biomass Pouch" ? Color(hex: "6DB04C") : Color(hex: "8B6BD9"))
                }
                Spacer(minLength: 0)

                Text(price)
                    .pixelText(size: 11, color: price.contains("FREE") ? .white : Color(hex: "18100A"))
                    .multilineTextAlignment(.center)
                    .frame(width: 66, height: 42)
                    .background(price.contains("FREE") ? Color(hex: "4A8A3C") : Color(hex: "F7C943"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .padding(8)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        }
        .buttonStyle(.plain)
    }
}

private struct StatBlock: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.custom(MitoFont.regular, size: 12))
                .foregroundStyle(Color(hex: "8A6B42"))
            Text(value)
                .pixelText(size: 23, color: color)
        }
    }
}

private struct TeamRosterCard: View {
    let hero: Hero
    let isInParty: Bool
    var isSelected = false
    var compact = false

    private var spriteSize: CGFloat {
        compact ? 46 : 70
    }

    private var imageHeight: CGFloat {
        compact ? 66 : 92
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [hero.color.opacity(0.42), Color(hex: "F4E6C0").opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(isInParty ? "IN" : "ADD")
                            .pixelText(size: 7, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(isInParty ? Color(hex: "6B4324") : Color(hex: "4A8A3C"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))

                        Spacer(minLength: 0)

                        Text("LV \(hero.level)")
                            .pixelText(size: 7, color: Color(hex: "18100A"))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .background(Color(hex: "F7C943"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .padding(4)

                    Spacer(minLength: 0)
                    Character(asset: hero.asset, size: spriteSize)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(height: imageHeight)

            VStack(spacing: 3) {
                Text(hero.name)
                    .pixelText(size: compact ? 8 : 10, color: Color(hex: "3A2A18"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(hero.role)
                    .font(.custom(MitoFont.regular, size: compact ? 10 : 12))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, compact ? 7 : 8)
            .background(Color(hex: "EAD4A4"))
        }
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .overlay {
            if isSelected {
                Rectangle()
                    .stroke(Color(hex: "FFD24D"), lineWidth: 3)
                Rectangle()
                    .stroke(Color(hex: "2D9CFF"), lineWidth: 2)
                    .padding(3)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct EmptyTeamSlot: View {
    let slotNumber: Int

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "6B4324").opacity(0.64), Color(hex: "2A1A0D").opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 8) {
                    Rectangle()
                        .stroke(
                            Color(hex: "EAD4A4").opacity(0.5),
                            style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                        )
                        .frame(width: 54, height: 42)
                        .overlay {
                            Text("+")
                                .pixelText(size: 18, color: Color(hex: "EAD4A4").opacity(0.68))
                        }

                    Text("SLOT \(slotNumber)")
                        .pixelText(size: 8, color: Color(hex: "B89868"))
                }
            }
            .frame(height: 92)

            VStack(spacing: 3) {
                Text("EMPTY")
                    .pixelText(size: 10, color: Color(hex: "8A6B42"))
                Text("Party slot")
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background(Color(hex: "D8BD82"))
        }
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .overlay(Rectangle().stroke(Color(hex: "6B4324"), lineWidth: 2).padding(4))
        .frame(maxWidth: .infinity)
    }
}

private struct TeamCardBoundsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct InlineCharacterActions: View {
    let inParty: Bool
    let canAdd: Bool
    var pointerOnTop = true
    let onInfo: () -> Void
    let onToggleParty: () -> Void

    private var toggleTitle: String {
        if inParty { return "REMOVE" }
        return canAdd ? "ADD" : "FULL"
    }

    var body: some View {
        VStack(spacing: 0) {
            if pointerOnTop {
                Triangle()
                    .fill(Color(hex: "6B4324"))
                    .frame(width: 12, height: 8)
            }

            VStack(spacing: 0) {
                Button(action: onInfo) {
                    Text("INFO")
                        .pixelText(size: 8, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 27)
                        .background(Color(hex: "6B4324"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("team-action-info")

                Rectangle()
                    .fill(Color(hex: "18100A"))
                    .frame(height: 3)

                Button(action: onToggleParty) {
                    Text(toggleTitle)
                        .pixelText(size: 8, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 29)
                        .background(inParty ? Color(hex: "D84A3A") : (canAdd ? Color(hex: "4A8A3C") : Color(hex: "8A6B42")))
                }
                .buttonStyle(.plain)
                .disabled(!inParty && !canAdd)
                .accessibilityIdentifier(inParty ? "team-action-remove" : "team-action-add")
            }
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

            if !pointerOnTop {
                Triangle()
                    .fill(inParty ? Color(hex: "D84A3A") : (canAdd ? Color(hex: "4A8A3C") : Color(hex: "8A6B42")))
                    .frame(width: 12, height: 8)
                    .rotationEffect(.degrees(180))
            }
        }
    }
}

private struct CharacterInfoModal: View {
    let hero: Hero
    let inParty: Bool
    let upgradeCost: Int
    let canUpgrade: Bool
    let onClose: () -> Void
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(hero.name.uppercased())
                    .pixelText(size: 17, color: Color(hex: "3A2A18"))
                Text(hero.role)
                    .font(.custom(MitoFont.regular, size: 16))
                    .foregroundStyle(Color(hex: "6B4324"))
                Spacer()
                Button(action: onClose) {
                    Text("×")
                        .font(.custom(MitoFont.regular, size: 22))
                        .foregroundStyle(Color(hex: "3A2A18"))
                }
                .buttonStyle(.plain)
            }

            ZStack(alignment: .top) {
                LinearGradient(colors: [hero.color.opacity(0.38), Color(hex: "E8D0B0")], startPoint: .top, endPoint: .bottom)
                Character(asset: hero.asset, size: 164)
                    .padding(.top, 36)

                HStack {
                    Text("LV \(hero.level)")
                        .pixelText(size: 12, color: Color(hex: "18100A"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "F7C943"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    Spacer()
                    Text(inParty ? "IN PARTY" : "RESERVE")
                        .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(inParty ? Color(hex: "4A8A3C") : Color(hex: "6B4324"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .padding(10)
            }
            .frame(height: 205)
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

            HStack(spacing: 8) {
                ModalStat(label: "HP", value: hero.hp, color: Color(hex: "3F8A3D"))
                ModalStat(label: "ATK", value: hero.attack, color: Color(hex: "D4873A"))
                ModalStat(label: "DEF", value: hero.defense, color: Color(hex: "4277D9"))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("LORE")
                    .pixelText(size: 10, color: Color(hex: "8A6B42"))
                Text(hero.lore)
                    .font(.custom(MitoFont.regular, size: 16))
                    .foregroundStyle(Color(hex: "3A2A18"))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "F4E6C0"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LEVEL UP")
                        .pixelText(size: 11, color: Color(hex: "3A2A18"))
                    Text("+5 HP · +3 ATK · +2 DEF")
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
                }
                Spacer()
                Button(action: onUpgrade) {
                    VStack(spacing: 1) {
                        Text("◎ \(upgradeCost)")
                            .pixelText(size: 11, color: Color(hex: "18100A"))
                        Text("UPGRADE")
                            .pixelText(size: 8, color: Color(hex: "3A2A18"))
                    }
                    .frame(width: 76, height: 39)
                    .background(canUpgrade ? Color(hex: "F7C943") : Color(hex: "8A6B42"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(!canUpgrade)
            }
            .padding(10)
            .background(Color(hex: "F4E6C0"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        }
        .padding(13)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

private struct ModalStat: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.custom(MitoFont.regular, size: 12))
                .foregroundStyle(Color(hex: "8A6B42"))
            Text("\(value)")
                .pixelText(size: 20, color: color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct DeckLibraryRow: View {
    let deck: Deck
    let progress: Double

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(deck.color)
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(deck.name)
                        .pixelText(size: 14, color: Color(hex: "3A2A18"))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(deck.cards)")
                            .pixelText(size: 18, color: Color(hex: "3A2A18"))
                        Text("cards")
                            .font(.custom(MitoFont.regular, size: 11))
                            .foregroundStyle(Color(hex: "8A6B42"))
                    }
                }
                HStack(spacing: 5) {
                    ForEach(deck.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .pixelText(size: 7, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: "F4E6C0"))
                            .overlay(Rectangle().stroke(Color(hex: "B89868"), lineWidth: 1))
                    }
                    if deck.id == "bio" || deck.id == "orgo" {
                        Text("+1")
                            .font(.custom(MitoFont.regular, size: 11))
                            .foregroundStyle(Color(hex: "6B4324"))
                    }
                }
                HStack(spacing: 8) {
                    ProgressBar(progress: progress, color: deck.color)
                    Text("\(Int(progress * 100))%")
                        .font(.custom(MitoFont.regular, size: 11))
                        .foregroundStyle(Color(hex: "3A2A18"))
                    Text(">")
                        .font(.custom(MitoFont.regular, size: 14))
                        .foregroundStyle(Color(hex: "3A2A18"))
                }
            }
            .padding(.vertical, 9)
            .padding(.trailing, 10)
        }
        .frame(height: 76)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .padding(.horizontal, 16)
    }
}

private struct ProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: "B89868"))
                Rectangle()
                    .fill(color)
                    .frame(width: proxy.size.width * progress)
            }
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .frame(height: 8)
    }
}

private struct ShopCard: View {
    let title: String
    let detail: String
    let cost: String
    let gain: String
    let action: () -> Void

    var body: some View {
        ParchmentBox {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title.uppercased())
                        .pixelText(size: 11, color: Color(hex: "3A2A18"))
                    Text(detail)
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "6B4324"))
                    HStack {
                        SmallTag(cost, active: false)
                        SmallTag(gain, active: true)
                    }
                }
                Spacer()
                Button(action: action) {
                    Text("BUY")
                        .pixelText(size: 9, color: .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(hex: "4A8A3C"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct HeroRow: View {
    let hero: Hero
    let upgrade: () -> Void

    var body: some View {
        ParchmentBox {
            HStack(spacing: 12) {
                Character(asset: hero.asset, size: 58)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(hero.name.uppercased())
                            .pixelText(size: 12, color: Color(hex: "3A2A18"))
                        SmallTag("LV \(hero.level)", active: true)
                    }
                    Text(hero.role)
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "6B4324"))
                    HPBar(value: hero.hp, max: 60, tint: hero.color)
                    HStack(spacing: 7) {
                        StatPill("ATK \(hero.attack)")
                        StatPill("DEF \(hero.defense)")
                    }
                }
                Button(action: upgrade) {
                    Text("UP")
                        .pixelText(size: 9, color: .white)
                        .padding(10)
                        .background(Color(hex: "4A8A3C"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FeatureButton: View {
    let title: String
    let badge: String?
    let detail: String
    let tint: Color
    var height: CGFloat = 84

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                .frame(width: 52, height: 52)
                .overlay(Text(title == "ENDLESS REVIEW" ? "B" : "X").pixelText(size: 18, color: .white))
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .pixelText(size: 15, color: .white)
                if let badge {
                    Text(badge)
                        .pixelText(size: 7, color: Color(hex: "18100A"))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(hex: "F7C943"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 1.5))
                }
                Text(detail)
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
            }
            Spacer()
            Text(">")
                .pixelText(size: 18, color: .white)
        }
        .padding(12)
        .frame(height: height)
        .background(tint)
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
    }
}

private struct ResourceRow: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack {
            Text(label.uppercased())
                .pixelText(size: 10, color: Color(hex: "F4E6C0"))
            Spacer()
            Text("\(value)")
                .pixelText(size: 13, color: color)
        }
        .padding(12)
        .background(Color.black.opacity(0.32))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }
}

private struct ToggleRow: View {
    let title: String
    let detail: String
    let isOn: Bool

    var body: some View {
        ParchmentBox {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .pixelText(size: 10, color: Color(hex: "3A2A18"))
                    Text(detail)
                        .font(.custom(MitoFont.regular, size: 14))
                        .foregroundStyle(Color(hex: "6B4324"))
                }
                Spacer()
                Rectangle()
                    .fill(isOn ? Color(hex: "4A8A3C") : Color(hex: "888894"))
                    .frame(width: 42, height: 24)
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }
        }
    }
}

private struct AnswerButton: View {
    let asset: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(asset)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .overlay(Text(title).pixelText(size: 10, color: Color(hex: "3A2A18")).opacity(0.001))
        }
        .buttonStyle(.plain)
    }
}

private struct StudyWanderer: Identifiable {
    let id: String
    let asset: String
    let size: CGFloat
    let start: CGPoint
    let seed: UInt64

    static let all: [StudyWanderer] = [
        StudyWanderer(id: "astro", asset: "hero-astrocyte-hop", size: 56, start: CGPoint(x: 0.13, y: 0.29), seed: 0xA517_0021),
        StudyWanderer(id: "dendri", asset: "hero-dendritic-cell-hop", size: 56, start: CGPoint(x: 0.39, y: 0.38), seed: 0xD31D_0022),
        StudyWanderer(id: "mito", asset: "hero-mito-hop", size: 62, start: CGPoint(x: 0.63, y: 0.43), seed: 0x4170_0023),
        StudyWanderer(id: "chloro", asset: "hero-chloroplast-hop", size: 52, start: CGPoint(x: 0.31, y: 0.56), seed: 0xC410_0024),
        StudyWanderer(id: "neuro", asset: "hero-neuron-hop", size: 52, start: CGPoint(x: 0.55, y: 0.66), seed: 0xE900_0025)
    ]
}

private struct StudyWanderingCharacter: View {
    let wanderer: StudyWanderer
    let canvasSize: CGSize

    private let frameCount = 8
    private let secondsPerFrame = 0.14
    private let tick: TimeInterval = 1 / 30

    @State private var position: CGPoint
    @State private var isMoving = false
    @State private var isMovingRight = false
    @State private var frame = 0

    init(wanderer: StudyWanderer, canvasSize: CGSize) {
        self.wanderer = wanderer
        self.canvasSize = canvasSize
        _position = State(initialValue: wanderer.start)
    }

    var body: some View {
        Character(
            asset: wanderer.asset,
            size: wanderer.size,
            mirrored: isMovingRight,
            frame: isMoving ? frame : 0
        )
        .position(x: position.x * canvasSize.width, y: position.y * canvasSize.height)
        .task(id: wanderer.id) {
            await runWanderLoop()
        }
    }

    private func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    @MainActor
    private func runWanderLoop() async {
        let launchVariance = UInt64(Date().timeIntervalSinceReferenceDate * 1_000)
        var generator = SeededGenerator(seed: wanderer.seed ^ launchVariance)
        position = StudyWalkMap.clampedWalkable(wanderer.start)
        isMoving = false
        frame = 0
        StudyCollisionRegistry.update(id: wanderer.id, position: position)

        while !Task.isCancelled {
            let rest = Double.random(in: 1.0...4.0, using: &generator)
            try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000))
            if Task.isCancelled { break }

            let start = position
            let occupied = StudyCollisionRegistry.occupiedPoints(excluding: wanderer.id)
            let target = StudyWalkMap.randomDestination(from: start, avoiding: occupied, using: &generator)
            let distance = start.distance(to: target)
            if distance < 0.015 { continue }
            guard StudyCollisionRegistry.reserve(id: wanderer.id, target: target, minimumDistance: StudyWalkMap.characterSpacing) else {
                continue
            }

            let duration = min(max(distance * 16, 1.15), 3.4)
            let startTime = Date().timeIntervalSinceReferenceDate
            isMoving = true
            isMovingRight = target.x > start.x

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSinceReferenceDate - startTime
                if elapsed >= duration { break }

                let progress = smoothstep(elapsed / duration)
                position = start.interpolated(to: target, progress: progress)
                StudyCollisionRegistry.update(id: wanderer.id, position: position)
                frame = Int(elapsed / secondsPerFrame) % frameCount
                try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
            }

            position = target
            StudyCollisionRegistry.update(id: wanderer.id, position: position)
            StudyCollisionRegistry.releaseReservation(id: wanderer.id)
            frame = 0
            isMoving = false
        }

        StudyCollisionRegistry.remove(id: wanderer.id)
    }
}

private enum StudyWalkMap {
    static let characterSpacing = 0.11

    private static let walkBounds = CGRect(x: 0.08, y: 0.20, width: 0.78, height: 0.54)

    private static let obstacles: [CGRect] = [
        CGRect(x: 0.00, y: 0.00, width: 0.62, height: 0.18), // top trees and fence
        CGRect(x: 0.00, y: 0.35, width: 0.30, height: 0.25), // water and rocks
        CGRect(x: 0.55, y: 0.10, width: 0.45, height: 0.31), // house, mailbox, and right-side props
        CGRect(x: 0.49, y: 0.25, width: 0.12, height: 0.09), // house-side rocks and flowers
        CGRect(x: 0.75, y: 0.24, width: 0.12, height: 0.11), // mailbox and front props
        CGRect(x: 0.15, y: 0.57, width: 0.17, height: 0.09), // lower-left rocks
        CGRect(x: 0.66, y: 0.63, width: 0.22, height: 0.10), // lower-right fence
        CGRect(x: 0.87, y: 0.38, width: 0.13, height: 0.34), // right fence/tree edge
        CGRect(x: 0.00, y: 0.76, width: 1.00, height: 0.24) // study button and nav
    ]

    static func clampedWalkable(_ point: CGPoint) -> CGPoint {
        if isWalkable(point) { return point }
        return CGPoint(x: 0.45, y: 0.50)
    }

    static func randomDestination(from current: CGPoint, avoiding occupied: [CGPoint], using generator: inout SeededGenerator) -> CGPoint {
        for _ in 0..<80 {
            let candidate = CGPoint(
                x: Double.random(in: walkBounds.minX...walkBounds.maxX, using: &generator),
                y: Double.random(in: walkBounds.minY...walkBounds.maxY, using: &generator)
            )
            let distance = current.distance(to: candidate)
            if distance >= 0.06,
               distance <= 0.28,
               isWalkable(candidate),
               clearsCharacters(candidate, avoiding: occupied),
               pathIsWalkable(from: current, to: candidate),
               pathClearsCharacters(from: current, to: candidate, avoiding: occupied) {
                return candidate
            }
        }

        return current
    }

    private static func isWalkable(_ point: CGPoint) -> Bool {
        guard walkBounds.contains(point) else { return false }
        return !obstacles.contains { $0.contains(point) }
    }

    private static func clearsCharacters(_ point: CGPoint, avoiding occupied: [CGPoint]) -> Bool {
        !occupied.contains { point.distance(to: $0) < characterSpacing }
    }

    private static func pathClearsCharacters(from start: CGPoint, to end: CGPoint, avoiding occupied: [CGPoint]) -> Bool {
        for step in 0...12 {
            let progress = Double(step) / 12
            if !clearsCharacters(start.interpolated(to: end, progress: progress), avoiding: occupied) {
                return false
            }
        }
        return true
    }

    private static func pathIsWalkable(from start: CGPoint, to end: CGPoint) -> Bool {
        for step in 0...18 {
            let progress = Double(step) / 18
            if !isWalkable(start.interpolated(to: end, progress: progress)) {
                return false
            }
        }
        return true
    }
}

@MainActor
private enum StudyCollisionRegistry {
    private static var positions: [String: CGPoint] = [:]
    private static var reservations: [String: CGPoint] = [:]

    static func update(id: String, position: CGPoint) {
        positions[id] = position
    }

    static func reserve(id: String, target: CGPoint, minimumDistance: Double) -> Bool {
        let blocked = occupiedPoints(excluding: id)
        guard !blocked.contains(where: { target.distance(to: $0) < minimumDistance }) else {
            return false
        }

        reservations[id] = target
        return true
    }

    static func releaseReservation(id: String) {
        reservations.removeValue(forKey: id)
    }

    static func remove(id: String) {
        positions.removeValue(forKey: id)
        reservations.removeValue(forKey: id)
    }

    static func occupiedPoints(excluding id: String) -> [CGPoint] {
        let current = positions.filter { $0.key != id }.map(\.value)
        let claimed = reservations.filter { $0.key != id }.map(\.value)
        return current + claimed
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        let dx = other.x - x
        let dy = other.y - y
        return sqrt(dx * dx + dy * dy)
    }

    func interpolated(to other: CGPoint, progress: Double) -> CGPoint {
        CGPoint(
            x: x + (other.x - x) * progress,
            y: y + (other.y - y) * progress
        )
    }
}

private struct Character: View {
    let asset: String
    let size: CGFloat
    var mirrored = false
    var frame = 0

    private let frameCount = 8
    private let frameAspectRatio: CGFloat = 200 / 128

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.32))
                .frame(width: size * 0.55, height: size * 0.13)
                .blur(radius: 1)
                .offset(y: 2)
            spriteFrame(frame)
        }
        .frame(width: size, height: size)
    }

    private func spriteFrame(_ frame: Int) -> some View {
        let frameWidth = size * frameAspectRatio
        let normalizedFrame = min(max(frame, 0), frameCount - 1)

        return Image(asset)
            .resizable()
            .interpolation(.none)
            .frame(width: frameWidth * CGFloat(frameCount), height: size)
            .offset(x: -frameWidth * CGFloat(normalizedFrame))
            .frame(width: frameWidth, height: size, alignment: .leading)
            .clipped()
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .frame(width: size, height: size)
    }
}

private struct HPBar: View {
    let value: Int
    let max: Int
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: "2A1A14"))
                Rectangle()
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(value) / CGFloat(max))
                HStack(spacing: 19) {
                    ForEach(0..<8, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.black.opacity(0.18))
                            .frame(width: 1)
                    }
                }
            }
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .frame(height: 14)
    }
}

private struct ParchmentBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

private struct PixelButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .pixelText(size: 13, color: Color(hex: "F4E6C0"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "4A8A3C"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        }
        .buttonStyle(.plain)
    }
}

private struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("<")
                .pixelText(size: 15, color: Color(hex: "F4E6C0"))
                .frame(width: 34, height: 34)
                .background(Color(hex: "6B4324"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

private struct ScreenTitle: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .pixelText(size: 16, color: Color(hex: "F4E6C0"))
            Text(subtitle)
                .font(.custom(MitoFont.regular, size: 13))
                .foregroundStyle(Color(hex: "F4E6C0").opacity(0.84))
        }
    }
}

private struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .pixelText(size: 9, color: Color(hex: "FFD24D"))
    }
}

private struct SmallTag: View {
    let title: String
    let active: Bool

    init(_ title: String, active: Bool) {
        self.title = title
        self.active = active
    }

    var body: some View {
        Text(title)
            .pixelText(size: 7, color: active ? .white : Color(hex: "4A2F1C"))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(active ? Color(hex: "6B9C4A") : Color(hex: "D8B884"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 1.5))
    }
}

private struct StatPill: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .pixelText(size: 8, color: Color(hex: "3A2A18"))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(hex: "F4E6C0"))
            .overlay(Rectangle().stroke(Color(hex: "B89868"), lineWidth: 1))
    }
}

private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let len = min(rect.width, rect.height) * 0.22
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        return path
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private let sampleQuestions = [
    "What molecule stores usable cellular energy after mitochondria charge it?",
    "What structure controls what enters and leaves the cell?",
    "Which organelle packages proteins for delivery?",
    "What carries electrons into the electron transport chain?"
]

private let sampleAnswers = [
    "ATP stores immediately usable cellular energy.",
    "The plasma membrane regulates traffic in and out.",
    "The Golgi apparatus modifies, sorts, and packages proteins.",
    "NADH and FADH2 carry electrons to the ETC."
]

private extension Image {
    func screenBackground() -> some View {
        self.resizable()
            .interpolation(.none)
            .scaledToFill()
            .ignoresSafeArea()
    }
}

private enum MitoFont {
    static let regular = "PixelifySans-Regular"
    static let bold = "PixelifySans-Regular"
    static let micro = "Silkscreen-Bold"
}

private extension Text {
    func pixelText(size: CGFloat, color: Color) -> some View {
        self.font(.custom(MitoFont.bold, size: size * 1.16).weight(.bold))
            .foregroundStyle(color)
            .textCase(.uppercase)
            .lineLimit(2)
            .minimumScaleFactor(0.65)
    }
}

private extension View {
    func authInputStyle() -> some View {
        self.font(.custom(MitoFont.regular, size: 18))
            .foregroundStyle(Color(hex: "3A2A18"))
            .padding(10)
            .background(Color(hex: "F4E6C0"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

private extension Color {
    static let mitoWoodDarkest = Color(hex: "1D130A")

    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch clean.count {
        case 3:
            r = (value >> 8) * 17
            g = ((value >> 4) & 0xF) * 17
            b = (value & 0xF) * 17
        default:
            r = value >> 16
            g = (value >> 8) & 0xFF
            b = value & 0xFF
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}
