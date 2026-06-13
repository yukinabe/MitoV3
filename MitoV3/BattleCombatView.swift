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
    let activeHeroAbilities: [BattleAbility]
    let activeHeroUltCharge: Int
    let enemyMaxHP: Int
    let combatBuffs: CombatBuffs
    let upcomingTurns: [Int]
    let skillCooldownTurns: Int
    let wave: Int
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
    @State private var displayedVisualAbility: BattleAbility?
    @State private var displayedVisualToken = 0
    @State private var animatedAttackToken = 0
    @State private var paused = false
    @AppStorage("audio.master") private var volume: Double = 0.8
    @AppStorage("audio.music") private var musicOn: Bool = true

    private var currentWildEnemyID: String {
        if mode == .endless {
            return (wave % 4 == 0) ? "wild-cytocrawler" : "wild-mutagem"
        } else {
            return "wild-spikevyrus"
        }
    }

    private var currentEnemy: Hero? { DataSet.capturable(id: currentWildEnemyID) }

    private var enemyName: String { currentEnemy?.name ?? (mode == .endless ? "Mutagem" : "Spikevyrus") }

    private var enemyRarity: String? {
        mode == .endless ? "EPIC" : nil
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

                // 2) On arrival it bursts on the enemy (every damaging ability, so
                //    buff-and-attack ultimates still land a visible hit).
                if let burst = impactBurstAbility {
                    BattleAbilityEffectView(ability: burst,
                                            scale: burst.kind == .ultimate ? 1.3 : 1.05,
                                            opacity: 1, rotation: 0)
                        .id(impactBurstToken)
                        .frame(width: effectSize(for: burst).width, height: effectSize(for: burst).height)
                        .position(enemyScreenPos(in: proxy.size))
                        .allowsHitTesting(false)
                        .zIndex(8)
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
        "bcell-memory-response"
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
        let pad: CGFloat = mode == .endless ? 72 : 42
        let usable = size.width - pad * 2
        let n = CGFloat(max(team.count, 1))
        let x = pad + (CGFloat(index) + 0.5) * (usable / n)
        let y = size.height * (mode == .endless ? 0.52 : 0.50)
        return CGPoint(x: x, y: y)
    }

    private func enemyScreenPos(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * (mode == .endless ? 0.33 : 0.31))
    }

    /// Send the ability's effect flying from the hero, then burst it on the enemy.
    private func launchStrike(_ ability: BattleAbility, from index: Int) {
        projectileAbility = ability
        projectileFromIndex = index
        projectileProgress = 0
        withAnimation(.easeIn(duration: impactDelay)) { projectileProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + impactDelay) {
            projectileAbility = nil
            guard ability.kind != .basic else { return }
            impactBurstToken += 1
            let tok = impactBurstToken
            impactBurstAbility = ability
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + impactDelay) {
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
        // A kill happened if HP hit zero (campaign) or jumped up because a new
        // enemy spawned (endless). Ultimates always crit-pop; so do finishers.
        let enemyDied = mobHP == 0 || mobHP > displayedMobHP
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

        // --- Brief freeze, then the visual reaction lands ---
        DispatchQueue.main.asyncAfter(deadline: .now() + hitStop) {
            if enemyDied, mode == .endless {
                // Death beat: empty the bar on the dying enemy, then bring the
                // next one in. Purely visual — mobHP is already the new enemy,
                // so the review loop keeps going and a fast answer just lands on
                // the incoming foe.
                withAnimation(.easeOut(duration: 0.16)) {
                    displayedMobHP = 0
                    displayedMobHPChip = 0
                }
                let incomingHP = mobHP
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                    displayedMobHP = incomingHP
                    displayedMobHPChip = incomingHP
                    playEnemyEnter()
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
        // Shrink + spin + fade — the "pop" of a kill.
        withAnimation(.easeIn(duration: 0.38)) {
            enemyDeathScale = 0.02
            enemyDeathSpin = 220
        }
        // Reset the death transform once it's offscreen. The enemy-enter
        // animation (endless) takes over opacity/offset from here.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            enemyDying = false
            enemyDeathScale = 1
            enemyDeathSpin = 0
        }
    }

    /// The next enemy drops in and fades up after the previous one dies
    /// (endless). Spring-settled so it feels like an arrival, not a pop.
    private func playEnemyEnter() {
        enemyEnterY = -46
        enemyEnterOpacity = 0
        withAnimation(.spring(response: 0.40, dampingFraction: 0.7)) {
            enemyEnterY = 0
            enemyEnterOpacity = 1
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
                    .opacity(enemyDying ? Double(Swift.max(enemyDeathScale, 0)) : enemyEnterOpacity)
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

                Text("-\(ability.damage)")
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
                    cooldown: skillCooldownTurns,
                    enabled: skillCooldownTurns == 0,
                    width: 84,
                    action: { onAbility(skill) }
                )
            }

            if let ultimate {
                let required = ultimate.ultimateChargeRequired ?? 4
                AbilityActionButton(
                    ability: ultimate,
                    charge: (activeHeroUltCharge, required),
                    enabled: activeHeroUltCharge >= required,
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
                    Text("DMG \(ability.damage)")
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

