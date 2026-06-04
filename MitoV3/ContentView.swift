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
