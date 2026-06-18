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
