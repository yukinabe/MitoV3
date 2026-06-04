import SwiftUI

struct HomeScreen: View {
    @Binding var atp: Int
    @ObservedObject var backend: MitoBackend
    @State private var showPicker = false
    @State private var sessionMode: StudyMode?
    @State private var showingSettings = false
    @State private var showingAuth = false

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
                if sessionMode == nil {
                    ForEach(StudyWanderer.all) { wanderer in
                        StudyWanderingCharacter(wanderer: wanderer, canvasSize: proxy.size)
                    }
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
                    if showPicker {
                        ModePickerPanel(
                            close: {
                                withAnimation(.easeOut(duration: 0.18)) { showPicker = false }
                            },
                            start: { mode in
                                showPicker = false
                                sessionMode = mode
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
            }
            .fullScreenCover(item: $sessionMode) { mode in
                FocusSession(mode: mode, presented: $sessionMode) { reward in
                    atp += reward
                }
            }
        }
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
    let onEnd: (Int) -> Void

    @State private var elapsed = 0          // seconds actually studied
    @State private var finished = false
    @State private var earned = 0

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

                ForEach(StudyWanderer.focusSet) { wanderer in
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
                Text(earned > 0 ? "+\(earned) ATP" : "No reward (study 5+ min)")
                    .pixelText(size: 15, color: earned > 0 ? Color(hex: "C8881A") : Color(hex: "8A6A40"))
                Button {
                    onEnd(earned)
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
        earned = mode.atpReward(studiedSeconds: elapsed)
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
