import SwiftUI

struct HomeScreen: View {
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

enum StudyMode: String, CaseIterable, Identifiable {
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

struct TimerPanel: View {
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
