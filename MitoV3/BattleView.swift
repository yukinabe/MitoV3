import SwiftUI

enum BattleMode {
    case endless
    case campaign
}

enum BattleRating: CaseIterable, Equatable {
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

struct BattleScreen: View {
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
    @State private var enemyMaxHP = 132
    @State private var wave = 1
    @State private var currentCard = 0
    @State private var showingAnswer = false
    @State private var reviewedCards = 15
    @State private var streak = 2
    @State private var activeHeroIndex = 0
    @State private var lastActorIndex = 0
    @State private var lastAbility: BattleAbility?
    @State private var attackToken = 0
    @State private var lastDamage = 0
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
        if !didUITestJump, ProcessInfo.processInfo.arguments.contains("-uitestMap") {
            didUITestJump = true
            route = .map
            return
        }
        if !didUITestJump, ProcessInfo.processInfo.arguments.contains("-uitestStage") {
            didUITestJump = true
            route = .stageSetup
            return
        }
        guard !didUITestJump,
              ProcessInfo.processInfo.arguments.contains("-uitestReview") else { return }
        didUITestJump = true
        battleMode = .endless
        wave = 1
        enemyMaxHP = BattleScaling.endlessEnemyHP(teamLevel: teamLevel, wave: 1)
        mobHP = enemyMaxHP
        teamHP = teamMaxHP
        reviewedCards = 0
        streak = 0
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
                wave = 1
                enemyMaxHP = BattleScaling.endlessEnemyHP(teamLevel: teamLevel, wave: 1)
                mobHP = enemyMaxHP
                teamHP = teamMaxHP
                currentCard = 0
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
                                        .frame(width: 50, height: 50)
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
            stage: selectedStage,
            decks: pickerDecks,
            selectedDecks: $selectedDecks,
            selectedTags: $selectedTags,
            onBack: { route = .map },
            onStart: {
                guard !selectedDecks.isEmpty else { return }
                battleMode = .campaign
                wave = 1
                enemyMaxHP = BattleScaling.campaignEnemyHP(
                    stageIndex: selectedStage.id,
                    tierMultiplier: selectedStage.tierMultiplier,
                    teamLevel: teamLevel
                )
                mobHP = enemyMaxHP
                teamHP = teamMaxHP
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
            attackToken: attackToken,
            lastDamage: lastDamage,
            enemyMaxHP: enemyMaxHP,
            wave: wave,
            stageLabel: "STAGE \(selectedStage.id) · \(selectedStage.difficulty)",
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
                    Text(mobHP <= 0 ? "+\(clearGold) gold  +\(clearBiomass) biomass" : "Review more cards and try again.")
                        .font(.custom(MitoFont.regular, size: 18))
                        .foregroundStyle(Color(hex: "4A2F1C"))
                    PixelButton(title: "CONTINUE") {
                        if mobHP <= 0 {
                            gold += clearGold
                            biomass += clearBiomass
                        }
                        route = .landing
                    }
                }
                .padding(8)
            }
            .padding(22)
        }
    }

    /// Campaign clear reward scales with the cleared stage's tier.
    private var clearGold: Int { Int(100 * selectedStage.tierMultiplier) }
    private var clearBiomass: Int { Int(6 * selectedStage.tierMultiplier) }

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

    /// Active battle party (endless fields 3, campaign fields 4).
    private var activeTeam: [Hero] {
        Array(DataSet.heroes.prefix(battleMode == .endless ? 3 : 4))
    }

    /// Average level of the active team, used to scale enemy difficulty.
    private var teamLevel: Int {
        let levels = activeTeam.map(\.level)
        return levels.isEmpty ? 10 : levels.reduce(0, +) / levels.count
    }

    /// Team max HP is the sum of the party's HP pools.
    private var teamMaxHP: Int {
        activeTeam.map(\.hp).reduce(0, +)
    }

    private func grade(_ rating: BattleRating) {
        // Schedule the current card with FSRS and persist before advancing.
        session.grade(rating.fsrs)
        // Endless review loops forever: rebuild the queue once it drains.
        if session.current == nil {
            session.start(deckIDs: selectedDecks, tags: selectedTags)
        }

        let ability = battleMode == .endless ? rollEndlessAbility() : nil
        // Player damage scales with team level so leveling up matters.
        let damageMult = BattleScaling.heroDamageMultiplier(teamLevel: teamLevel)
        let damage = max(1, Int(Double(ability?.damage ?? rating.damage) * damageMult))
        // Campaign mistakes hurt more on harder stages.
        let recoil = battleMode == .campaign ? Int(Double(rating.recoil) * selectedStage.tierMultiplier) : 0
        let enemyDefeated = mobHP - damage <= 0
        let teamDefeated = teamHP - recoil <= 0
        // Drive the combat juice (hit flash, shake, floating number, lunge).
        lastDamage = damage
        attackToken += 1
        mobHP = max(0, mobHP - damage)
        teamHP = max(0, teamHP - recoil)
        reviewedCards += 1
        streak = battleMode == .endless ? streak + 1 : (rating == .again ? 0 : streak + 1)
        currentCard += 1
        showingAnswer = false

        let modeName = battleMode == .endless ? "endless" : "campaign"
        Task {
            await MitoBackend.shared.logEvent("review_graded", props: [
                "rating": rating.title, "mode": modeName, "damage": "\(damage)"
            ])
        }

        if battleMode == .endless, enemyDefeated {
            // Next wave: stronger enemy + bigger loot.
            wave += 1
            enemyMaxHP = BattleScaling.endlessEnemyHP(teamLevel: teamLevel, wave: wave)
            mobHP = enemyMaxHP
            let reward = BattleScaling.endlessReward(wave: wave)
            gold += reward.gold
            biomass += reward.biomass
            let clearedWave = wave - 1
            Task { await MitoBackend.shared.logEvent("battle_wave_cleared", props: ["wave": "\(clearedWave)", "mode": "endless"]) }
        } else if enemyDefeated || teamDefeated {
            let outcome = enemyDefeated ? "win" : "loss"
            let stageID = selectedStage.id
            let reviewed = reviewedCards
            Task {
                await MitoBackend.shared.logEvent("battle_run", props: [
                    "outcome": outcome, "mode": modeName,
                    "stage": "\(stageID)", "reviewed": "\(reviewed)"
                ])
            }
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

struct BattleCombatView: View {
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
    let attackToken: Int
    let lastDamage: Int
    let enemyMaxHP: Int
    let wave: Int
    let stageLabel: String
    let onReveal: () -> Void
    let onDone: () -> Void
    let onGrade: (BattleRating) -> Void

    // Combat juice + pause state.
    @Environment(\.scenePhase) private var scenePhase
    @State private var enemyShakeX: CGFloat = 0
    @State private var enemyFlash: Double = 0
    @State private var enemyHitScale: CGFloat = 1
    @State private var screenShakeX: CGFloat = 0
    @State private var lungeY: CGFloat = 0
    @State private var displayedMobHP = 0
    @State private var damagePopupID = 0
    @State private var showDamage = false
    @State private var damageRise: CGFloat = 0
    @State private var damageFade: Double = 0
    @State private var paused = false
    @AppStorage("battleVolume") private var volume = 0.8

    private var enemyName: String {
        mode == .endless ? "Mutagem" : "Spikevyrus"
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

                    gradeRow
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 82)

                    Spacer(minLength: 0)
                }
                .offset(x: screenShakeX)

                if paused {
                    pauseOverlay
                }
            }
            .onAppear { displayedMobHP = mobHP }
            .onChange(of: attackToken) { _, _ in runHitAnimation() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { paused = true }
            }
        }
    }

    /// One satisfying hit: enemy flash + recoil shake + scale punch, attacker
    /// lunge, a floating damage number, and a quick screen shake.
    /// Travel time of the lunge before it "connects" with the enemy.
    private let impactDelay: TimeInterval = 0.22

    private func runHitAnimation() {
        guard !paused else { return }

        // 1) Attacker lunges forward toward the enemy.
        withAnimation(.easeOut(duration: 0.18)) { lungeY = -22 }

        // 2) On contact: hero springs back and the enemy reacts (shake, flash,
        //    HP drop, damage number) — held off until the lunge connects.
        DispatchQueue.main.asyncAfter(deadline: .now() + impactDelay) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { lungeY = 0 }
            applyImpact()
        }
    }

    private func applyImpact() {
        // HP bar drains on impact (snap up instantly if a new enemy spawned).
        if mobHP < displayedMobHP {
            withAnimation(.easeOut(duration: 0.40)) { displayedMobHP = mobHP }
        } else {
            displayedMobHP = mobHP
        }

        // Flash + scale punch.
        enemyFlash = 0.8
        enemyHitScale = 1.16
        withAnimation(.easeOut(duration: 0.45)) { enemyFlash = 0 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { enemyHitScale = 1 }

        // Recoil: one shove + a slow underdamped settle (weighty, not jittery).
        enemyShakeX = -14
        screenShakeX = -6
        withAnimation(.spring(response: 0.55, dampingFraction: 0.4)) {
            enemyShakeX = 0
            screenShakeX = 0
        }

        // Floating damage number rises and fades.
        damagePopupID += 1
        showDamage = true
        damageRise = 0
        damageFade = 1
        withAnimation(.easeOut(duration: 1.05)) {
            damageRise = -64
            damageFade = 0
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

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("VOLUME")
                            .pixelText(size: 10, color: Color(hex: "3A2A18"))
                        Spacer()
                        Text("\(Int(volume * 100))%")
                            .pixelText(size: 10, color: Color(hex: "6B4324"))
                    }
                    Slider(value: $volume, in: 0...1)
                        .tint(Color(hex: "4A8A3C"))
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

            Spacer(minLength: 0)

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
                if mode == .campaign {
                    Spacer(minLength: 0)
                    Text("\(displayedMobHP)/\(enemyMaxHP)")
                        .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                }
            }

            HPBar(value: displayedMobHP, max: enemyMaxHP, tint: Color(hex: "58C054"))
                .frame(height: mode == .endless ? 15 : 13)

            ZStack {
                Image("mob_1")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: mode == .endless ? 124 : 118, height: mode == .endless ? 124 : 118)
                    .shadow(color: .black.opacity(0.34), radius: 0, x: 4, y: 5)
                    .overlay(
                        Image("mob_1")
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: mode == .endless ? 124 : 118, height: mode == .endless ? 124 : 118)
                            .colorMultiply(.white)
                            .opacity(enemyFlash)
                            .blendMode(.plusLighter)
                    )
                    .scaleEffect(enemyHitScale)
                    .offset(x: enemyShakeX)

                if showDamage {
                    Text("-\(lastDamage)")
                        .font(.custom(MitoFont.bold, size: 26))
                        .foregroundStyle(Color(hex: "FFE14D"))
                        .shadow(color: .black.opacity(0.8), radius: 0, x: 2, y: 2)
                        .offset(x: 42, y: -28 + damageRise)
                        .opacity(damageFade)
                        .id(damagePopupID)
                }
            }
        }
    }

    private var partyRow: some View {
        HStack(alignment: .bottom, spacing: mode == .endless ? 24 : 18) {
            ForEach(Array(DataSet.heroes.prefix(heroCount).enumerated()), id: \.element.id) { index, hero in
                VStack(spacing: -1) {
                    SpriteView(asset: hero.asset, size: heroSize(for: index))
                        .scaleEffect(heroScale(for: index), anchor: .bottom)
                    Text(hero.name)
                        .pixelText(size: 7, color: Color(hex: "F4E6C0"))
                        .shadow(color: .black.opacity(0.85), radius: 0, x: 1, y: 1)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .offset(y: index == lastActorIndex ? lungeY : 0)
                .animation(.spring(response: 0.22, dampingFraction: 0.68), value: lastActorIndex)
            }
        }
    }

    private var abilityBanner: some View {
        let attacker = DataSet.heroes[min(max(lastActorIndex, 0), DataSet.heroes.count - 1)]
        let upNext = DataSet.heroes[min(max(activeHeroIndex, 0), DataSet.heroes.count - 1)]

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
        mode == .endless ? (index == highlightedHeroIndex ? 49 : 43) : 40
    }

    private func heroScale(for index: Int) -> CGFloat {
        mode == .endless && index == highlightedHeroIndex ? 1.08 : 1
    }

    /// The enlarged hero is always the one about to act next. `activeHeroIndex`
    /// is advanced to the upcoming attacker after each grade, so it is the
    /// correct "on deck" hero (the previous code highlighted whoever just hit).
    private var highlightedHeroIndex: Int {
        activeHeroIndex
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

struct BattleStatusChip: View {
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

struct BattleFlashcardPanel: View {
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
        VStack(alignment: .leading, spacing: 10) {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 4)

            if !showingAnswer {
                Button(action: onReveal) {
                    Text("SHOW ANSWER")
                        .pixelText(size: 16, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 39)
                        .background(Color(hex: "6B4324"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 224)
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

struct BattlePanelTag: View {
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

struct BattleGradeButton: View {
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

struct CampaignStageSetup: View {
    let stage: Stage
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
                    Text("STAGE \(stage.id) · \(stage.difficulty)")
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
                        Text(stage.name.uppercased())
                            .pixelText(size: 13, color: Color(hex: "3A2A18"))
                        Text("Spikevyrus · \(stage.difficulty == "BOSS" ? "boss fight" : "3 waves")")
                            .font(.custom(MitoFont.regular, size: 15))
                            .foregroundStyle(Color(hex: "6B4324"))
                    }
                    Spacer()
                    Text(stage.difficulty)
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
                    Button {
                        let all = Set(decks.map(\.id))
                        selectedDecks = all.isSubset(of: selectedDecks) ? [] : all
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

                // Decks scroll only within this region; the page never shifts.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(decks) { deck in
                            EndlessDeckRow(deck: deck, isSelected: selectedDecks.contains(deck.id), highlightSelected: true) {
                                toggleDeck(deck)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)

                TagFilterSection(availableTags: availableTags, selectedTags: $selectedTags)

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
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
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
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

struct EndlessReviewSetup: View {
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

    var body: some View {
            VStack(spacing: 10) {
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

                HStack {
                    Text("PICK YOUR DECKS")
                        .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                    Spacer()
                    Button {
                        let all = Set(decks.map(\.id))
                        selectedDecks = all.isSubset(of: selectedDecks) ? [] : all
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

                // Decks scroll only within this region; the page never shifts.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(decks) { deck in
                            EndlessDeckRow(deck: deck, isSelected: selectedDecks.contains(deck.id)) {
                                toggleDeck(deck)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)

                TagFilterSection(availableTags: availableTags, selectedTags: $selectedTags)

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
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                ZStack {
                    Image("map-bg")
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                    Color(hex: "123D2F").opacity(0.66)
                    LinearGradient(colors: [.clear, Color.black.opacity(0.30)], startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea()
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

/// Shared, self-contained tag filter for the battle setup screens: a tidy
/// bordered panel whose chips wrap (FlowLayout) and scroll independently when
/// there are many tags, so it never bloats or leaves dead space.
struct TagFilterSection: View {
    let availableTags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("FILTER BY TAG")
                    .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                Text("· OPTIONAL")
                    .pixelText(size: 7, color: Color(hex: "F4E6C0").opacity(0.55))
                Spacer(minLength: 0)
                if !selectedTags.isEmpty {
                    Button { selectedTags.removeAll() } label: {
                        Text("CLEAR")
                            .pixelText(size: 8, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(hex: "EAD4A4"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }

            if availableTags.isEmpty {
                Text("Select a deck to reveal its tags.")
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(Color(hex: "F4E6C0").opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView(showsIndicators: false) {
                    FlowLayout(spacing: 7) {
                        ForEach(availableTags, id: \.self) { tag in
                            Button { toggle(tag) } label: {
                                SmallTag(tag.uppercased(), active: selectedTags.contains(tag))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 56)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.30))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }

    private func toggle(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

struct EndlessDeckRow: View {
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
