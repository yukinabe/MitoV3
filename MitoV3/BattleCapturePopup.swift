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
            withAnimation(.spring(response: 0.62, dampingFraction: 0.58)) {
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
    @Binding var isPresented: Bool
    @ObservedObject private var egg = EggStore.shared
    @State private var single: HatchResult?
    @State private var multi: [HatchResult]?
    @State private var eggWobble = false

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
                multiResults(multi)
            } else {
                hatchHome
            }
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
            Text("🥚")
                .font(.system(size: 92))
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
                    if let r = egg.hatch(1).first {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { single = r }
                    }
                }
                hatchButton("HATCH ×10", enabled: egg.canHatchTen) {
                    let r = egg.hatch(10)
                    if !r.isEmpty {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { multi = r }
                    }
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
            AudioManager.shared.play(.reward)
            Haptics.success()
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

    // MARK: Single hatch
    @ViewBuilder
    private func singleReveal(_ result: HatchResult) -> some View {
        if result.isNew {
            NewBioBudReveal(hero: result.hero, collected: true) {
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

    // MARK: 10× hatch
    private func multiResults(_ results: [HatchResult]) -> some View {
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
            Button { multi = nil } label: {
                RevealActionLabel(title: L("CONTINUE"), color: Color(hex: "4A8A3C"))
            }
            .buttonStyle(.plain)
            .frame(width: 220)
            .padding(.bottom, 32)
        }
    }
}
