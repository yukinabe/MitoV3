//  BattleCapturePopup.swift
//  Extracted from BattleView.swift (behavior-preserving refactor).

import SwiftUI

// MARK: - Capture popup

/// Offered after defeating a capturable wild creature. Catch it to add it to your
/// collection (usable as a team member) or let it go.
struct CapturePopup: View {
    let creature: Hero
    let onCapture: () -> Void
    let onRelease: () -> Void

    @State private var pop: CGFloat = 0.6

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(Lf("A WILD %@ APPEARED!", L(creature.name).uppercased()))
                    .pixelText(size: 12, color: Color(hex: "FFD24D"))
                    .multilineTextAlignment(.center)

                SpriteView(asset: creature.asset, size: 92)
                    .padding(10)
                    .background(creature.color.opacity(0.25))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                Text(L(creature.role).uppercased() + " · LV \(creature.level)")
                    .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                Text(L(creature.lore))
                    .font(.custom(MitoFont.regular, size: 14))
                    .foregroundStyle(Color(hex: "E9D8B6"))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    Button(action: onRelease) {
                        Text(L("LET GO"))
                            .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)

                    Button(action: onCapture) {
                        Text(L("✦ CAPTURE"))
                            .pixelText(size: 13, color: Color(hex: "1A130A"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color(hex: "FFD24D"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(width: 290)
            .background(Color(hex: "2A1B0E"))
            .overlay(Rectangle().stroke(Color(hex: "FFD24D"), lineWidth: 4))
            .scaleEffect(pop)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { pop = 1 }
            }
        }
    }
}

// MARK: - Recruit popup

/// Shown after beating a campaign boss who is a recruitable base hero. Unlike a
/// wild capture there's no "let go" — defeating the boss recruits them outright.
struct RecruitPopup: View {
    let hero: Hero
    let onJoin: () -> Void

    @State private var pop: CGFloat = 0.6

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(Lf("%@ JOINED YOUR TEAM!", L(hero.name).uppercased()))
                    .pixelText(size: 12, color: Color(hex: "FFD24D"))
                    .multilineTextAlignment(.center)

                SpriteView(asset: hero.asset, size: 96)
                    .padding(10)
                    .background(hero.color.opacity(0.25))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                Text(L(hero.role).uppercased() + " · LV \(hero.level)")
                    .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                Text(L(hero.lore))
                    .font(.custom(MitoFont.regular, size: 14))
                    .foregroundStyle(Color(hex: "E9D8B6"))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Button(action: onJoin) {
                    Text(L("✦ ADD TO ROSTER"))
                        .pixelText(size: 13, color: Color(hex: "1A130A"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(hex: "FFD24D"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(width: 290)
            .background(Color(hex: "2A1B0E"))
            .overlay(Rectangle().stroke(Color(hex: "FFD24D"), lineWidth: 4))
            .scaleEffect(pop)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { pop = 1 }
            }
        }
    }
}
