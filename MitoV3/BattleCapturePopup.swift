//  BattleCapturePopup.swift
//  Extracted from BattleView.swift (behavior-preserving refactor).

import SwiftUI

// MARK: - Capture popup

/// Offered after defeating a capturable wild creature. Catch it to add it to your
/// collection (usable as a team member) or let it go.
struct CapturePopup: View {
    let creature: Hero
    let onCapture: () -> Void
    let onContinue: () -> Void
    let onRelease: () -> Void

    @State private var captured = false
    @State private var shareImage: Image?

    var body: some View {
        NewBioBudReveal(hero: creature, collected: captured) {
            if captured {
                if let shareImage {
                    BioBudShareButton(image: shareImage, hero: creature)
                }
                Button(action: onContinue) {
                    RevealActionLabel(title: L("CONTINUE"), color: Color(hex: "4A8A3C"))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    Button(action: onRelease) {
                        RevealActionLabel(title: L("LET GO"), color: Color(hex: "6B4324"))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onCapture()
                        AudioManager.shared.play(.reward)
                        Haptics.success()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.58)) {
                            captured = true
                        }
                    } label: {
                        RevealActionLabel(
                            title: L("✦ CAPTURE"),
                            color: Color(hex: "FFD24D"),
                            textColor: Color(hex: "1A130A")
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            shareImage = BioBudShareCard.render(hero: creature)
        }
    }
}

// MARK: - Recruit popup

/// Shown after beating a campaign boss who is a recruitable base hero. Unlike a
/// wild capture there's no "let go" — defeating the boss recruits them outright.
struct RecruitPopup: View {
    let hero: Hero
    let onJoin: () -> Void
    let onContinue: () -> Void

    @State private var joined = false
    @State private var shareImage: Image?

    var body: some View {
        NewBioBudReveal(hero: hero, collected: joined) {
            if joined {
                if let shareImage {
                    BioBudShareButton(image: shareImage, hero: hero)
                }
                Button(action: onContinue) {
                    RevealActionLabel(title: L("CONTINUE"), color: Color(hex: "4A8A3C"))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    onJoin()
                    AudioManager.shared.play(.reward)
                    Haptics.success()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.58)) {
                        joined = true
                    }
                } label: {
                    RevealActionLabel(
                        title: L("✦ ADD TO ROSTER"),
                        color: Color(hex: "FFD24D"),
                        textColor: Color(hex: "1A130A")
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            shareImage = BioBudShareCard.render(hero: hero)
        }
    }
}

// MARK: - Full-screen reveal

private struct NewBioBudReveal<Actions: View>: View {
    let hero: Hero
    let collected: Bool
    @ViewBuilder let actions: Actions

    @State private var revealScale: CGFloat = 0.45
    @State private var revealOpacity = 0.0
    @State private var spriteFrame = 0

    private var legendary: Bool { hero.rarity == .legendary }
    private var spriteSize: CGFloat { legendary ? 218 : 188 }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.84)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        hero.rarity.color.opacity(legendary ? 0.72 : 0.48),
                        Color(hex: "24150B").opacity(0.88),
                        Color.black
                    ],
                    center: .center,
                    startRadius: 18,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.68
                )
                .ignoresSafeArea()

                if hero.rarity >= .rare {
                    RarityBeams(rarity: hero.rarity)
                }

                BioBudBurst(rarity: hero.rarity)

                VStack(spacing: 12) {
                    Spacer(minLength: 18)

                    Text(L("NEW BIOBUD"))
                        .pixelText(size: legendary ? 24 : 21, color: Color(hex: "FFD24D"))
                        .shadow(color: hero.rarity.color, radius: legendary ? 12 : 6)

                    Text(collected ? L("ADDED TO YOUR COLLECTION") : L("BIOBUD DISCOVERED"))
                        .pixelText(
                            size: 10,
                            color: collected ? Color(hex: "9CD67D") : Color(hex: "F4E6C0")
                        )

                    if hero.rarity >= .rare {
                        RarityBanner(rarity: hero.rarity)
                    }

                    ZStack {
                        Rectangle()
                            .fill(Color(hex: "1A1009").opacity(0.68))
                        Rectangle()
                            .fill(hero.rarity.color.opacity(legendary ? 0.28 : 0.18))
                            .padding(7)
                        SpriteView(asset: hero.asset, size: spriteSize, frame: spriteFrame)
                    }
                    .frame(width: min(proxy.size.width - 42, 350), height: legendary ? 252 : 224)
                    .overlay(Rectangle().stroke(hero.rarity.color, lineWidth: legendary ? 7 : 5))
                    .overlay(Rectangle().stroke(Color(hex: "FFD24D"), lineWidth: legendary ? 2 : 0).padding(7))
                    .scaleEffect(revealScale)
                    .opacity(revealOpacity)

                    VStack(spacing: 7) {
                        Text(L(hero.name).uppercased())
                            .pixelText(size: legendary ? 25 : 22, color: Color(hex: "F4E6C0"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        HStack(spacing: 8) {
                            Text(hero.rarity.label)
                                .pixelText(size: 10, color: Color(hex: "18100A"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(hero.rarity.color)
                                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                            Text(L(hero.role).uppercased())
                                .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                        }

                        Text(L(hero.lore))
                            .font(.custom(MitoFont.regular, size: 14))
                            .foregroundStyle(Color(hex: "E9D8B6"))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: min(proxy.size.width - 36, 370))
                    .background(Color(hex: "2A1B0E").opacity(0.94))
                    .overlay(Rectangle().stroke(hero.rarity.color, lineWidth: 4))

                    VStack(spacing: 9) {
                        actions
                    }
                    .frame(maxWidth: min(proxy.size.width - 42, 350))

                    Spacer(minLength: 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // Higher rarity = a slower, more dramatic grow from a smaller start.
            revealScale = legendary ? 0.24 : (hero.rarity >= .epic ? 0.34 : 0.45)
            let response = legendary ? 1.05 : (hero.rarity >= .epic ? 0.82 : 0.62)
            withAnimation(.spring(response: response, dampingFraction: 0.6)) {
                revealScale = 1
                revealOpacity = 1
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                spriteFrame = (spriteFrame + 1) % 8
            }
        }
    }
}

private struct BioBudBurst: View {
    let rarity: Rarity
    @State private var expanded = false

    private var particleCount: Int {
        switch rarity {
        case .common: 12
        case .rare: 18
        case .epic: 24
        case .legendary: 34
        }
    }

    private var burstColor: Color {
        rarity == .legendary ? Color(hex: "FFD24D") : rarity.color
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<particleCount, id: \.self) { index in
                    let angle = Double(index) / Double(particleCount) * Double.pi * 2
                    let ring = CGFloat(0.28 + Double(index % 4) * 0.055)
                    Rectangle()
                        .fill(index.isMultiple(of: 3) ? Color(hex: "F4E6C0") : burstColor)
                        .frame(
                            width: rarity == .legendary && index.isMultiple(of: 4) ? 9 : 5,
                            height: rarity == .legendary && index.isMultiple(of: 4) ? 18 : 10
                        )
                        .rotationEffect(.radians(angle))
                        .position(
                            x: proxy.size.width / 2 + (expanded ? cos(angle) * proxy.size.width * ring : 0),
                            y: proxy.size.height * 0.43 + (expanded ? sin(angle) * proxy.size.width * ring : 0)
                        )
                        .opacity(expanded ? 0.12 : 1)
                        .scaleEffect(expanded ? 0.55 : 1.35)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: rarity == .legendary ? 1.35 : 1.0)) {
                    expanded = true
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Rotating god-rays behind a rare-or-better reveal. Ray count, width, opacity
/// and spin speed all step up with rarity so a legendary pull reads as obviously
/// bigger than a rare one. Gold for legendary, the rarity tint otherwise.
private struct RarityBeams: View {
    let rarity: Rarity
    @State private var spin = false

    private var rayCount: Int {
        switch rarity {
        case .legendary: 18
        case .epic: 13
        default: 10
        }
    }
    private var rayWidth: CGFloat { rarity == .legendary ? 30 : (rarity == .epic ? 22 : 16) }
    private var color: Color { rarity == .legendary ? Color(hex: "FFE27A") : rarity.color }
    private var maxOpacity: Double {
        switch rarity {
        case .legendary: 0.6
        case .epic: 0.42
        default: 0.28
        }
    }
    private var spinSeconds: Double { rarity == .legendary ? 16 : 24 }

    var body: some View {
        GeometryReader { proxy in
            let dim = max(proxy.size.width, proxy.size.height) * 1.5
            ZStack {
                // Soft halo so the area behind the sprite glows.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(maxOpacity * 0.9), .clear],
                            center: .center, startRadius: 0, endRadius: dim * 0.26
                        )
                    )
                    .frame(width: dim, height: dim)

                // God-rays: each spoke is brightest at the centre and fades outward.
                ZStack {
                    ForEach(0..<rayCount, id: \.self) { i in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(maxOpacity), .clear],
                                    startPoint: .bottom, endPoint: .top
                                )
                            )
                            .frame(width: rayWidth, height: dim * 0.5)
                            .offset(y: -dim * 0.25)
                            .rotationEffect(.degrees(Double(i) / Double(rayCount) * 360))
                    }
                }
                .frame(width: dim, height: dim)
                .rotationEffect(.degrees(spin ? 360 : 0))
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.43)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: spinSeconds).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }
}

/// The rarity word that slams in on a rare-or-better reveal. Legendary gets stars
/// and a gold tint; the punch (overshoot scale) is sized by rarity.
private struct RarityBanner: View {
    let rarity: Rarity
    @State private var punch = false

    private var text: String {
        switch rarity {
        case .legendary: "★  LEGENDARY  ★"
        case .epic: "✦  EPIC  ✦"
        case .rare: "RARE"
        case .common: ""
        }
    }
    private var color: Color { rarity == .legendary ? Color(hex: "FFE27A") : rarity.color }
    private var size: CGFloat {
        switch rarity {
        case .legendary: 18
        case .epic: 14
        default: 11
        }
    }

    var body: some View {
        Text(text)
            .pixelText(size: size, color: color)
            .shadow(color: color.opacity(0.8), radius: rarity == .legendary ? 14 : 6)
            .scaleEffect(punch ? 1 : (rarity == .legendary ? 1.7 : 1.3))
            .opacity(punch ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) { punch = true }
            }
    }
}

private struct RevealActionLabel: View {
    let title: String
    let color: Color
    var textColor = Color(hex: "F4E6C0")

    var body: some View {
        Text(title)
            .pixelText(size: 12, color: textColor)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(color)
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

private struct BioBudShareButton: View {
    let image: Image
    let hero: Hero

    var body: some View {
        ShareLink(
            item: image,
            preview: SharePreview("My new BioBud: \(hero.name)", image: image)
        ) {
            RevealActionLabel(
                title: L("SHARE"),
                color: hero.rarity.color,
                textColor: Color(hex: "18100A")
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BioBudShareCard: View {
    let hero: Hero

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "182116"), Color(hex: "2A1B0E"), Color(hex: "090604")],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [hero.rarity.color.opacity(0.62), .clear],
                center: .center,
                startRadius: 12,
                endRadius: 210
            )

            VStack(spacing: 18) {
                Text("MITO")
                    .pixelText(size: 23, color: Color(hex: "FFD24D"))
                    .padding(.top, 34)
                Text(L("NEW BIOBUD"))
                    .pixelText(size: 15, color: Color(hex: "F4E6C0"))

                SpriteView(asset: hero.asset, size: hero.rarity == .legendary ? 186 : 164, frame: 0)

                VStack(spacing: 9) {
                    Text(L(hero.name).uppercased())
                        .pixelText(size: 25, color: Color(hex: "F4E6C0"))
                    Text(hero.rarity.label)
                        .pixelText(size: 11, color: Color(hex: "18100A"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(hero.rarity.color)
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    Text(L(hero.lore))
                        .font(.custom(MitoFont.regular, size: 14))
                        .foregroundStyle(Color(hex: "E9D8B6"))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 22)
                }

                Spacer()
                Text(L("ADDED TO YOUR COLLECTION"))
                    .pixelText(size: 9, color: Color(hex: "9CD67D"))
                    .padding(.bottom, 28)
            }
        }
        .frame(width: 300, height: 533)
        .overlay(Rectangle().stroke(hero.rarity.color, lineWidth: 7))
    }

    @MainActor
    static func render(hero: Hero) -> Image? {
        let renderer = ImageRenderer(content: BioBudShareCard(hero: hero))
        renderer.scale = 3
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

// MARK: - Egg hatch (gacha) screen

/// Full-screen hatch screen, reached from the egg button on the home meadow.
/// Eggs are earned by studying; here you spend them to hatch biobuds (×1 or
/// ×10). Reuses the NewBioBudReveal for the new-biobud moment.
struct HatchView: View {
    private enum HatchPhase: Equatable {
        case home
        case zooming(Int)
        case drawing(Int)
        case cracking(Int)

        var eggCount: Int? {
            switch self {
            case .home: nil
            case let .zooming(count), let .drawing(count), let .cracking(count): count
            }
        }
    }

    @Binding var isPresented: Bool
    @ObservedObject private var egg = EggStore.shared
    @State private var single: HatchResult?
    @State private var multi: [HatchResult]?
    @State private var shareImage: Image?
    @State private var eggWobble = false
    @State private var phase: HatchPhase = .home
    @State private var drawnPoints: [CGPoint] = []
    @State private var strokeLength: CGFloat = 0
    @State private var ritualScale: CGFloat = 0.58
    @State private var ritualOpacity = 0.0
    @State private var crackPulse = false
    @State private var flashOpacity = 0.0
    @State private var nudge = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: "3A2A18"), Color(hex: "140D07"), Color.black],
                center: .center, startRadius: 24, endRadius: 560
            )
            .ignoresSafeArea()

            if let single {
                singleReveal(single)
            } else if let multi {
                MultiRevealSequence(results: multi) { self.multi = nil }
            } else if phase != .home {
                hatchRitual
            } else {
                hatchHome
            }

            Color.white
                .ignoresSafeArea()
                .opacity(flashOpacity)
                .allowsHitTesting(false)
        }
    }

    // MARK: Home
    private var hatchHome: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button { isPresented = false } label: {
                    Text("X").pixelText(size: 14, color: Color(hex: "F4E6C0")).padding(12)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HatchEgg()
                .frame(width: 112, height: 142)
                .rotationEffect(.degrees(eggWobble ? 6 : -6))
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: eggWobble)
            Text("\(egg.eggs)")
                .pixelText(size: 30, color: Color(hex: "F7C943"))
            Text(egg.eggs == 1 ? "EGG" : "EGGS")
                .pixelText(size: 10, color: Color(hex: "E9D8B6"))
            Text("study sessions hatch biobuds")
                .font(.custom(MitoFont.regular, size: 14))
                .foregroundStyle(Color(hex: "E9D8B6"))
            if egg.shards > 0 {
                Text("✦ \(egg.shards) SHARDS")
                    .pixelText(size: 9, color: Color(hex: "C7A6F2"))
            }
            Spacer()
            VStack(spacing: 10) {
                hatchButton("HATCH ×1", enabled: egg.canHatchOne) {
                    beginRitual(count: 1)
                }
                hatchButton("HATCH ×10", enabled: egg.canHatchTen) {
                    beginRitual(count: 10)
                }
            }
            .padding(.bottom, 34)
        }
        .padding(.horizontal, 22)
        .onAppear { eggWobble = true }
    }

    private func hatchButton(_ title: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            guard enabled else { return }
            AudioManager.shared.play(.uiTap)
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .pixelText(size: 15, color: Color(hex: "1A130A"))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(enabled ? Color(hex: "F7C943") : Color(hex: "6B4324"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.55)
    }

    // MARK: Hatch ritual
    private var hatchRitual: some View {
        GeometryReader { proxy in
            let eggWidth = min(proxy.size.width * 0.78, 330)
            let eggHeight = min(proxy.size.height * 0.53, 430)

            ZStack {
                RadialGradient(
                    colors: [
                        Color(hex: "F7C943").opacity(phaseIsCracking ? 0.34 : 0.16),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 12,
                    endRadius: eggWidth * 0.78
                )
                .scaleEffect(crackPulse ? 1.14 : 0.9)
                .opacity(crackPulse ? 1 : 0.62)

                VStack(spacing: 18) {
                    Spacer(minLength: 34)

                    VStack(spacing: 7) {
                        Text(phaseIsCracking ? "THE EGG IS OPENING" : "DRAW THE FIRST CRACK")
                            .pixelText(size: 15, color: Color(hex: "FFD24D"))
                            .multilineTextAlignment(.center)
                            .shadow(color: Color(hex: "FFD24D").opacity(0.65), radius: phaseIsCracking ? 12 : 3)

                        Text(nudge ? "DRAW A LINE ACROSS THE EGG" : "ONE STROKE  •  RELEASE TO HATCH")
                            .pixelText(size: 8, color: nudge ? Color(hex: "FF9E6B") : Color(hex: "E9D8B6"))
                            .opacity(phaseIsDrawing ? 1 : 0)
                    }

                    ZStack {
                        HatchEgg(glowing: phaseIsCracking)

                        HatchStroke(points: drawnPoints)
                        .stroke(
                            phaseIsCracking ? Color(hex: "FFD24D") : Color(hex: "FFF3C4"),
                            style: StrokeStyle(
                                lineWidth: phaseIsCracking ? 9 : 6,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .shadow(
                            color: phaseIsCracking ? Color(hex: "FFD24D") : Color.white,
                            radius: phaseIsCracking ? 16 : 5
                        )
                        .clipShape(HatchEggShape())

                        if phaseIsCracking {
                            CrackBranches(points: drawnPoints)
                                .stroke(
                                    Color(hex: "FFD24D"),
                                    style: StrokeStyle(lineWidth: 6, lineCap: .square, lineJoin: .miter)
                                )
                                .shadow(color: Color(hex: "FFD24D"), radius: 12)
                                .clipShape(HatchEggShape())
                                .transition(.opacity)
                        }
                    }
                    .frame(width: eggWidth, height: eggHeight)
                    .contentShape(HatchEggShape())
                    .gesture(drawingGesture(in: CGSize(width: eggWidth, height: eggHeight)))
                    .rotationEffect(.degrees(crackRotation))
                    .offset(x: crackOffset)
                    .scaleEffect(crackPulse ? 1.035 : 1)
                    .accessibilityLabel("Egg drawing surface")
                    .accessibilityHint("Draw one continuous crack and release to hatch")

                    Text(phase.eggCount == 10 ? "10 EGGS • ONE RITUAL" : "MAKE YOUR MARK")
                        .pixelText(size: 8, color: Color(hex: "C7A6F2"))
                        .opacity(phaseIsDrawing ? 1 : 0)

                    Spacer(minLength: 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .scaleEffect(ritualScale)
            .opacity(ritualOpacity)
        }
        .allowsHitTesting(phaseIsDrawing)
    }

    private var phaseIsDrawing: Bool {
        if case .drawing = phase { return true }
        return false
    }

    private var phaseIsCracking: Bool {
        if case .cracking = phase { return true }
        return false
    }

    private var crackRotation: Double {
        guard phaseIsCracking else { return 0 }
        return crackPulse ? 4.5 : -4.5
    }

    private var crackOffset: CGFloat {
        guard phaseIsCracking else { return 0 }
        return crackPulse ? 7 : -7
    }

    private func beginRitual(count: Int) {
        guard phase == .home else { return }
        drawnPoints = []
        strokeLength = 0
        ritualScale = 0.58
        ritualOpacity = 0
        crackPulse = false
        nudge = false
        phase = .zooming(count)

        withAnimation(.spring(response: 0.58, dampingFraction: 0.76)) {
            ritualScale = 1
            ritualOpacity = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(480))
            guard phase == .zooming(count) else { return }
            Haptics.support()
            withAnimation(.easeOut(duration: 0.2)) {
                phase = .drawing(count)
            }
        }
    }

    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard phaseIsDrawing, HatchEggShape.contains(value.location, in: size) else { return }
                if let last = drawnPoints.last {
                    let distance = hypot(value.location.x - last.x, value.location.y - last.y)
                    guard distance >= 2 else { return }
                    strokeLength += distance
                }
                drawnPoints.append(value.location)
            }
            .onEnded { _ in
                guard phaseIsDrawing else { return }
                guard strokeLength >= 32, drawnPoints.count >= 2 else {
                    Haptics.warning()
                    withAnimation(.easeOut(duration: 0.18)) {
                        drawnPoints = []
                        strokeLength = 0
                        nudge = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1300))
                        withAnimation(.easeOut(duration: 0.3)) { nudge = false }
                    }
                    return
                }
                completeRitualStroke()
            }
    }

    private func completeRitualStroke() {
        guard case let .drawing(count) = phase else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            phase = .cracking(count)
            crackPulse = true
        }
        AudioManager.shared.play(.hitSkill, volume: 0.72)
        Haptics.skill()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard phase == .cracking(count) else { return }
            withAnimation(.linear(duration: 0.08).repeatCount(5, autoreverses: true)) {
                crackPulse.toggle()
            }
            AudioManager.shared.play(.hitBasic, volume: 0.82)
            Haptics.hit()

            try? await Task.sleep(for: .milliseconds(520))
            guard phase == .cracking(count) else { return }
            AudioManager.shared.play(.crit, volume: 0.9)
            Haptics.crit()
            withAnimation(.easeIn(duration: 0.18)) {
                flashOpacity = 1
            }

            try? await Task.sleep(for: .milliseconds(190))
            guard phase == .cracking(count) else { return }
            resolveHatch(count: count)
            AudioManager.shared.play(.reward)
            Haptics.success()

            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.48)) {
                flashOpacity = 0
            }
        }
    }

    private func resolveHatch(count: Int) {
        let results = egg.hatch(count)
        guard !results.isEmpty else {
            resetRitual()
            return
        }
        if count == 1 {
            single = results[0]
            shareImage = BioBudShareCard.render(hero: results[0].hero)
        } else {
            multi = results
        }
        resetRitual()
    }

    private func resetRitual() {
        phase = .home
        drawnPoints = []
        strokeLength = 0
        ritualScale = 0.58
        ritualOpacity = 0
        crackPulse = false
        nudge = false
    }

    // MARK: Single hatch
    @ViewBuilder
    private func singleReveal(_ result: HatchResult) -> some View {
        if result.isNew {
            NewBioBudReveal(hero: result.hero, collected: true) {
                if let shareImage {
                    BioBudShareButton(image: shareImage, hero: result.hero)
                }
                Button { single = nil } label: {
                    RevealActionLabel(title: L("CONTINUE"), color: Color(hex: "4A8A3C"))
                }
                .buttonStyle(.plain)
            }
        } else {
            ZStack {
                Color.black.opacity(0.84).ignoresSafeArea()
                BioBudBurst(rarity: result.hero.rarity)
                VStack(spacing: 12) {
                    SpriteView(asset: result.hero.asset, size: 150)
                    Text(L(result.hero.name).uppercased())
                        .pixelText(size: 16, color: result.hero.rarity.color)
                    Text("ALREADY IN YOUR COLLECTION")
                        .pixelText(size: 8, color: Color(hex: "E9D8B6"))
                    Text("✦ +\(result.shardsGained) SHARDS")
                        .pixelText(size: 12, color: Color(hex: "C7A6F2"))
                    Button { single = nil } label: {
                        RevealActionLabel(title: L("CONTINUE"), color: Color(hex: "4A8A3C"))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 210)
                    .padding(.top, 8)
                }
            }
        }
    }

}

/// Sequential ×10 reveal — one biobud at a time, with an anticipation flash
/// (tinted to the card's rarity, held longer + a crit sting for rare and up)
/// before each pops in. Ends on the full grid summary. Tap to advance; tapping
/// during a flash skips straight to the card so impatient pulls stay snappy.
private struct MultiRevealSequence: View {
    let results: [HatchResult]
    let onClose: () -> Void

    @State private var index = 0
    @State private var showCard = false
    @State private var flash = false
    @State private var done = false

    private var current: HatchResult { results[min(index, results.count - 1)] }

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()

            if done {
                summaryGrid
            } else {
                RadialGradient(
                    colors: [current.hero.rarity.color.opacity(flash ? flashPeak : 0), .clear],
                    center: .center, startRadius: 8, endRadius: 380
                )
                .ignoresSafeArea()

                if showCard && current.hero.rarity >= .rare {
                    RarityBeams(rarity: current.hero.rarity)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                VStack(spacing: 14) {
                    Text("\(index + 1) / \(results.count)")
                        .pixelText(size: 9, color: Color(hex: "E9D8B6"))
                        .opacity(0.8)

                    Spacer()

                    if showCard {
                        VStack(spacing: 10) {
                            BioBudBurst(rarity: current.hero.rarity)
                                .frame(height: 0)
                            SpriteView(asset: current.hero.asset, size: current.hero.rarity == .legendary ? 178 : 150)
                            if current.hero.rarity >= .rare {
                                RarityBanner(rarity: current.hero.rarity)
                            } else {
                                Text(current.hero.rarity.label.uppercased())
                                    .pixelText(size: 10, color: current.hero.rarity.color)
                            }
                            Text(L(current.hero.name).uppercased())
                                .pixelText(size: current.hero.rarity == .legendary ? 19 : 16, color: Color(hex: "FFF3C4"))
                            Text(current.isNew ? "NEW" : "✦ +\(current.shardsGained) SHARDS")
                                .pixelText(size: 9, color: current.isNew ? Color(hex: "9CD67D") : Color(hex: "C7A6F2"))
                        }
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }

                    Spacer()

                    Text(index + 1 < results.count ? "TAP TO CONTINUE" : "TAP TO SEE ALL")
                        .pixelText(size: 8, color: Color(hex: "E9D8B6"))
                        .opacity(showCard ? 0.85 : 0)
                        .padding(.bottom, 40)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .onAppear { present() }
    }

    private var summaryGrid: some View {
        VStack(spacing: 14) {
            Text("10× HATCH")
                .pixelText(size: 18, color: Color(hex: "F7C943"))
                .padding(.top, 44)
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(results) { r in
                        VStack(spacing: 3) {
                            SpriteView(asset: r.hero.asset, size: 44)
                            Text(r.isNew ? "NEW" : "+\(r.shardsGained)")
                                .pixelText(size: 7, color: r.isNew ? Color(hex: "9CD67D") : Color(hex: "C7A6F2"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(hex: "F4E6C0").opacity(0.10))
                        .overlay(Rectangle().stroke(r.hero.rarity.color, lineWidth: 2))
                    }
                }
                .padding(.horizontal, 16)
            }
            Button { onClose() } label: {
                RevealActionLabel(title: L("CONTINUE"), color: Color(hex: "4A8A3C"))
            }
            .buttonStyle(.plain)
            .frame(width: 220)
            .padding(.bottom, 32)
        }
    }

    // The brighter the flash and the longer the anticipation hold, the rarer the
    // pull — so a legendary lands with an unmistakably bigger beat than a common.
    private var flashPeak: Double {
        switch current.hero.rarity {
        case .legendary: 0.9
        case .epic: 0.72
        default: 0.55
        }
    }

    private func holdMillis(_ rarity: Rarity) -> Int {
        switch rarity {
        case .legendary: 900
        case .epic: 620
        case .rare: 460
        case .common: 210
        }
    }

    private func present() {
        let r = current
        let isRare = r.hero.rarity >= .rare
        showCard = false
        withAnimation(.easeOut(duration: 0.18)) { flash = true }
        if isRare {
            AudioManager.shared.play(.crit, volume: r.hero.rarity == .legendary ? 1 : 0.85)
            Haptics.crit()
        } else {
            Haptics.tap()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(holdMillis(r.hero.rarity)))
            guard !showCard else { return }
            reveal(r)
        }
    }

    private func reveal(_ r: HatchResult) {
        let spring: Animation = r.hero.rarity == .legendary
            ? .spring(response: 0.6, dampingFraction: 0.55)
            : .spring(response: 0.42, dampingFraction: 0.7)
        withAnimation(spring) { showCard = true }
        withAnimation(.easeOut(duration: 0.5)) { flash = false }
        AudioManager.shared.play(r.isNew ? .reward : .uiTap)
        if r.isNew { Haptics.success() }
        if r.hero.rarity == .legendary { Haptics.crit() }
    }

    private func advance() {
        if !showCard {
            reveal(current)        // impatient tap — show the card now
            return
        }
        if index + 1 < results.count {
            index += 1
            present()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { done = true }
        }
    }
}

private struct HatchEggShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.025))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.025, y: rect.height * 0.65),
            control1: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.height * 0.12),
            control2: CGPoint(x: rect.maxX + rect.width * 0.02, y: rect.height * 0.43)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.02),
            control1: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.height * 0.91),
            control2: CGPoint(x: rect.width * 0.73, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.025, y: rect.height * 0.65),
            control1: CGPoint(x: rect.width * 0.27, y: rect.maxY),
            control2: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.height * 0.91)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.025),
            control1: CGPoint(x: rect.minX - rect.width * 0.02, y: rect.height * 0.43),
            control2: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.height * 0.12)
        )
        path.closeSubpath()
        return path
    }

    static func contains(_ point: CGPoint, in size: CGSize) -> Bool {
        HatchEggShape().path(in: CGRect(origin: .zero, size: size)).contains(point)
    }
}

private struct HatchEgg: View {
    var glowing = false

    var body: some View {
        HatchEggShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "FFF5CE"),
                        Color(hex: "F4D98A"),
                        Color(hex: "C8873F")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                HatchEggShape()
                    .stroke(Color(hex: "5A3017"), lineWidth: 7)
            }
            .overlay {
                GeometryReader { proxy in
                    ZStack {
                        Ellipse()
                            .fill(Color.white.opacity(0.42))
                            .frame(width: proxy.size.width * 0.22, height: proxy.size.height * 0.38)
                            .rotationEffect(.degrees(22))
                            .position(x: proxy.size.width * 0.31, y: proxy.size.height * 0.34)
                        Circle()
                            .fill(Color(hex: "D99A4E").opacity(0.48))
                            .frame(width: proxy.size.width * 0.11)
                            .position(x: proxy.size.width * 0.66, y: proxy.size.height * 0.34)
                        Circle()
                            .fill(Color(hex: "B96C32").opacity(0.32))
                            .frame(width: proxy.size.width * 0.075)
                            .position(x: proxy.size.width * 0.38, y: proxy.size.height * 0.7)
                    }
                    .clipShape(HatchEggShape())
                }
            }
            .shadow(color: Color(hex: "FFD24D").opacity(glowing ? 0.9 : 0.22), radius: glowing ? 30 : 10)
    }
}

private struct HatchStroke: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else { return Path() }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

private struct CrackBranches: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard points.count >= 4 else { return Path() }
        var path = Path()
        let indices = [points.count / 3, points.count / 2, points.count * 2 / 3]
        for (branch, index) in indices.enumerated() {
            let origin = points[min(index, points.count - 1)]
            let direction: CGFloat = branch.isMultiple(of: 2) ? -1 : 1
            path.move(to: origin)
            path.addLine(to: CGPoint(x: origin.x + 24 * direction, y: origin.y - 18))
            path.addLine(to: CGPoint(x: origin.x + 39 * direction, y: origin.y - 9))
        }
        return path
    }
}
