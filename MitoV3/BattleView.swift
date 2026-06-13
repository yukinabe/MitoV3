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

    /// Build a battle grade from an FSRS rating produced by an answer mode
    /// (multiple-choice speed mapping or the AI type-in grader).
    init(_ rating: Rating) {
        switch rating {
        case .again: self = .again
        case .hard: self = .hard
        case .good: self = .good
        case .easy: self = .easy
        }
    }

    /// Satisfying woody tick that rises in brightness from Again → Easy.
    var gradeSound: AudioManager.Sound {
        switch self {
        case .again: .gradeAgain
        case .hard: .gradeHard
        case .good: .gradeGood
        case .easy: .gradeEasy
        }
    }
}

struct BattleScreen: View {
    @Binding var atp: Int
    @Binding var gold: Int
    @Binding var biomass: Int

    @State private var route: BattleRoute = .landing
    @State private var battleMode: BattleMode = .endless
    @State private var selectedStage = DataSet.stages[0]
    /// Highest campaign stage cleared (0 = fresh start, only stage 1 open).
    @AppStorage("campaign.cleared") private var clearedStage = 0
    /// All active combat buffs/debuffs (atk, def, speed, shield, mark).
    @State private var combatBuffs = CombatBuffs()
    /// HSR-style speed/action-value turn order.
    @State private var turnEngine = TurnEngine()
    /// Per-hero skill cooldown (remaining turns of that hero before re-use).
    @State private var skillCooldown: [String: Int] = [:]
    @State private var selectedDecks: Set<String> = ["bio"]
    @State private var selectedTags: Set<String> = []
    @State private var mobHP = 132
    /// Per-character HP for Campaign (keyed by hero id). Endless has no player HP.
    @State private var heroHP: [String: Int] = [:]
    @State private var enemyMaxHP = 132
    @State private var wave = 1
    @State private var currentCard = 0
    @State private var showingAnswer = false
    @State private var reviewedCards = 15
    @State private var streak = 2
    @State private var activeHeroIndex = 0
    @State private var lastActorIndex = 0
    @State private var lastAbility: BattleAbility?
    @State private var visualAbility: BattleAbility?
    @State private var visualEffectToken = 0
    @State private var attackToken = 0
    @State private var lastDamage = 0
    @State private var pendingRating: BattleRating?
    @State private var choosingAbility = false
    @State private var ultimateCharge: [String: Int] = [:]
    /// Auto-battle: when on, the best ability (ult → skill → basic) is cast
    /// automatically after each card is graded. Studying stays manual.
    @AppStorage("battle.autoMode") private var autoMode = false
    /// How the player answers cards this session (classic / multiple-choice /
    /// type-in). Chosen on the setup screens; persisted for convenience.
    @AppStorage("battle.answerMode") private var answerModeRaw = AnswerMode.classic.rawValue
    private var answerMode: AnswerMode {
        let mode = AnswerMode(rawValue: answerModeRaw) ?? .classic
        // Multiple-choice was retired; anyone who had it saved falls back.
        return AnswerMode.selectable.contains(mode) ? mode : .classic
    }
    @ObservedObject private var session = ReviewSession.shared
    /// A capturable wild creature offered after defeating it (campaign/endless).
    @State private var captureOffer: Hero?
    /// Creatures already offered this run, so a declined capture isn't re-offered
    /// every wave. Cleared when a fresh battle starts.
    @State private var offeredThisRun: Set<String> = []

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

            if let creature = captureOffer {
                CapturePopup(
                    creature: creature,
                    onCapture: {
                        CaptureStore.shared.capture(creature.id)
                        AudioManager.shared.play(.victory, volume: 0.8)
                        Haptics.success()
                        captureOffer = nil
                    },
                    onRelease: {
                        Haptics.tap()
                        captureOffer = nil
                    }
                )
                .zIndex(50)
            }
        }
        .onAppear(perform: maybeJumpToReviewForUITest)
    }

    /// The wild creature tied to the current enemy, if the player hasn't caught
    /// it yet. Endless = Mutagem (Cytocrawler on every 4th wave); campaign =
    /// Spikevyrus. Returns nil if already owned, so we never re-offer.
    private var currentWildEnemyID: String {
        if battleMode == .endless {
            return (wave % 4 == 0) ? "wild-cytocrawler" : "wild-mutagem"
        } else {
            return "wild-spikevyrus"
        }
    }

    private func captureCandidate() -> Hero? {
        let id = currentWildEnemyID
        guard !CaptureStore.shared.isOwned(id) else { return nil }
        return DataSet.capturable(id: id)
    }

    /// Show the capture popup for the defeated creature, unless it's already been
    /// offered this run (so declining doesn't nag every wave).
    private func offerCaptureIfWild() {
        guard let creature = captureCandidate(), !offeredThisRun.contains(creature.id) else { return }
        offeredThisRun.insert(creature.id)
        // Let the victory beat land first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { captureOffer = creature }
    }

    /// UI-test affordance only (DEBUG builds): with `-uitestReview`, drop
    /// straight into an endless-review combat so screenshots can capture the
    /// live FSRS loop. Compiles to a no-op in release.
    @State private var didUITestJump = false
    @State private var didUITestAutoCast = false
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
        if !didUITestJump, ProcessInfo.processInfo.arguments.contains("-uitestCampaign") {
            didUITestJump = true
            battleMode = .campaign
            enemyMaxHP = BattleScaling.campaignEnemyHP(
                stageIndex: selectedStage.id, tierMultiplier: selectedStage.tierMultiplier, teamLevel: teamLevel)
            mobHP = enemyMaxHP
            heroHP = Dictionary(uniqueKeysWithValues: activeTeam.map { ($0.id, $0.hp) })
            resetCombatFlow()
            showingAnswer = ProcessInfo.processInfo.arguments.contains("-uitestReveal")
            session.start(deckIDs: [])
            route = .combat
            return
        }
        guard !didUITestJump,
              ProcessInfo.processInfo.arguments.contains("-uitestReview") else { return }
        didUITestJump = true
        battleMode = .endless
        wave = 1
        enemyMaxHP = BattleScaling.endlessEnemyHP(teamLevel: teamLevel, wave: 1)
        mobHP = enemyMaxHP
        resetCombatFlow()
        session.start(deckIDs: [])
        // UI-test: force an answer mode, e.g. -uitestAnswerMode=multipleChoice
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-uitestAnswerMode=") }),
           let mode = AnswerMode(rawValue: String(arg.dropFirst("-uitestAnswerMode=".count))) {
            answerModeRaw = mode.rawValue
        }
        showingAnswer = ProcessInfo.processInfo.arguments.contains("-uitestReveal")
        route = ProcessInfo.processInfo.arguments.contains("-uitestPicker") ? .reviewSetup : .combat

        // UI-test: pop the capture offer so it can be screenshotted.
        if ProcessInfo.processInfo.arguments.contains("-uitestCapture") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                captureOffer = DataSet.capturable(id: "wild-mutagem")
            }
        }

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
        if ProcessInfo.processInfo.arguments.contains("-uitestAI") {
            Task {
                await MitoBackend.shared.attachSync(to: session)
                let result = await MitoBackend.shared.runAISelfTest()
                let url = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("uitest_ai.txt")
                try? result.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        #endif
    }

    private func scheduleUITestAutoCastIfNeeded() {
        #if DEBUG
        guard !didUITestAutoCast,
              route == .combat,
              let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-uitestAutoCast=") })
        else { return }

        didUITestAutoCast = true
        let requestedKind = String(arg.dropFirst("-uitestAutoCast=".count)).lowercased()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showingAnswer = true
            if requestedKind == "ultimate", let activeHero {
                let required = activeHero.abilities.first { $0.kind == .ultimate }?.ultimateChargeRequired ?? 4
                ultimateCharge[activeHero.id] = required
            }
            grade(.good)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                let targetKind: AbilityKind = requestedKind == "ultimate" ? .ultimate : .skill
                if let ability = activeHeroAbilities.first(where: { $0.kind == targetKind }) {
                    useAbility(ability)
                }
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

    /// Bridge the persisted raw string to a typed binding for the pickers.
    private var answerModeBinding: Binding<AnswerMode> {
        Binding(get: { answerMode }, set: { answerModeRaw = $0.rawValue })
    }

    /// When the player chooses multiple-choice, pre-generate any missing
    /// distractors in the background so options are AI-quality (best-effort;
    /// a sibling-answer fallback covers anything not yet generated).
    private func prepareAnswerMode() {
        guard answerMode == .multipleChoice else { return }
        let cards = session.allCards()
        Task { await MitoBackend.shared.backfillDistractors(for: cards) }
    }

    private var reviewSetup: some View {
        EndlessReviewSetup(
            decks: pickerDecks,
            selectedDecks: $selectedDecks,
            selectedTags: $selectedTags,
            answerMode: answerModeBinding,
            onBack: { route = .landing },
            onStart: {
                battleMode = .endless
                wave = 1
                enemyMaxHP = BattleScaling.endlessEnemyHP(teamLevel: teamLevel, wave: 1)
                mobHP = enemyMaxHP
                resetCombatFlow()
                session.start(deckIDs: selectedDecks, tags: selectedTags)
                prepareAnswerMode()
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
                            let status = stageStatus(stage)
                            Button {
                                guard status != .locked else { return }
                                selectedStage = stage
                                route = .stageSetup
                            } label: {
                                VStack(spacing: 3) {
                                    Image(status.asset)
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

    /// Stage unlock state derived from saved progress: everything up to the
    /// highest cleared stage is done, the next one is active, the rest locked.
    private func stageStatus(_ stage: Stage) -> StageStatus {
        if stage.id <= clearedStage { return .cleared }
        if stage.id == clearedStage + 1 { return .active }
        return .locked
    }

    private var stageSetup: some View {
        CampaignStageSetup(
            stage: selectedStage,
            decks: pickerDecks,
            selectedDecks: $selectedDecks,
            selectedTags: $selectedTags,
            answerMode: answerModeBinding,
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
                heroHP = Dictionary(uniqueKeysWithValues: activeTeam.map { ($0.id, $0.hp) })
                resetCombatFlow()
                session.start(deckIDs: selectedDecks, tags: selectedTags)
                prepareAnswerMode()
                route = .combat
            }
        )
    }

    private var combat: some View {
        BattleCombatView(
            mode: battleMode,
            mobHP: mobHP,
            heroHP: heroHP,
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
            visualAbility: visualAbility,
            visualEffectToken: visualEffectToken,
            attackToken: attackToken,
            lastDamage: lastDamage,
            choosingAbility: choosingAbility,
            activeHeroAbilities: activeHeroAbilities,
            activeHeroUltCharge: activeHeroUltCharge,
            enemyMaxHP: enemyMaxHP,
            combatBuffs: combatBuffs,
            upcomingTurns: upcomingTurnIndices(5),
            skillCooldownTurns: activeSkillCooldown,
            wave: wave,
            stageLabel: "STAGE \(selectedStage.id) · \(selectedStage.difficulty)",
            autoMode: autoMode,
            answerMode: answerMode,
            answerCardID: session.current?.id,
            mcOptions: session.current.map(answerOptions(for:)) ?? [],
            onReveal: {
                showingAnswer = true
                AudioManager.shared.play(.cardShow)
                Haptics.tap()
            },
            onDone: { route = .landing },
            onGrade: grade,
            onAbility: useAbility,
            onToggleAuto: {
                autoMode.toggle()
                Haptics.tap()
            },
            gradeTyped: { text, signals in await aiGradeTyped(text, signals) }
        )
        .onAppear(perform: scheduleUITestAutoCastIfNeeded)
        // Flipping auto on while the ability picker is already showing should
        // cast immediately rather than waiting for the next card.
        .onChange(of: autoMode) { _, isOn in
            guard isOn, choosingAbility, let ability = autoChosenAbility() else { return }
            autoCast(ability)
        }
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

    // MARK: - Answer modes (multiple-choice / type-in)

    /// The shuffled multiple-choice options for a card: the correct answer plus
    /// up to three distractors (AI-cached on the card, or sampled from sibling
    /// cards when none are generated yet). Order is deterministic per card so it
    /// doesn't reshuffle on every redraw.
    private func answerOptions(for card: ReviewCard) -> [String] {
        let correct = card.back
        let correctKey = AnswerGrading.normalize(correct)
        let distractorSource = (card.choices?.isEmpty == false) ? card.choices! : siblingDistractors(for: card)
        var seen: Set<String> = [correctKey]
        var distractors: [String] = []
        for d in distractorSource {
            let key = AnswerGrading.normalize(d)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            distractors.append(d)
            if distractors.count == 3 { break }
        }
        var rng = SeededGenerator(seed: card.id)
        return ([correct] + distractors).shuffled(using: &rng)
    }

    /// Offline/no-AI fallback distractors: other cards' answers from the same
    /// deck (then anywhere) so multiple-choice always has options to show.
    private func siblingDistractors(for card: ReviewCard) -> [String] {
        let all = session.allCards()
        let correctKey = AnswerGrading.normalize(card.back)
        func pick(_ pool: [ReviewCard]) -> [String] {
            pool.filter { $0.id != card.id && AnswerGrading.normalize($0.back) != correctKey }
                .map(\.back)
        }
        let sameDeck = pick(all.filter { $0.deckID == card.deckID })
        let others = pick(all.filter { $0.deckID != card.deckID })
        var rng = SeededGenerator(seed: card.id)
        return (sameDeck.shuffled(using: &rng) + others.shuffled(using: &rng))
    }

    /// Grade a typed answer via the AI edge function, falling back to a local
    /// similarity score when offline / the call fails. Returns a battle grade
    /// plus optional learner feedback to surface.
    private func aiGradeTyped(_ text: String, _ signals: TypingSignals) async -> (BattleRating, String?) {
        guard let card = session.current else { return (.again, nil) }
        do {
            let g = try await MitoBackend.shared.gradeTypedAnswer(
                cardID: card.id, userAnswer: text,
                elapsedMs: signals.elapsedMs, signals: signals)
            return (BattleRating(g.rating), g.feedback)
        } catch {
            return (BattleRating(AnswerGrading.localSimilarityRating(expected: card.back, answer: text)), nil)
        }
    }

    /// The shared 3-character active party (same for both modes).
    private var activeTeam: [Hero] { BattleRules.partyHeroes }

    private var activeHero: Hero? {
        guard !activeTeam.isEmpty else { return nil }
        return activeTeam[min(max(activeHeroIndex, 0), activeTeam.count - 1)]
    }

    private var activeHeroAbilities: [BattleAbility] {
        activeHero?.abilities ?? []
    }

    private var activeHeroUltCharge: Int {
        guard let activeHero else { return 0 }
        return ultimateCharge[activeHero.id] ?? 0
    }

    /// Remaining skill-cooldown turns for the hero whose turn it is.
    private var activeSkillCooldown: Int {
        guard let activeHero else { return 0 }
        return skillCooldown[activeHero.id] ?? 0
    }

    /// Hero ids still standing (campaign tracks HP; endless never falls).
    private func aliveIds() -> Set<String> {
        if battleMode == .campaign {
            return Set(activeTeam.filter { (heroHP[$0.id] ?? $0.hp) > 0 }.map { $0.id })
        }
        return Set(activeTeam.map { $0.id })
    }

    /// activeTeam index of whoever the turn engine says acts next.
    private func currentTurnIndex() -> Int {
        guard let id = turnEngine.current(alive: aliveIds()),
              let idx = activeTeam.firstIndex(where: { $0.id == id }) else {
            return min(max(activeHeroIndex, 0), max(activeTeam.count - 1, 0))
        }
        return idx
    }

    /// Upcoming turn order as activeTeam indices (for the on-screen timeline).
    private func upcomingTurnIndices(_ n: Int) -> [Int] {
        turnEngine.upcoming(n, heroes: effectiveTeam(), alive: aliveIds()).compactMap { id in
            activeTeam.firstIndex(where: { $0.id == id })
        }
    }

    /// The active team with the team SPEED buff folded into each hero's speed.
    private func effectiveTeam() -> [Hero] {
        let bonus = combatBuffs.speedBonus
        guard bonus != 0 else { return activeTeam }
        return activeTeam.map { var h = $0; h.speed += bonus; return h }
    }

    /// Advance the action clock for whoever just acted (speed buff included).
    private func advanceTurn(after index: Int) {
        let actor = activeTeam[index]
        turnEngine.advance(actor: actor.id,
                           speed: actor.speed + combatBuffs.speedBonus,
                           alive: aliveIds())
        activeHeroIndex = currentTurnIndex()
    }

    /// Apply an ability's buff/effect grants (stat buffs + instant heal/energy).
    private func applyGrants(_ ability: BattleAbility) {
        for g in ability.grants {
            switch g.kind {
            case .attack:  combatBuffs.attack.apply(g.magnitude, g.turns)
            case .defense: combatBuffs.defense.apply(g.magnitude, g.turns)
            case .speed:
                combatBuffs.speed.apply(g.magnitude, g.turns)
                turnEngine.advanceGauge(0.15, alive: aliveIds())   // act a bit sooner now
            case .mark:    combatBuffs.mark.apply(g.magnitude, g.turns)
            case .shield:  combatBuffs.shield += Int(g.magnitude)
            case .heal:    healLowestAlly(Int(g.magnitude))
            case .ultEnergy:
                for h in activeTeam {
                    let req = h.abilities.first { $0.kind == .ultimate }?.ultimateChargeRequired ?? 4
                    ultimateCharge[h.id] = min(req, (ultimateCharge[h.id] ?? 0) + Int(g.magnitude))
                }
            }
        }
    }

    /// Restore HP to the lowest living ally (campaign only).
    private func healLowestAlly(_ amount: Int) {
        guard battleMode == .campaign, amount > 0 else { return }
        let living = activeTeam.filter { (heroHP[$0.id] ?? $0.hp) > 0 }
        guard let target = living.min(by: {
            (heroHP[$0.id] ?? $0.hp) < (heroHP[$1.id] ?? $1.hp)
        }) else { return }
        heroHP[target.id] = min(target.hp, (heroHP[target.id] ?? target.hp) + amount)
    }

    private func resetCombatFlow() {
        currentCard = battleMode == .campaign ? 1 : 0
        reviewedCards = 0
        streak = 0
        activeHeroIndex = 0
        lastActorIndex = 0
        lastAbility = nil
        visualAbility = nil
        visualEffectToken = 0
        lastDamage = 0
        pendingRating = nil
        choosingAbility = false
        captureOffer = nil
        offeredThisRun = []
        combatBuffs = CombatBuffs()
        skillCooldown = [:]
        ultimateCharge = Dictionary(uniqueKeysWithValues: activeTeam.map { ($0.id, 0) })
        if ProcessInfo.processInfo.arguments.contains("-uitestUltReady") {
            ultimateCharge = Dictionary(uniqueKeysWithValues: activeTeam.map { hero in
                let required = hero.abilities.first { $0.kind == .ultimate }?.ultimateChargeRequired ?? 4
                return (hero.id, required)
            })
        }
        turnEngine.reset(activeTeam)
        activeHeroIndex = currentTurnIndex()
        showingAnswer = false
    }

    /// Average level of the active team, used to scale enemy difficulty.
    private var teamLevel: Int {
        let levels = activeTeam.map(\.level)
        return levels.isEmpty ? 10 : levels.reduce(0, +) / levels.count
    }

    /// First living hero at or after `index` (campaign skips downed heroes).
    private func nextLivingHeroIndex(after index: Int) -> Int {
        let n = activeTeam.count
        guard n > 0 else { return 0 }
        for offset in 1...n {
            let i = (index + offset) % n
            if (heroHP[activeTeam[i].id] ?? 0) > 0 { return i }
        }
        return index
    }

    private func grade(_ rating: BattleRating) {
        guard session.current != nil else { return }
        AudioManager.shared.play(rating.gradeSound)
        Haptics.select()
        pendingRating = rating
        choosingAbility = true

        if let activeHero {
            let required = activeHero.abilities.first { $0.kind == .ultimate }?.ultimateChargeRequired ?? 4
            ultimateCharge[activeHero.id] = min(required, (ultimateCharge[activeHero.id] ?? 0) + 1)
        }

        // Auto-battle: skip the manual ability pick and fire the best option.
        if autoMode, let ability = autoChosenAbility() {
            autoCast(ability)
        }
    }

    /// The ability auto-battle should cast for the active hero, following the
    /// priority ultimate (if charged) → skill (if off cooldown) → basic.
    private func autoChosenAbility() -> BattleAbility? {
        guard let hero = activeHero else { return nil }
        let abilities = hero.abilities
        if let ult = abilities.first(where: { $0.kind == .ultimate }) {
            let required = ult.ultimateChargeRequired ?? 4
            if (ultimateCharge[hero.id] ?? 0) >= required { return ult }
        }
        if let skill = abilities.first(where: { $0.kind == .skill }),
           (skillCooldown[hero.id] ?? 0) == 0 {
            return skill
        }
        return abilities.first { $0.kind == .basic }
            ?? abilities.first { $0.kind == .skill }
            ?? abilities.first
    }

    /// Fire an auto-selected ability after a short beat so the player still
    /// registers the grade and sees the cast land.
    private func autoCast(_ ability: BattleAbility) {
        let castRating = pendingRating
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            // Bail if the flow moved on (manual tap, auto toggled off, new card).
            guard autoMode, choosingAbility, pendingRating == castRating else { return }
            useAbility(ability)
        }
    }

    private func useAbility(_ ability: BattleAbility) {
        guard let rating = pendingRating else { return }
        // Schedule the current card with FSRS and persist before advancing.
        session.grade(rating.fsrs)
        // Endless review loops forever: rebuild the queue once it drains.
        if session.current == nil {
            session.start(deckIDs: selectedDecks, tags: selectedTags)
        }

        let boundedIndex = min(max(activeHeroIndex, 0), max(activeTeam.count - 1, 0))
        if ability.kind == .ultimate, activeTeam.indices.contains(boundedIndex) {
            ultimateCharge[activeTeam[boundedIndex].id] = 0
        }

        // Damage scales with team level, the team ATK buff, and the enemy MARK.
        let damageMult = BattleScaling.heroDamageMultiplier(teamLevel: teamLevel)
        let buffed = Double(ability.damage) * damageMult
            * combatBuffs.damageMultiplier * combatBuffs.markMultiplier
        // Pure-support abilities (Cristae Surge, Present Antigen) deal no damage.
        let damage = ability.dealsDamage ? max(1, Int(buffed)) : 0
        let enemyDefeated = ability.dealsDamage && (mobHP - damage <= 0)
        // End of turn: existing buffs tick down, then this ability's grants apply.
        combatBuffs.tickAll()
        applyGrants(ability)
        // Skill cooldown: every answered card ticks all cooldowns down; casting
        // a skill benches that hero's skill for `cooldownTurns` more cards.
        let actorId = activeTeam[boundedIndex].id
        for hero in activeTeam {
            skillCooldown[hero.id] = max(0, (skillCooldown[hero.id] ?? 0) - 1)
        }
        if ability.kind == .skill {
            skillCooldown[actorId] = ability.cooldownTurns
        }
        // Drive the combat juice (hit flash, shake, floating number, lunge).
        lastDamage = damage
        lastActorIndex = boundedIndex
        lastAbility = ability
        if ability.kind != .basic {
            visualAbility = ability
            visualEffectToken += 1
            let token = visualEffectToken
            let isUITestHold = ProcessInfo.processInfo.arguments.contains("-uitestHoldAbilityEffects")
                || ProcessInfo.processInfo.arguments.contains("-uitestSlowAbilityEffects")
            let duration: TimeInterval = isUITestHold ? 8.0 : 0.95
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                if !isUITestHold, visualEffectToken == token {
                    visualAbility = nil
                }
                if !isUITestHold, lastAbility?.id == ability.id {
                    lastAbility = nil
                }
            }
        } else {
            visualAbility = nil
        }
        attackToken += 1
        mobHP = max(0, mobHP - damage)
        reviewedCards += 1
        streak = battleMode == .endless ? streak + 1 : (rating == .again ? 0 : streak + 1)
        currentCard += 1
        showingAnswer = false
        pendingRating = nil
        choosingAbility = false

        // Campaign only: recoil hits the active hero; the team is defeated when
        // all three are down. Endless has no player HP and never fails.
        var teamDefeated = false
        if battleMode == .campaign {
            // DEF buff reduces recoil; a team SHIELD absorbs the rest first.
            var recoil = Int(Double(rating.recoil) * selectedStage.tierMultiplier
                             * combatBuffs.recoilMultiplier)
            if combatBuffs.shield > 0, recoil > 0 {
                let absorbed = min(combatBuffs.shield, recoil)
                combatBuffs.shield -= absorbed
                recoil -= absorbed
            }
            if recoil > 0, activeTeam.indices.contains(boundedIndex) {
                let id = activeTeam[boundedIndex].id
                heroHP[id] = max(0, (heroHP[id] ?? 0) - recoil)
            }
            advanceTurn(after: boundedIndex)
            teamDefeated = activeTeam.allSatisfy { (heroHP[$0.id] ?? 0) <= 0 }
        } else {
            advanceTurn(after: boundedIndex)
        }

        let modeName = battleMode == .endless ? "endless" : "campaign"
        Task {
            await MitoBackend.shared.logEvent("review_graded", props: [
                "rating": rating.title, "mode": modeName, "damage": "\(damage)",
                "ability": ability.id, "ability_kind": ability.kind.rawValue
            ])
        }

        if battleMode == .endless, enemyDefeated {
            DailyQuests.shared.noteBattleWon()
            // Wild encounter: offer to capture the creature you just beat.
            offerCaptureIfWild()
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
            // Outcome sting (delayed slightly so the finishing hit lands first).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                AudioManager.shared.play(enemyDefeated ? .victory : .defeat, volume: 0.9)
            }
            if teamDefeated { Haptics.warning() } else { Haptics.success() }
            // Campaign progression: clearing a stage unlocks the next one.
            if battleMode == .campaign, enemyDefeated {
                DailyQuests.shared.noteBattleWon()
                clearedStage = max(clearedStage, selectedStage.id)
                offerCaptureIfWild()
            }
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
        let team = BattleRules.partyHeroes
        let boundedIndex = min(max(activeHeroIndex, 0), max(team.count - 1, 0))
        let hero = team[boundedIndex]
        let ability = BattleAbilityBook.abilities(for: hero).randomElement()
            ?? BattleAbility(id: "fallback", name: "Study Strike", kind: .basic, damage: 28, detail: "A steady review strike lands.", theme: "Study", animationKey: "tap", color: hero.color, energyCost: nil, ultimateChargeRequired: nil)
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

struct BattleAbilityEffectView: View {
    let ability: BattleAbility
    let scale: CGFloat
    let opacity: Double
    let rotation: Double

    var body: some View {
        ZStack {
            if Self.spriteSheetAnimationKeys.contains(ability.animationKey) {
                SpriteSheetAbilityEffect(asset: ability.animationKey, frameCount: 8, frameSize: CGSize(width: 200, height: 128))
            } else {
                switch ability.animationKey {
            case "beam":
                BeamEffect(color: ability.color)
            case "bloom":
                BloomEffect(color: ability.color)
            case "network", "network-burst":
                NetworkEffect(color: ability.color, intense: ability.kind == .ultimate)
            case "mark":
                MarkEffect(color: ability.color)
            case "rally":
                RallyEffect(color: ability.color)
            case "shield":
                ShieldEffect(color: ability.color)
            case "storm":
                StormEffect(color: ability.color)
            case "burst":
                BurstEffect(color: ability.color, intense: true)
            case "pulse":
                PulseEffect(color: ability.color)
            default:
                BurstEffect(color: ability.color, intense: ability.kind == .ultimate)
                }
            }
        }
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation))
        .opacity(opacity)
        .blendMode(.plusLighter)
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
}

struct SpriteSheetAbilityEffect: View {
    let asset: String
    let frameCount: Int
    let frameSize: CGSize
    @State private var frameIndex = 0

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / frameSize.width, proxy.size.height / frameSize.height)
            Image(asset)
                .resizable()
                .interpolation(.none)
                .frame(width: frameSize.width * CGFloat(frameCount) * scale, height: frameSize.height * scale, alignment: .leading)
                .offset(x: -CGFloat(frameIndex) * frameSize.width * scale)
                .frame(width: frameSize.width * scale, height: frameSize.height * scale, alignment: .leading)
                .clipped()
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .onAppear {
            frameIndex = 0
            for index in 1..<frameCount {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.065) {
                    frameIndex = index
                }
            }
        }
    }
}

struct PulseEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(color.opacity(0.95 - Double(index) * 0.2), lineWidth: CGFloat(7 - index * 2))
                    .frame(width: CGFloat(64 + index * 34), height: CGFloat(64 + index * 34))
            }
            Circle()
                .fill(Color(hex: "FFF1A8").opacity(0.42))
                .frame(width: 34, height: 34)
        }
    }
}

struct BeamEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            Capsule()
                .fill(color.opacity(0.82))
                .frame(width: 178, height: 18)
                .rotationEffect(.degrees(-10))
            Capsule()
                .fill(Color.white.opacity(0.74))
                .frame(width: 138, height: 7)
                .rotationEffect(.degrees(-10))
            PixelSpark(color: color)
                .offset(x: 78, y: -16)
        }
    }
}

struct BloomEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? color.opacity(0.82) : Color(hex: "FFF1A8").opacity(0.76))
                    .frame(width: 24, height: 78)
                    .offset(y: -50)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle()
                .fill(Color.white.opacity(0.52))
                .frame(width: 46, height: 46)
        }
    }
}

struct NetworkEffect: View {
    let color: Color
    let intense: Bool

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 36, y: 104))
                path.addLine(to: CGPoint(x: 88, y: 48))
                path.addLine(to: CGPoint(x: 136, y: 82))
                path.addLine(to: CGPoint(x: 174, y: 34))
                path.move(to: CGPoint(x: 88, y: 48))
                path.addLine(to: CGPoint(x: 112, y: 150))
                path.addLine(to: CGPoint(x: 164, y: 118))
                path.move(to: CGPoint(x: 36, y: 104))
                path.addLine(to: CGPoint(x: 112, y: 150))
            }
            .stroke(color.opacity(0.86), style: StrokeStyle(lineWidth: intense ? 7 : 5, lineCap: .square, lineJoin: .round))
            .frame(width: 210, height: 180)

            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.78) : color.opacity(0.9))
                    .frame(width: intense ? 18 : 13, height: intense ? 18 : 13)
                    .position(networkPoint(index))
            }
        }
        .frame(width: 210, height: 180)
    }

    private func networkPoint(_ index: Int) -> CGPoint {
        let points = [
            CGPoint(x: 36, y: 104), CGPoint(x: 88, y: 48), CGPoint(x: 136, y: 82),
            CGPoint(x: 174, y: 34), CGPoint(x: 112, y: 150), CGPoint(x: 164, y: 118)
        ]
        return points[index % points.count]
    }
}

struct MarkEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 7)
                .frame(width: 106, height: 106)
            Rectangle()
                .fill(color)
                .frame(width: 140, height: 8)
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 140)
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 20, height: 20)
        }
    }
}

struct RallyEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? color : Color(hex: "FFF1A8"))
                    .frame(width: 10, height: 46)
                    .offset(y: -72)
                    .rotationEffect(.degrees(Double(index) * 36))
            }
            MarkEffect(color: color)
                .scaleEffect(0.72)
        }
    }
}

struct ShieldEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .stroke(color.opacity(0.9), lineWidth: 9)
                .frame(width: 134, height: 154)
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.6), lineWidth: 4)
                .frame(width: 96, height: 116)
            PixelSpark(color: color)
                .offset(x: 58, y: -52)
        }
    }
}

struct StormEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                LightningBolt()
                    .fill(index.isMultiple(of: 2) ? color : Color.white.opacity(0.82))
                    .frame(width: 38, height: 112)
                    .offset(x: CGFloat(index - 2) * 34, y: CGFloat(index % 2) * 18)
                    .rotationEffect(.degrees(Double(index * 8 - 12)))
            }
        }
    }
}

struct BurstEffect: View {
    let color: Color
    let intense: Bool

    var body: some View {
        ZStack {
            ForEach(0..<(intense ? 14 : 9), id: \.self) { index in
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? color : Color(hex: "FFF1A8"))
                    .frame(width: intense ? 12 : 9, height: intense ? 92 : 62)
                    .offset(y: intense ? -82 : -58)
                    .rotationEffect(.degrees(Double(index) * (intense ? 25.7 : 40)))
            }
            Circle()
                .fill(color.opacity(0.58))
                .frame(width: intense ? 98 : 64, height: intense ? 98 : 64)
            Circle()
                .fill(Color.white.opacity(0.72))
                .frame(width: intense ? 44 : 28, height: intense ? 44 : 28)
        }
    }
}

struct PixelSpark: View {
    let color: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(color)
                .frame(width: 28, height: 8)
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 28)
            Rectangle()
                .fill(Color.white.opacity(0.75))
                .frame(width: 8, height: 8)
        }
    }
}

struct LightningBolt: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.midY * 0.92))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.midY * 0.92))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.22, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.02, y: rect.midY * 1.12))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.28, y: rect.midY * 1.12))
        path.closeSubpath()
        return path
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
    var allowManualReveal: Bool = true
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

            if !showingAnswer && allowManualReveal {
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

// MARK: - Multiple-choice answer panel

/// Multiple-choice answering: tap an option, see correct/wrong, and a grade is
/// derived from correctness + speed (no AI needed at review time). Re-created per
/// card via `.id(cardID)`, so its timer and selection reset each card.
struct MultipleChoicePanel: View {
    let options: [String]
    let correctAnswer: String
    let onReveal: () -> Void
    let onResolved: (BattleRating) -> Void

    @State private var start = Date()
    @State private var selected: String?
    @State private var resolved = false

    private func isCorrect(_ option: String) -> Bool {
        AnswerGrading.normalize(option) == AnswerGrading.normalize(correctAnswer)
    }

    private func background(for option: String) -> Color {
        guard resolved else { return Color(hex: "6B4324") }
        if isCorrect(option) { return Color(hex: "4A9B3F") }            // always reveal the right one
        if option == selected { return Color(hex: "C84535") }           // your wrong pick
        return Color(hex: "6B4324").opacity(0.5)
    }

    private func tap(_ option: String) {
        guard !resolved else { return }
        selected = option
        resolved = true
        let correct = isCorrect(option)
        onReveal()
        AudioManager.shared.play(correct ? .gradeGood : .gradeAgain)
        Haptics.select()
        let rating = BattleRating(AnswerGrading.multipleChoiceRating(
            correct: correct, elapsed: Date().timeIntervalSince(start)))
        // Hold the correct/wrong reveal briefly before handing off to the ability row.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { onResolved(rating) }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button { tap(option) } label: {
                    Text(option)
                        .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 8)
                        .background(background(for: option))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(resolved)
            }
        }
    }
}

// MARK: - Type-in answer panel

/// Type-in answering: the player types a free answer; the AI grader (with a
/// local-similarity fallback) turns it into a battle grade. Tracks timing and
/// hesitation signals to feed the grader. Re-created per card via `.id(cardID)`.
struct TypeInPanel: View {
    let correctAnswer: String
    let onReveal: () -> Void
    let grade: (String, TypingSignals) async -> (BattleRating, String?)
    let onResolved: (BattleRating) -> Void

    @State private var text = ""
    @State private var start = Date()
    @State private var firstKeystroke: Date?
    @State private var deletions = 0
    @State private var keystrokes = 0
    @State private var lastLength = 0
    @State private var grading = false
    @State private var feedback: String?
    @FocusState private var focused: Bool

    private func track(_ newValue: String) {
        if firstKeystroke == nil && !newValue.isEmpty { firstKeystroke = Date() }
        let delta = newValue.count - lastLength
        if delta > 0 { keystrokes += delta } else if delta < 0 { deletions += -delta }
        lastLength = newValue.count
    }

    private func submit() {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, !grading else { return }
        grading = true
        focused = false
        onReveal()
        let now = Date()
        let signals = TypingSignals(
            elapsedMs: Int(now.timeIntervalSince(start) * 1000),
            timeToFirstKeystrokeMs: Int((firstKeystroke ?? now).timeIntervalSince(start) * 1000),
            deletions: deletions,
            keystrokes: keystrokes)
        Task {
            let (rating, fb) = await grade(answer, signals)
            await MainActor.run {
                feedback = fb
                grading = false
                AudioManager.shared.play(rating.gradeSound)
                Haptics.select()
            }
            // Let the player read the AI feedback before the ability row takes over.
            try? await Task.sleep(nanoseconds: fb == nil ? 600_000_000 : 1_400_000_000)
            await MainActor.run { onResolved(rating) }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let feedback {
                Text(feedback)
                    .font(.custom(MitoFont.regular, size: 14))
                    .foregroundStyle(Color(hex: "F4E6C0"))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(hex: "2A1A0D").opacity(0.85))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }

            TextField("", text: $text, prompt: Text("Type your answer…").foregroundColor(Color(hex: "8A6B42")))
                .font(.custom(MitoFont.regular, size: 16))
                .foregroundStyle(Color(hex: "3A2A18"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .disabled(grading)
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                .onChange(of: text) { _, newValue in track(newValue) }
                .onSubmit(submit)

            Button(action: submit) {
                Text(grading ? "CHECKING…" : "SUBMIT")
                    .pixelText(size: 16, color: Color(hex: "F4E6C0"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(hex: "4A9B3F"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
            .disabled(grading || text.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(grading || text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
        }
        .onAppear { focused = true }
    }
}

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
                Text("A WILD \(creature.name.uppercased()) APPEARED!")
                    .pixelText(size: 12, color: Color(hex: "FFD24D"))
                    .multilineTextAlignment(.center)

                SpriteView(asset: creature.asset, size: 92)
                    .padding(10)
                    .background(creature.color.opacity(0.25))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                Text(creature.role.uppercased() + " · LV \(creature.level)")
                    .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                Text(creature.lore)
                    .font(.custom(MitoFont.regular, size: 14))
                    .foregroundStyle(Color(hex: "E9D8B6"))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    Button(action: onRelease) {
                        Text("LET GO")
                            .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)

                    Button(action: onCapture) {
                        Text("✦ CAPTURE")
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

struct CampaignStageSetup: View {
    let stage: Stage
    let decks: [Deck]
    @Binding var selectedDecks: Set<String>
    @Binding var selectedTags: Set<String>
    @Binding var answerMode: AnswerMode
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
                    SpriteView(asset: "wild-spikevyrus-hop", size: 58)
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

                AnswerModePicker(answerMode: $answerMode)

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
    @Binding var answerMode: AnswerMode
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

                AnswerModePicker(answerMode: $answerMode)

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
/// Lets the player choose how they answer cards this session: classic
/// self-grade, multiple-choice, or type-in.
struct AnswerModePicker: View {
    @Binding var answerMode: AnswerMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANSWER MODE")
                .pixelText(size: 10, color: Color(hex: "F4E6C0"))
            HStack(spacing: 6) {
                ForEach(AnswerMode.selectable, id: \.self) { mode in
                    let on = mode == answerMode
                    Button {
                        answerMode = mode
                        Haptics.tap()
                    } label: {
                        Text(mode.shortTitle)
                            .pixelText(size: 10, color: on ? Color(hex: "1A130A") : Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(on ? Color(hex: "FFD24D") : Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

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
