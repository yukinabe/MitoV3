//  BattleCombatView.swift
//  The live battle/combat view + damage numbers + ability bar button.
//  Extracted from BattleView.swift (behavior-preserving refactor).

import SwiftUI

/// One floating damage number. Size scales with magnitude; crits are gold.
struct FloatingDamage: Identifiable {
    let id = UUID()
    let amount: Int
    let isCrit: Bool
    let xJitter: CGFloat
}

private struct CombatFeedback: Identifiable, Equatable {
    let id = UUID()
    let grant: BuffGrant
    let target: Target

    enum Target: Equatable {
        case ally(Int)
        case enemy
    }

    var text: String {
        switch grant.kind {
        case .attack: "+\(Int(grant.magnitude * 100))% ATK"
        case .defense: "GUARD"
        case .speed: "+\(Int(grant.magnitude)) SPD"
        case .shield: "+\(Int(grant.magnitude)) SHIELD"
        case .heal: "+\(Int(grant.magnitude)) HP"
        case .ultEnergy: "+\(Int(grant.magnitude)) ENERGY"
        case .mark: "MARK +\(Int(grant.magnitude * 100))%"
        }
    }

    var color: Color {
        switch grant.kind {
        case .attack: Color(hex: "FFD24D")
        case .defense: Color(hex: "7EB9F0")
        case .speed: Color(hex: "8FE3C0")
        case .shield: Color(hex: "BFD8FF")
        case .heal: Color(hex: "B8F58A")
        case .ultEnergy: Color(hex: "FFF1A8")
        case .mark: Color(hex: "F2A65A")
        }
    }
}

/// Self-animating damage number: pops in with an overshoot, then rises and fades.
private struct DamageNumberView: View {
    let damage: FloatingDamage
    @State private var rise: CGFloat = 0
    @State private var fade: Double = 1
    @State private var scale: CGFloat = 0.3

    private var fontSize: CGFloat {
        // Bigger hits read bigger; crits get an extra bump.
        let base = 18 + min(CGFloat(damage.amount) * 0.28, 20)
        return damage.isCrit ? base + 8 : base
    }

    var body: some View {
        Text("-\(damage.amount)")
            .font(.custom(MitoFont.bold, size: fontSize))
            .foregroundStyle(damage.isCrit ? Color(hex: "FFD24D") : Color(hex: "FFF1C8"))
            .shadow(color: .black.opacity(0.85), radius: 0, x: 2, y: 2)
            .overlay(
                damage.isCrit
                    ? Text("-\(damage.amount)")
                        .font(.custom(MitoFont.bold, size: fontSize))
                        .foregroundStyle(Color.white.opacity(0.0))
                        .shadow(color: Color(hex: "FF8A3D").opacity(0.9), radius: 6)
                    : nil
            )
            .scaleEffect(scale)
            .offset(x: damage.xJitter, y: -22 + rise)
            .opacity(fade)
            .onAppear {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.45)) {
                    scale = damage.isCrit ? 1.35 : 1.0
                }
                withAnimation(.easeOut(duration: 1.0)) {
                    rise = damage.isCrit ? -84 : -64
                    fade = 0
                }
            }
    }
}

private struct CombatFeedbackView: View {
    let feedback: CombatFeedback

    var body: some View {
        HStack(spacing: 3) {
            Text(feedback.grant.kind.icon)
                .pixelText(size: 8, color: Color(hex: "1A130A"))
            Text(feedback.text)
                .pixelText(size: 7, color: Color(hex: "1A130A"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(feedback.color)
        .overlay(Rectangle().stroke(Color.white.opacity(0.75), lineWidth: 1))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        .shadow(color: feedback.color.opacity(0.8), radius: 8)
    }
}

private struct LegendaryDirectedStrikeView: View {
    let ability: BattleAbility
    let start: CGPoint
    let end: CGPoint
    let progress: CGFloat

    private var current: CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }

    var body: some View {
        ZStack {
            switch ability.animationKey {
            case "t4-genome-injection":
                DnaTether(start: start, end: current, color: Color(hex: "4FDFF2"), accent: Color(hex: "B8FF5B"))
                PixelSpark(color: Color(hex: "B8FF5B"))
                    .scaleEffect(0.68 + progress * 0.35)
                    .position(current)
            case "t4-tail-pierce":
                PiercingLine(start: start, end: current, color: Color(hex: "4FDFF2"))
            case "t4-lytic-burst":
                DnaTether(start: start, end: current, color: Color(hex: "8DF7FF"), accent: Color(hex: "B8FF5B"))
                ExpandingHexPulse(center: current, color: Color(hex: "8DF7FF"), progress: progress)
            case "prion-misfold-flick":
                MisfoldRibbon(start: start, end: current, color: Color(hex: "C78CFF"), progress: progress, intense: false)
            case "prion-chain-conformation":
                MisfoldRibbon(start: start, end: current, color: Color(hex: "B56BFF"), progress: progress, intense: true)
                MarkEffect(color: Color(hex: "B56BFF"))
                    .scaleEffect(0.28 + progress * 0.2)
                    .opacity(Double(progress))
                    .position(current)
            case "prion-cascade":
                MisfoldRibbon(start: start, end: current, color: Color(hex: "E6B7FF"), progress: progress, intense: true)
                CascadePulse(center: current, color: Color(hex: "E6B7FF"), progress: progress)
            default:
                PiercingLine(start: start, end: current, color: ability.color)
            }
        }
    }
}

private struct LegendaryImpactEffectView: View {
    let ability: BattleAbility

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                switch ability.animationKey {
                case "t4-genome-injection":
                    ExpandingHexPulse(center: center, color: Color(hex: "B8FF5B"), progress: 0.95)
                    DnaImpactCore(color: Color(hex: "4FDFF2"), accent: Color(hex: "B8FF5B"))
                        .position(center)
                case "t4-tail-pierce":
                    PiercingImpact(color: Color(hex: "4FDFF2"))
                        .position(center)
                case "t4-lytic-burst":
                    SpriteSheetAbilityEffect(asset: ability.animationKey, frameCount: 8, frameSize: CGSize(width: 200, height: 128))
                case "prion-misfold-flick":
                    CascadePulse(center: center, color: Color(hex: "C78CFF"), progress: 0.72)
                case "prion-chain-conformation":
                    MarkEffect(color: Color(hex: "B56BFF"))
                        .scaleEffect(0.76)
                        .position(center)
                    CascadePulse(center: center, color: Color(hex: "B56BFF"), progress: 0.82)
                case "prion-cascade":
                    SpriteSheetAbilityEffect(asset: ability.animationKey, frameCount: 8, frameSize: CGSize(width: 200, height: 128))
                default:
                    BurstEffect(color: ability.color, intense: ability.kind == .ultimate)
                        .position(center)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .blendMode(.plusLighter)
    }
}

private struct DnaImpactCore: View {
    let color: Color
    let accent: Color

    var body: some View {
        ZStack {
            Capsule()
                .fill(color.opacity(0.82))
                .frame(width: 52, height: 12)
            Capsule()
                .fill(accent.opacity(0.86))
                .frame(width: 52, height: 6)
                .rotationEffect(.degrees(35))
            Capsule()
                .fill(Color.white.opacity(0.72))
                .frame(width: 42, height: 3)
                .rotationEffect(.degrees(-35))
            PixelSpark(color: accent)
                .scaleEffect(0.56)
                .offset(x: 24)
        }
    }
}

private struct PiercingImpact: View {
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? color : Color.white.opacity(0.82))
                    .frame(width: 7, height: 58)
                    .offset(y: -36)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
            Circle()
                .fill(color.opacity(0.62))
                .frame(width: 44, height: 44)
            Circle()
                .fill(Color.white.opacity(0.74))
                .frame(width: 17, height: 17)
        }
    }
}

private struct BuffTransferLink: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color
    let opacity: Double

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: start)
                let mid = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 24)
                path.addQuadCurve(to: end, control: mid)
            }
            .stroke(color.opacity(opacity * 0.72), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 4]))
            PixelSpark(color: color)
                .scaleEffect(0.38)
                .position(end)
                .opacity(opacity)
        }
        .blendMode(.plusLighter)
    }
}

private struct DebuffTargetPulse: View {
    let color: Color
    let opacity: Double

    var body: some View {
        ZStack {
            MarkEffect(color: color)
                .scaleEffect(0.72)
            Circle()
                .stroke(color.opacity(0.85), lineWidth: 5)
                .frame(width: 112, height: 112)
            Circle()
                .stroke(Color.white.opacity(0.55), lineWidth: 2)
                .frame(width: 82, height: 82)
        }
        .opacity(opacity)
        .blendMode(.plusLighter)
    }
}

private struct PiercingLine: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: 3, lineCap: .square))
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(color.opacity(0.88), style: StrokeStyle(lineWidth: 8, lineCap: .square))
            .blendMode(.plusLighter)
        }
    }
}

private struct DnaTether: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color
    let accent: Color

    var body: some View {
        ZStack {
            Path { path in
                let points = wavePoints(phase: 0)
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            .stroke(color.opacity(0.92), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            Path { path in
                let points = wavePoints(phase: .pi)
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            .stroke(accent.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            ForEach(0..<7, id: \.self) { index in
                let pair = rung(index)
                Path { path in
                    path.move(to: pair.0)
                    path.addLine(to: pair.1)
                }
                .stroke(Color.white.opacity(0.72), style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
            }
        }
    }

    private func wavePoints(phase: CGFloat) -> [CGPoint] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let nx = -dy / length
        let ny = dx / length
        return (0..<18).map { idx in
            let t = CGFloat(idx) / 17
            let amp = sin(t * .pi * 5 + phase) * 8
            return CGPoint(x: start.x + dx * t + nx * amp, y: start.y + dy * t + ny * amp)
        }
    }

    private func rung(_ index: Int) -> (CGPoint, CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let nx = -dy / length
        let ny = dx / length
        let t = CGFloat(index + 1) / 8
        let amp = sin(t * .pi * 5) * 8
        let center = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
        return (
            CGPoint(x: center.x + nx * amp, y: center.y + ny * amp),
            CGPoint(x: center.x - nx * amp, y: center.y - ny * amp)
        )
    }
}

private struct MisfoldRibbon: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color
    let progress: CGFloat
    let intense: Bool

    var body: some View {
        ZStack {
            ForEach(0..<(intense ? 3 : 2), id: \.self) { strand in
                Path { path in
                    let points = ribbonPoints(strand: strand)
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(strand == 0 ? Color.white.opacity(0.82) : color.opacity(0.88),
                        style: StrokeStyle(lineWidth: strand == 0 ? 2 : 5, lineCap: .round, lineJoin: .round))
                .blendMode(.plusLighter)
            }
        }
    }

    private func ribbonPoints(strand: Int) -> [CGPoint] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let nx = -dy / length
        let ny = dx / length
        return (0..<10).map { idx in
            let t = CGFloat(idx) / 9
            let wobble = sin(t * .pi * CGFloat(intense ? 5 : 3) + CGFloat(strand) * 1.8 + progress * 2) * CGFloat(intense ? 13 : 8)
            return CGPoint(x: start.x + dx * t + nx * wobble, y: start.y + dy * t + ny * wobble)
        }
    }
}

private struct ExpandingHexPulse: View {
    let center: CGPoint
    let color: Color
    let progress: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                HexagonShape()
                    .stroke(index == 0 ? color.opacity(0.95) : Color.white.opacity(0.7), lineWidth: index == 0 ? 4 : 2)
                    .frame(width: 32 + progress * CGFloat(72 + index * 20), height: 32 + progress * CGFloat(72 + index * 20))
                    .position(center)
            }
        }
    }
}

private struct CascadePulse: View {
    let center: CGPoint
    let color: Color
    let progress: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Ellipse()
                    .stroke(index == 0 ? color.opacity(0.95) : Color.white.opacity(0.62), lineWidth: index == 0 ? 5 : 2)
                    .frame(width: 34 + progress * CGFloat(86 + index * 26), height: 18 + progress * CGFloat(50 + index * 14))
                    .rotationEffect(.degrees(Double(index) * 18))
                    .position(center)
            }
        }
    }
}

private struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for index in 0..<6 {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 3
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

struct BattleCombatView: View {
    let mode: BattleMode
    let mobHP: Int
    let heroHP: [String: Int]
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
    let visualAbility: BattleAbility?
    let visualEffectToken: Int
    let attackToken: Int
    let lastDamage: Int
    let choosingAbility: Bool
    let finishingWithoutCards: Bool
    let activeHeroAbilities: [BattleAbility]
    let activeHeroUltCharge: Int
    let enemyMaxHP: Int
    let combatBuffs: CombatBuffs
    let upcomingTurns: [Int]
    let skillCooldownTurns: Int
    let wave: Int
    /// When set (campaign recruit stages), the enemy is this hero instead of the
    /// generic wild boss — so the boss you fight is the character you'll recruit.
    var bossOverrideID: String? = nil
    let stageLabel: String
    let autoMode: Bool
    let answerMode: AnswerMode
    let answerCardID: UUID?
    let mcOptions: [String]
    let onReveal: () -> Void
    let onDone: () -> Void
    let onGrade: (BattleRating) -> Void
    let onAbility: (BattleAbility) -> Void
    let onToggleAuto: () -> Void
    let gradeTyped: (String, TypingSignals) async -> (BattleRating, String?)

    // Combat juice + pause state.
    @Environment(\.scenePhase) private var scenePhase
    @State private var enemyShakeX: CGFloat = 0
    @State private var enemyFlash: Double = 0
    @State private var enemyHitScale: CGFloat = 1
    @State private var lungeY: CGFloat = 0
    @State private var displayedMobHP = 0
    @State private var displayedMobHPChip = 0          // lagging "chip" ghost bar
    @State private var floatingDamages: [FloatingDamage] = []
    @State private var sceneShake: CGSize = .zero      // real screen shake
    @State private var enemyDying = false
    @State private var enemyDeathScale: CGFloat = 1
    @State private var enemyDeathSpin: Double = 0
    @State private var enemyEnterY: CGFloat = 0       // next enemy drops/fades in
    @State private var enemyEnterOpacity: Double = 1
    @State private var enemyBreath: CGFloat = 1        // idle breathing
    @State private var effectAbility: BattleAbility?
    @State private var showAbilityEffect = false
    @State private var abilityEffectScale: CGFloat = 0.5
    @State private var abilityEffectOpacity: Double = 0
    @State private var abilityEffectRotation: Double = 0
    @State private var teamBuffHopY: CGFloat = 0
    @State private var partyHopY: CGFloat = 0      // clean one-shot team-buff hop
    @State private var activeBob: CGFloat = 0       // gentle idle bob on the active hero
    @State private var animatedPartyHopToken = 0
    // Directed ability strike: travels from the active hero up to the enemy.
    @State private var projectileAbility: BattleAbility?
    @State private var projectileProgress: CGFloat = 0
    @State private var projectileFromIndex = 0
    @State private var impactBurstAbility: BattleAbility?
    @State private var impactBurstToken = 0
    @State private var combatFeedback: [CombatFeedback] = []
    @State private var feedbackRise: CGFloat = 0
    @State private var feedbackOpacity: Double = 0
    @State private var displayedVisualAbility: BattleAbility?
    @State private var displayedVisualToken = 0
    @State private var animatedAttackToken = 0
    @State private var paused = false
    @AppStorage("audio.master") private var volume: Double = 0.8
    @AppStorage("audio.music") private var musicOn: Bool = true

    private var currentWildEnemyID: String {
        if let bossOverrideID { return bossOverrideID }
        if mode == .endless {
            return (wave % 4 == 0) ? "wild-cytocrawler" : "wild-mutagem"
        } else {
            return "wild-spikevyrus"
        }
    }

    private var currentEnemy: Hero? { DataSet.anyHero(id: currentWildEnemyID) }

    private var enemyName: String { L(currentEnemy?.name ?? (mode == .endless ? "Mutagem" : "Spikevyrus")) }

    private var enemyRarity: String? {
        if bossOverrideID != nil { return "BOSS" }
        return mode == .endless ? "EPIC" : nil
    }

    /// Shared 3-character active party (same in both modes).
    private var team: [Hero] { BattleRules.partyHeroes }
    private var activeVisualAbility: BattleAbility? {
        displayedVisualAbility ?? visualAbility ?? (lastAbility?.kind == .basic ? nil : lastAbility)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("dungeon-bg")
                    .screenBackground()
                    .scaleEffect(1.05) // overscan so screen-shake never reveals edges
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

                    Group {
                        if finishingWithoutCards {
                            finalStandPanel
                        } else {
                            BattleFlashcardPanel(
                                mode: mode,
                                currentCard: currentCard,
                                showingAnswer: showingAnswer,
                                questionText: questionText,
                                answerText: answerText,
                                cardTag: cardTag,
                                // In choice/type-in modes the answer is revealed by
                                // answering, so hide the manual "SHOW ANSWER" button.
                                allowManualReveal: answerMode == .classic && !choosingAbility,
                                onReveal: onReveal
                            )
                        }
                    }
                    .padding(.horizontal, 12)

                    gradeRow
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 82)

                    Spacer(minLength: 0)
                }

                // 1) The strike flies from the casting hero up toward the enemy.
                if let pa = projectileAbility {
                    let start = heroScreenPos(index: projectileFromIndex, in: proxy.size)
                    let end = enemyScreenPos(in: proxy.size)
                    if isLegendaryDirectedAbility(pa) {
                        LegendaryDirectedStrikeView(ability: pa, start: start, end: end, progress: projectileProgress)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .allowsHitTesting(false)
                            .zIndex(7)
                    } else {
                        let pos = CGPoint(x: start.x + (end.x - start.x) * projectileProgress,
                                          y: start.y + (end.y - start.y) * projectileProgress)
                        let travelScale = 0.35 + 0.45 * projectileProgress
                        BattleAbilityEffectView(ability: pa, scale: travelScale, opacity: 1,
                                                rotation: Double(projectileProgress) * 120)
                            .frame(width: effectSize(for: pa).width * 0.72,
                                   height: effectSize(for: pa).height * 0.72)
                            .position(pos)
                            .allowsHitTesting(false)
                            .zIndex(7)
                    }
                }

                // 2) On arrival it bursts on the enemy (every damaging ability, so
                //    buff-and-attack ultimates still land a visible hit).
                if let burst = impactBurstAbility {
                    if isLegendaryDirectedAbility(burst) {
                        LegendaryImpactEffectView(ability: burst)
                            .id(impactBurstToken)
                            .frame(width: effectSize(for: burst).width, height: effectSize(for: burst).height)
                            .position(enemyScreenPos(in: proxy.size))
                            .allowsHitTesting(false)
                            .zIndex(8)
                    } else {
                        BattleAbilityEffectView(ability: burst,
                                                scale: burst.kind == .ultimate ? 1.3 : 1.05,
                                                opacity: 1, rotation: 0)
                            .id(impactBurstToken)
                            .frame(width: effectSize(for: burst).width, height: effectSize(for: burst).height)
                            .position(enemyScreenPos(in: proxy.size))
                            .allowsHitTesting(false)
                            .zIndex(8)
                    }
                }

                ForEach(combatFeedback) { feedback in
                    switch feedback.target {
                    case .ally(let index):
                        BuffTransferLink(
                            start: heroScreenPos(index: lastActorIndex, in: proxy.size),
                            end: heroScreenPos(index: index, in: proxy.size),
                            color: feedback.color,
                            opacity: feedbackOpacity
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                        .zIndex(8.5)
                    case .enemy:
                        DebuffTargetPulse(color: feedback.color, opacity: feedbackOpacity)
                            .position(enemyScreenPos(in: proxy.size))
                            .allowsHitTesting(false)
                            .zIndex(8.5)
                    }
                }

                ForEach(combatFeedback) { feedback in
                    CombatFeedbackView(feedback: feedback)
                        .position(feedbackPosition(feedback.target, in: proxy.size))
                        .offset(y: feedbackRise)
                        .opacity(feedbackOpacity)
                        .allowsHitTesting(false)
                        .zIndex(9)
                }

                // Turn-order timeline (who acts next), Honkai-style, left edge.
                turnOrderStrip
                    .position(x: 30, y: proxy.size.height * (mode == .endless ? 0.30 : 0.27))
                    .zIndex(6)

                if paused {
                    pauseOverlay
                }
            }
            .offset(sceneShake)
            .onAppear {
                displayedMobHP = mobHP
                displayedMobHPChip = mobHP
                startIdleBreathing()
                Haptics.warm()
                AudioManager.shared.startMusic(.battle)
                syncVisualAbilityIfNeeded()
                runHitAnimationIfNeeded()
            }
            .onDisappear {
                // Leaving combat returns to the calmer home/menu loop.
                AudioManager.shared.startMusic(.home)
            }
            .task(id: attackToken) {
                syncVisualAbilityIfNeeded()
                runHitAnimationIfNeeded()
            }
            .task(id: lastAbility?.id) {
                syncLastAbilityEffect()
            }
            .onChange(of: visualEffectToken) { _, _ in syncVisualAbilityIfNeeded() }
            .onChange(of: lastAbility?.id) { _, _ in syncVisualAbilityIfNeeded(force: true) }
            .onChange(of: attackToken) { _, _ in
                syncVisualAbilityIfNeeded()
                runHitAnimationIfNeeded()
            }
            .onChange(of: wave) { _, _ in
                guard mode == .endless, mobHP > 0 else { return }
                displayedMobHP = mobHP
                displayedMobHPChip = mobHP
                playEnemyEnter()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { paused = true }
            }
        }
    }

    /// One satisfying hit: enemy flash + recoil shake + scale punch, attacker
    /// lunge, a floating damage number, and a quick screen shake.
    /// Travel time of the lunge before it "connects" with the enemy.
    private let impactDelay: TimeInterval = 0.22

    private func isPartyAuraAbility(_ ability: BattleAbility) -> Bool {
        Self.partyAuraAnimationKeys.contains(ability.animationKey)
    }

    private func isLegendaryDirectedAbility(_ ability: BattleAbility) -> Bool {
        Self.legendaryDirectedAnimationKeys.contains(ability.animationKey)
    }

    private func effectSize(for ability: BattleAbility) -> CGSize {
        if isPartyAuraAbility(ability) {
            return CGSize(width: 250, height: 160)
        }
        if Self.spriteSheetAnimationKeys.contains(ability.animationKey) {
            return ability.kind == .ultimate ? CGSize(width: 300, height: 192) : CGSize(width: 240, height: 154)
        }
        return ability.kind == .ultimate ? CGSize(width: 250, height: 250) : CGSize(width: 180, height: 180)
    }

    private static let spriteSheetAnimationKeys: Set<String> = [
        "mito-cristae-surge",
        "mito-powerhouse-burst",
        "cloro-sugar-rush",
        "cloro-photosynthesis-bloom",
        "astro-synapse-buffer",
        "astro-glial-network",
        "dendri-present-antigen",
        "dendri-immune-rally",
        "neuro-myelin-guard",
        "neuro-synaptic-overload",
        "bcell-affinity-shield",
        "bcell-memory-response",
        "prion-misfold-flick",
        "prion-chain-conformation",
        "prion-cascade",
        "t4-tail-pierce",
        "t4-genome-injection",
        "t4-lytic-burst"
    ]

    private static let partyAuraAnimationKeys: Set<String> = [
        "mito-cristae-surge",
        "mito-powerhouse-burst",
        "astro-synapse-buffer",
        "astro-glial-network",
        "dendri-immune-rally",
        "neuro-myelin-guard",
        "bcell-affinity-shield",
        "bcell-memory-response"
    ]

    private static let legendaryDirectedAnimationKeys: Set<String> = [
        "prion-misfold-flick",
        "prion-chain-conformation",
        "prion-cascade",
        "t4-tail-pierce",
        "t4-genome-injection",
        "t4-lytic-burst"
    ]

    private func runHitAnimationIfNeeded() {
        guard attackToken != animatedAttackToken else { return }
        animatedAttackToken = attackToken
        runHitAnimation()
    }

    private func syncVisualAbilityIfNeeded(force: Bool = false) {
        let candidate = visualAbility ?? lastAbility
        guard let ability = candidate, ability.kind != .basic else {
            displayedVisualAbility = nil
            return
        }
        guard force || attackToken != displayedVisualToken else { return }

        displayedVisualToken = attackToken
        displayedVisualAbility = ability
        let token = attackToken
        let isUITestHold = ProcessInfo.processInfo.arguments.contains("-uitestHoldAbilityEffects")
            || ProcessInfo.processInfo.arguments.contains("-uitestSlowAbilityEffects")
        let duration: TimeInterval = isUITestHold ? 8.0 : 0.95
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if displayedVisualToken == token {
                displayedVisualAbility = nil
            }
        }
    }

    private func syncLastAbilityEffect() {
        guard let ability = lastAbility, ability.kind != .basic else { return }

        displayedVisualAbility = ability
        let abilityID = ability.id
        let duration: TimeInterval = ProcessInfo.processInfo.arguments.contains("-uitestSlowAbilityEffects") ? 2.9 : 0.95
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if displayedVisualAbility?.id == abilityID {
                displayedVisualAbility = nil
            }
        }
    }

    /// Screen position of a hero in the party row (for directed strikes).
    private func heroScreenPos(index: Int, in size: CGSize) -> CGPoint {
        // Mirrors `partyRow`: it is inside the main VStack with horizontal padding
        // and appears below the enemy block, well above the flashcard panel.
        let pad: CGFloat = mode == .endless ? 72 : 42
        let spacing: CGFloat = mode == .endless ? 26 : 16
        let count = CGFloat(max(team.count, 1))
        let usable = size.width - pad * 2 - spacing * max(0, count - 1)
        let slot = usable / count
        let x = pad + slot * (CGFloat(index) + 0.5) + spacing * CGFloat(index) - (mode == .endless ? 6 : 4)
        let y = size.height * (mode == .endless ? 0.255 : 0.255)
        return CGPoint(x: x, y: y)
    }

    private func enemyScreenPos(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * (mode == .endless ? 0.16 : 0.16))
    }

    private func contactDelay(for ability: BattleAbility?) -> TimeInterval {
        let holdForUITest = ProcessInfo.processInfo.arguments.contains("-uitestHoldAbilityEffects")
            || ProcessInfo.processInfo.arguments.contains("-uitestSlowAbilityEffects")
        if holdForUITest, let ability, isLegendaryDirectedAbility(ability) {
            return 8.0
        }
        return impactDelay
    }

    private func feedbackPosition(_ target: CombatFeedback.Target, in size: CGSize) -> CGPoint {
        switch target {
        case .ally(let index):
            let pos = heroScreenPos(index: index, in: size)
            return CGPoint(x: pos.x, y: pos.y - 58)
        case .enemy:
            let pos = enemyScreenPos(in: size)
            return CGPoint(x: pos.x, y: pos.y - 70)
        }
    }

    /// Send the ability's effect flying from the hero, then burst it on the enemy.
    private func launchStrike(_ ability: BattleAbility, from index: Int) {
        let holdForUITest = ProcessInfo.processInfo.arguments.contains("-uitestHoldAbilityEffects")
            || ProcessInfo.processInfo.arguments.contains("-uitestSlowAbilityEffects")
        let isHeldDirectedAbility = holdForUITest && isLegendaryDirectedAbility(ability)
        let travelDuration: TimeInterval = isHeldDirectedAbility ? 0.75 : impactDelay
        let projectileHoldDuration: TimeInterval = isHeldDirectedAbility ? 30.0 : 0
        let burstDuration: TimeInterval = holdForUITest ? 8.0 : 0.55
        projectileAbility = ability
        projectileFromIndex = index
        projectileProgress = 0
        if isHeldDirectedAbility {
            projectileProgress = 1
        } else {
            withAnimation(.easeIn(duration: travelDuration)) { projectileProgress = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + travelDuration + projectileHoldDuration) {
            projectileAbility = nil
            guard ability.kind != .basic else { return }
            impactBurstToken += 1
            let tok = impactBurstToken
            impactBurstAbility = ability
            DispatchQueue.main.asyncAfter(deadline: .now() + burstDuration) {
                if impactBurstToken == tok { impactBurstAbility = nil }
            }
        }
    }

    private func runHitAnimation() {
        guard !paused else { return }

        // 0) Cast cue: support abilities get a warm chime, damage abilities a
        //    whoosh/zap. Basics stay silent here and read through their impact.
        if let ability = lastAbility, ability.kind != .basic {
            if isPartyAuraAbility(ability) {
                AudioManager.shared.play(ability.kind == .ultimate ? .castSupportUlt : .castSupport)
                Haptics.support()
                // Clean one-shot team hop: up, then spring back to EXACT baseline.
                partyHopY = -12
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { partyHopY = 0 }
            } else {
                AudioManager.shared.play(ability.kind == .ultimate ? .castDamageUlt : .castDamage)
            }
        }

        // Pure-support abilities (no damage) stop here — only the buff cast +
        // team hop play; no strike, lunge, or enemy hit.
        guard lastAbility?.dealsDamage ?? true else { return }

        // Launch the directed strike from the casting hero toward the enemy.
        if let ability = lastAbility {
            launchStrike(ability, from: lastActorIndex)
        }

        // 1) Attacker lunges forward toward the enemy.
        withAnimation(.easeOut(duration: 0.18)) { lungeY = -22 }

        // 2) On contact: hero springs back and the enemy reacts (shake, flash,
        //    HP drop, damage number) — held off until the lunge connects.
        DispatchQueue.main.asyncAfter(deadline: .now() + contactDelay(for: lastAbility)) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { lungeY = 0 }
            applyImpact()
        }
    }

    private func runAbilityEffect(for ability: BattleAbility) {
        effectAbility = ability
        showAbilityEffect = true
        abilityEffectScale = isPartyAuraAbility(ability) ? 0.68 : (ability.kind == .ultimate ? 0.45 : 0.62)
        abilityEffectOpacity = 1
        abilityEffectRotation = 0
        teamBuffHopY = 0

        let slowForUITest = ProcessInfo.processInfo.arguments.contains("-uitestSlowAbilityEffects")
        let duration: TimeInterval = slowForUITest
            ? 2.4
            : (isPartyAuraAbility(ability) ? 0.72 : (ability.kind == .ultimate ? 0.82 : 0.52))
        withAnimation(.easeOut(duration: duration)) {
            abilityEffectScale = isPartyAuraAbility(ability) ? 1.0 : (ability.kind == .ultimate ? 1.35 : 1.12)
            abilityEffectRotation = isPartyAuraAbility(ability) ? 0 : (ability.kind == .ultimate ? 28 : 12)
        }

        if isPartyAuraAbility(ability) {
            withAnimation(.easeOut(duration: 0.16)) {
                teamBuffHopY = -13
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) {
                    teamBuffHopY = 0
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.62) {
            withAnimation(.easeOut(duration: duration * 0.38)) {
                abilityEffectOpacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            showAbilityEffect = false
            effectAbility = nil
            teamBuffHopY = 0
        }
    }

    private func applyImpact() {
        let kind = lastAbility?.kind ?? .basic
        let enemyDied = mobHP == 0
        let isCrit = kind == .ultimate || enemyDied
        let hitStop: TimeInterval = isCrit ? 0.07 : 0

        // --- Audio + haptics fire immediately at contact (sells the hit-stop) ---
        AudioManager.shared.play(hitSound(for: lastAbility))
        if isCrit {
            AudioManager.shared.play(.crit, volume: 0.85)
            Haptics.crit()
        } else if kind == .skill {
            Haptics.hit()
        } else {
            Haptics.tap()
        }

        // --- Floating damage number (scales with magnitude; gold on crit) ---
        spawnDamageNumber(lastDamage, isCrit: isCrit)
        if let ability = lastAbility {
            showCombatFeedback(for: ability)
        }

        // --- Brief freeze, then the visual reaction lands ---
        DispatchQueue.main.asyncAfter(deadline: .now() + hitStop) {
            if enemyDied {
                withAnimation(.easeOut(duration: 0.16)) {
                    displayedMobHP = 0
                    displayedMobHPChip = 0
                }
            } else if mobHP < displayedMobHP {
                // HP bar drains; chip bar trails behind for readable damage size.
                withAnimation(.easeOut(duration: 0.30)) { displayedMobHP = mobHP }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.easeOut(duration: 0.45)) { displayedMobHPChip = mobHP }
                }
            } else {
                displayedMobHP = mobHP
                displayedMobHPChip = mobHP
            }

            // Flash (tinted by the attacker's class color) + scale punch.
            enemyFlash = isCrit ? 1.0 : 0.8
            enemyHitScale = isCrit ? 1.26 : 1.16
            withAnimation(.easeOut(duration: 0.45)) { enemyFlash = 0 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { enemyHitScale = 1 }

            // Recoil shove + underdamped settle.
            enemyShakeX = isCrit ? -22 : -14
            withAnimation(.spring(response: 0.55, dampingFraction: 0.4)) { enemyShakeX = 0 }

            // Real screen shake — stronger for crits/ultimates.
            kickScreenShake(intensity: isCrit ? 12 : 5)

            if enemyDied { playEnemyDeath() }
        }
    }

    /// Which impact thud matches the ability tier.
    private func hitSound(for ability: BattleAbility?) -> AudioManager.Sound {
        switch ability?.kind {
        case .ultimate: return .hitUltimate
        case .skill: return .hitSkill
        default: return .hitBasic
        }
    }

    private func spawnDamageNumber(_ amount: Int, isCrit: Bool) {
        let dmg = FloatingDamage(amount: amount, isCrit: isCrit,
                                 xJitter: CGFloat.random(in: -16...28))
        floatingDamages.append(dmg)
        // Auto-reap after its rise/fade completes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            floatingDamages.removeAll { $0.id == dmg.id }
        }
    }

    private func showCombatFeedback(for ability: BattleAbility) {
        let grants = ability.grants
        guard !grants.isEmpty else { return }

        var feedback: [CombatFeedback] = []
        for grant in grants {
            switch grant.kind {
            case .mark:
                feedback.append(CombatFeedback(grant: grant, target: .enemy))
            case .attack, .defense, .speed, .shield, .heal, .ultEnergy:
                feedback.append(contentsOf: team.indices.map { CombatFeedback(grant: grant, target: .ally($0)) })
            }
        }

        combatFeedback = feedback
        feedbackRise = 8
        feedbackOpacity = 0
        withAnimation(.spring(response: 0.24, dampingFraction: 0.58)) {
            feedbackRise = -10
            feedbackOpacity = 1
            if feedback.contains(where: { if case .ally = $0.target { true } else { false } }) {
                partyHopY = -10
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            if partyHopY != 0 {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) { partyHopY = 0 }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
            withAnimation(.easeOut(duration: 0.25)) {
                feedbackRise = -32
                feedbackOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.02) {
            combatFeedback = []
            feedbackRise = 0
        }
    }

    private func kickScreenShake(intensity: CGFloat) {
        let dir: CGFloat = Bool.random() ? 1 : -1
        sceneShake = CGSize(width: intensity * dir, height: -intensity * 0.5)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.32)) {
            sceneShake = .zero
        }
    }

    private func playEnemyDeath() {
        AudioManager.shared.play(.enemyDeath)
        Haptics.success()
        enemyDying = true
        enemyDeathScale = 1
        enemyDeathSpin = 0
        enemyEnterY = 0
        enemyEnterOpacity = 1
        // Hold the defeated silhouette for a beat, then collapse and fade.
        withAnimation(.easeOut(duration: 0.16)) {
            enemyDeathScale = 1.12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeIn(duration: 0.52)) {
                enemyDeathScale = 0.62
                enemyDeathSpin = 18
                enemyEnterY = 28
                enemyEnterOpacity = 0
            }
        }
    }

    /// The next enemy drops in and fades up after the previous one dies
    /// (endless). Spring-settled so it feels like an arrival, not a pop.
    private func playEnemyEnter() {
        enemyDying = false
        enemyDeathScale = 1
        enemyDeathSpin = 0
        enemyEnterY = -46
        enemyEnterOpacity = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.68)) {
                enemyEnterY = 0
                enemyEnterOpacity = 1
            }
        }
    }

    /// Gentle continuous "breathing" so the enemy isn't a static sprite.
    private func startIdleBreathing() {
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            enemyBreath = 1.04
        }
        // Soft idle bob applied only to the active hero (see partyRow).
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            activeBob = -3
        }
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { paused = false }

            VStack(spacing: 16) {
                Text("PAUSED")
                    .pixelText(size: 22, color: Color(hex: "F4E6C0"))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("VOLUME")
                            .pixelText(size: 10, color: Color(hex: "3A2A18"))
                        Spacer()
                        Text("\(Int(volume * 100))%")
                            .pixelText(size: 10, color: Color(hex: "6B4324"))
                    }
                    Slider(value: $volume, in: 0...1)
                        .tint(Color(hex: "4A8A3C"))
                        .onChange(of: volume) { _, v in
                            AudioManager.shared.masterVolume = Float(v)
                        }

                    Button {
                        musicOn.toggle()
                        AudioManager.shared.musicEnabled = musicOn
                        Haptics.select()
                    } label: {
                        HStack {
                            Text("MUSIC")
                                .pixelText(size: 10, color: Color(hex: "3A2A18"))
                            Spacer()
                            Text(musicOn ? "ON" : "OFF")
                                .pixelText(size: 10, color: musicOn ? Color(hex: "4A8A3C") : Color(hex: "C84A3A"))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                Button { paused = false } label: {
                    Text("RESUME")
                        .pixelText(size: 15, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "4A8A3C"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)

                Button {
                    paused = false
                    onDone()
                } label: {
                    Text("EXIT BATTLE")
                        .pixelText(size: 13, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "C84A3A"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(width: 270)
            .background(Color(hex: "2A1B0E"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
        }
        .zIndex(20)
    }

    private var statusRow: some View {
        HStack(spacing: 7) {
            if mode == .endless {
                BattleStatusChip("WAVE \(wave)")
                BattleStatusChip("REVIEWED \(reviewedCards)")
                BattleStatusChip("CHAIN \(streak)")
            } else {
                BattleStatusChip(stageLabel)
            }

            // Active buff/debuff chips — each shows its real effect.
            ForEach(Array(combatBuffs.chips.enumerated()), id: \.offset) { _, chip in
                Text("\(chip.kind.icon)\(chip.text)")
                    .pixelText(size: 8, color: Color(hex: "1A130A"))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(buffChipColor(chip.kind))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }

            Spacer(minLength: 0)

            Button(action: onToggleAuto) {
                Text("AUTO")
                    .pixelText(size: 10, color: autoMode ? Color(hex: "1A130A") : Color(hex: "F4E6C0"))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(autoMode ? Color(hex: "FFD24D") : Color(hex: "182116").opacity(0.88))
                    .overlay(Rectangle().stroke(autoMode ? Color(hex: "FFD24D") : Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Auto battle")
            .accessibilityValue(autoMode ? "On" : "Off")

            Button { paused = true } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Color(hex: "F4E6C0"))
                    .frame(width: 30, height: 28)
                    .background(Color(hex: "182116").opacity(0.88))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause")

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
                Spacer(minLength: 0)
                Text("\(displayedMobHP)/\(enemyMaxHP)")
                    .pixelText(size: 9, color: Color(hex: "F4E6C0"))
            }

            // Thin, clean solid-green HP line (fraction shown in the header above).
            GeometryReader { proxy in
                let denom = CGFloat(Swift.max(enemyMaxHP, 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: "1E140C").opacity(0.8))
                    Capsule()
                        .fill(Color(hex: "58C054"))
                        .frame(width: max(2, proxy.size.width * CGFloat(displayedMobHP) / denom))
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 2)

            ZStack {
                SpriteView(asset: currentEnemy?.asset ?? "wild-spikevyrus-hop", size: mode == .endless ? 124 : 118)
                    .shadow(color: .black.opacity(0.34), radius: 0, x: 4, y: 5)
                    .overlay(
                        SpriteView(asset: currentEnemy?.asset ?? "wild-spikevyrus-hop", size: mode == .endless ? 124 : 118)
                            .colorMultiply(enemyFlashColor)
                            .opacity(enemyFlash)
                            .blendMode(.plusLighter)
                    )
                    .scaleEffect(enemyHitScale * enemyBreath * enemyDeathScale)
                    .rotationEffect(.degrees(enemyDeathSpin))
                    .opacity(enemyEnterOpacity)
                    .offset(x: enemyShakeX, y: enemyEnterY)

                ForEach(floatingDamages) { dmg in
                    DamageNumberView(damage: dmg)
                        .offset(x: 34)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Flash color of a hit = the attacking class's signature color (white fallback).
    private var enemyFlashColor: Color {
        lastAbility?.color ?? .white
    }

    private func buffChipColor(_ kind: BuffKind) -> Color {
        switch kind {
        case .attack:    return Color(hex: "FFD24D")
        case .defense:   return Color(hex: "7EB9F0")
        case .speed:     return Color(hex: "8FE3C0")
        case .shield:    return Color(hex: "BFD8FF")
        case .mark:      return Color(hex: "F2A65A")
        case .heal, .ultEnergy: return Color(hex: "C8F08F")
        }
    }

    private var partyRow: some View {
        HStack(alignment: .bottom, spacing: mode == .endless ? 26 : 16) {
            ForEach(Array(team.enumerated()), id: \.element.id) { index, hero in
                let hp = heroHP[hero.id] ?? hero.hp
                let down = mode == .campaign && hp <= 0
                let size = heroSize(for: index)
                let isActive = index == highlightedHeroIndex && !down
                let auraWidth = max(size * 2.55, 96)
                let auraHeight = max(size * 1.75, 68)
                let hop = partyHopY                  // clean shared team-buff hop (returns to 0)
                let bob = isActive ? activeBob : 0    // gentle idle bob on the active hero
                VStack(spacing: 2) {
                    ZStack(alignment: .bottom) {
                        // Grounded contact shadow keeps every hero planted.
                        Ellipse()
                            .fill(Color.black.opacity(0.26))
                            .frame(width: size * 0.92, height: size * 0.2)
                            .offset(y: 4)
                            .blur(radius: 1)
                            .zIndex(0)
                        // Bright spotlight under the hero whose turn it is.
                        if isActive {
                            Ellipse()
                                .fill(RadialGradient(
                                    colors: [Color(hex: "FFE9A8").opacity(0.9), Color(hex: "FFE9A8").opacity(0.0)],
                                    center: .center, startRadius: 1, endRadius: size * 0.72))
                                .frame(width: size * 1.55, height: size * 0.52)
                                .offset(y: 4)
                                .blur(radius: 2)
                                .zIndex(0)
                        }

                        if
                            let effectAbility = activeVisualAbility,
                            isPartyAuraAbility(effectAbility),
                            !down
                        {
                            Ellipse()
                                .fill(effectAbility.color.opacity(effectAbility.kind == .ultimate ? 0.32 : 0.22))
                                .overlay(
                                    Ellipse()
                                        .stroke(effectAbility.color.opacity(0.85), lineWidth: effectAbility.kind == .ultimate ? 3 : 2)
                                )
                                .frame(width: auraWidth * 0.86, height: auraHeight * 0.56)
                                .blur(radius: 1)
                                .offset(y: 8)            // aura stays grounded while the hero hops
                                .allowsHitTesting(false)
                                .zIndex(2)

                            SpriteSheetAbilityEffect(
                                asset: effectAbility.animationKey,
                                frameCount: 8,
                                frameSize: CGSize(width: 200, height: 128)
                            )
                            .id("\(visualEffectToken)-\(hero.id)")
                            .frame(width: auraWidth * 1.12, height: auraHeight * 1.08)
                            .opacity(effectAbility.kind == .ultimate ? 0.95 : 0.72)
                            .blendMode(.screen)
                            .offset(y: hop + bob + 4)
                            .allowsHitTesting(false)
                            .zIndex(3)
                        }

                        SpriteView(asset: hero.asset, size: size)
                            .scaleEffect(heroScale(for: index), anchor: .bottom)
                            .saturation(down ? 0 : 1)
                            .opacity(down ? 0.45 : 1)
                            // White + warm rim glow makes the active hero unmistakable.
                            .shadow(color: isActive ? Color.white.opacity(0.9) : .clear, radius: isActive ? 5 : 0)
                            .shadow(color: isActive ? Color(hex: "FFE9A8").opacity(0.85) : .clear, radius: isActive ? 11 : 0)
                            .offset(y: hop + bob)
                            .animation(.spring(response: 0.30, dampingFraction: 0.6), value: partyHopY)
                            .zIndex(1)
                    }
                    .frame(width: size, height: size + 10, alignment: .bottom)
                    Text(hero.name)
                        .pixelText(size: isActive ? 8 : 7, color: isActive ? Color(hex: "FFE9A8") : Color(hex: "F4E6C0"))
                        .shadow(color: .black.opacity(0.85), radius: 0, x: 1, y: 1)
                        .lineLimit(1)
                    // Campaign: each character has a thin solid-green HP line.
                    if mode == .campaign {
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.5))
                            Capsule()
                                .fill(Color(hex: "58C054"))
                                .frame(width: 40 * CGFloat(hp) / CGFloat(Swift.max(hero.hp, 1)))
                        }
                        .frame(width: 40, height: 3)
                        .opacity(down ? 0.4 : 1)
                    }
                }
                .frame(maxWidth: .infinity)
                .offset(y: index == lastActorIndex ? lungeY : 0)
                .animation(.spring(response: 0.22, dampingFraction: 0.68), value: lastActorIndex)
            }
        }
    }

    /// Upcoming turn order, driven by the Speed/action-value engine.
    private var turnOrder: [Int] {
        upcomingTurns.isEmpty ? [min(max(activeHeroIndex, 0), max(team.count - 1, 0))] : upcomingTurns
    }

    /// Vertical turn timeline shown on the left edge of the battlefield.
    private var turnOrderStrip: some View {
        VStack(spacing: 5) {
            Text("TURN")
                .pixelText(size: 6, color: Color(hex: "F4E6C0"))
                .shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: 1)
            ForEach(Array(turnOrder.enumerated()), id: \.offset) { pos, idx in
                let hero = team[idx]
                let s: CGFloat = pos == 0 ? 28 : 21
                VStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hero.color.opacity(pos == 0 ? 1.0 : 0.6))
                        .frame(width: s, height: s)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(pos == 0 ? Color.white : Color(hex: "18100A"),
                                        lineWidth: pos == 0 ? 2 : 1)
                        )
                        .overlay(
                            Text(String(hero.name.prefix(1)).uppercased())
                                .pixelText(size: pos == 0 ? 12 : 9, color: .white)
                                .shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: 1)
                        )
                        .shadow(color: pos == 0 ? Color.white.opacity(0.7) : .clear, radius: pos == 0 ? 4 : 0)
                    if pos == 0 {
                        Text("SPD \(hero.speed)")
                            .pixelText(size: 6, color: Color(hex: "FFE9A8"))
                            .shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: 1)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 5)
        .background(Color(hex: "18120A").opacity(0.55))
        .overlay(Rectangle().stroke(Color(hex: "18100A").opacity(0.7), lineWidth: 2))
    }

    private var abilityBanner: some View {
        let attacker = team[min(max(lastActorIndex, 0), max(team.count - 1, 0))]
        let upNext = team[min(max(activeHeroIndex, 0), max(team.count - 1, 0))]

        return HStack(spacing: 7) {
            if let ability = lastAbility {
                Text(attacker.name.uppercased())
                    .pixelText(size: 8, color: Color(hex: "F4E6C0"))
                    .frame(width: 58)
                    .padding(.vertical, 5)
                    .background(ability.color.opacity(0.88))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))

                Text(ability.name.uppercased())
                    .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("-\(lastDamage)")
                    .pixelText(size: 11, color: Color(hex: "FFD24D"))
            } else {
                Text(upNext.name.uppercased())
                    .pixelText(size: 8, color: Color(hex: "F4E6C0"))
                    .frame(width: 58)
                    .padding(.vertical, 5)
                    .background(upNext.color.opacity(0.88))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))

                Text("UP NEXT")
                    .pixelText(size: 9, color: Color(hex: "F4E6C0").opacity(0.9))

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 35)
        .background(Color(hex: "182116").opacity(0.84))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }

    private var finalStandPanel: some View {
        VStack(spacing: 8) {
            Text("FINAL STAND")
                .pixelText(size: 14, color: Color(hex: "FFD24D"))
            Text("Review complete. Finish this enemy with free abilities.")
                .font(.custom(MitoFont.regular, size: 15))
                .foregroundStyle(Color(hex: "F4E6C0"))
                .multilineTextAlignment(.center)
            Text("NO COOLDOWNS · NO CHARGE REQUIRED")
                .pixelText(size: 8, color: Color(hex: "9CD67D"))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 138)
        .padding(.horizontal, 16)
        .background(Color(hex: "182116").opacity(0.94))
        .overlay(Rectangle().stroke(Color(hex: "FFD24D"), lineWidth: 3))
    }

    private func heroSize(for index: Int) -> CGFloat {
        let base: CGFloat = mode == .endless ? 43 : 42
        let big: CGFloat = mode == .endless ? 49 : 48
        return index == highlightedHeroIndex ? big : base
    }

    private func heroScale(for index: Int) -> CGFloat {
        index == highlightedHeroIndex ? 1.08 : 1
    }

    /// The enlarged hero is always the one about to act next. `activeHeroIndex`
    /// is advanced to the upcoming attacker after each grade.
    private var highlightedHeroIndex: Int {
        activeHeroIndex
    }

    @ViewBuilder
    private var gradeRow: some View {
        if choosingAbility {
            abilityActionRow
        } else {
            switch answerMode {
            case .classic:
                HStack(spacing: 10) {
                    ForEach(BattleRating.allCases, id: \.self) { rating in
                        BattleGradeButton(rating: rating, enabled: showingAnswer) {
                            onGrade(rating)
                        }
                    }
                }
                .opacity(showingAnswer ? 1 : 0.48)
                .tutorialAnchor("battle.grade")
            case .multipleChoice:
                MultipleChoicePanel(
                    options: mcOptions,
                    correctAnswer: answerText,
                    onReveal: onReveal,
                    onResolved: { onGrade($0) }
                )
                .id(answerCardID)
            case .typeIn:
                TypeInPanel(
                    correctAnswer: answerText,
                    onReveal: onReveal,
                    grade: gradeTyped,
                    onResolved: { onGrade($0) }
                )
                .id(answerCardID)
            }
        }
    }

    private var abilityActionRow: some View {
        let basic = activeHeroAbilities.first { $0.kind == .basic }
        let skill = activeHeroAbilities.first { $0.kind == .skill }
        let ultimate = activeHeroAbilities.first { $0.kind == .ultimate }

        return HStack(spacing: 10) {
            if let basic {
                AbilityActionButton(
                    ability: basic,
                    charge: nil,
                    enabled: true,
                    width: 84,
                    action: { onAbility(basic) }
                )
            }

            if let skill {
                AbilityActionButton(
                    ability: skill,
                    charge: nil,
                    cooldown: finishingWithoutCards ? 0 : skillCooldownTurns,
                    enabled: finishingWithoutCards || skillCooldownTurns == 0,
                    width: 84,
                    action: { onAbility(skill) }
                )
            }

            if let ultimate {
                let required = ultimate.ultimateChargeRequired ?? 4
                AbilityActionButton(
                    ability: ultimate,
                    charge: finishingWithoutCards ? nil : (activeHeroUltCharge, required),
                    enabled: finishingWithoutCards || activeHeroUltCharge >= required,
                    width: 157,
                    action: { onAbility(ultimate) }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .tutorialAnchor("battle.ability")
    }
}

struct AbilityActionButton: View {
    let ability: BattleAbility
    let charge: (current: Int, required: Int)?
    var cooldown: Int = 0
    let enabled: Bool
    let width: CGFloat
    let action: () -> Void

    private var progress: CGFloat {
        guard let charge, charge.required > 0 else { return 1 }
        return min(1, CGFloat(charge.current) / CGFloat(charge.required))
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(ability.kind.rawValue.uppercased())
                    .pixelText(size: 7, color: Color(hex: "F4E6C0").opacity(0.92))
                Text(ability.name.uppercased())
                    .pixelText(size: ability.kind == .ultimate ? 9 : 8, color: Color(hex: "F4E6C0"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                if let charge {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color(hex: "2A1A0D"))
                            Rectangle()
                                .fill(enabled ? Color(hex: "FFD24D") : Color(hex: "6DA6FF"))
                                .frame(width: proxy.size.width * progress)
                        }
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .frame(height: 7)

                    Text("⚡ ENERGY \(charge.current)/\(charge.required)")
                        .pixelText(size: 6, color: Color(hex: "F4E6C0").opacity(0.9))
                } else if cooldown > 0 {
                    Text("ON COOLDOWN")
                        .pixelText(size: 6, color: Color(hex: "F4E6C0").opacity(0.7))
                    Text("\(cooldown) TURN\(cooldown == 1 ? "" : "S")")
                        .pixelText(size: 8, color: Color(hex: "6DA6FF"))
                } else if ability.dealsDamage {
                    Text("PWR \(ability.damage)")
                        .pixelText(size: 6, color: Color(hex: "F4E6C0").opacity(0.88))
                } else {
                    Text("SUPPORT")
                        .pixelText(size: 6, color: Color(hex: "BFE3FF"))
                }
            }
            .frame(width: width, height: 58)
            .background(ability.color.opacity(enabled ? 0.92 : 0.42))
            .overlay(Rectangle().stroke(enabled && ability.kind == .ultimate ? Color(hex: "FFD24D") : Color(hex: "18100A"), lineWidth: enabled && ability.kind == .ultimate ? 4 : 3))
            .shadow(color: enabled && ability.kind == .ultimate ? Color(hex: "FFD24D").opacity(0.5) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }
}
