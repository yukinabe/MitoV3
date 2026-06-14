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
    /// A base hero recruited after beating their campaign boss.
    @State private var recruitOffer: Hero?
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

            if let hero = recruitOffer {
                RecruitPopup(
                    hero: hero,
                    onJoin: {
                        RosterStore.shared.unlock(hero.id)
                        AudioManager.shared.play(.victory, volume: 0.85)
                        Haptics.success()
                        recruitOffer = nil
                    }
                )
                .zIndex(55)
            }
        }
        .onAppear(perform: maybeJumpToReviewForUITest)
    }

    /// The base hero recruited by clearing the selected campaign stage, if it's a
    /// recruit stage and the player hasn't already unlocked them.
    private var campaignRecruitHero: Hero? {
        guard let id = CampaignRecruits.heroID(forStage: selectedStage.id),
              !RosterStore.shared.isOwned(id) else { return nil }
        return DataSet.anyHero(id: id)
    }

    /// The boss hero a campaign stage is fought against (drives the enemy sprite/
    /// name). Recruit stages show the joinable hero until they're recruited; after
    /// that the stage reverts to a generic Spikevyrus fight so the enemy you see
    /// matches the capture you're offered on a replay.
    private var campaignBossHeroID: String? {
        guard let id = CampaignRecruits.heroID(forStage: selectedStage.id),
              !RosterStore.shared.isOwned(id) else { return nil }
        return id
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
                        TutorialManager.shared.complete("battle.endless")
                        route = .reviewSetup
                    } label: {
                        FeatureButton(title: "ENDLESS REVIEW", badge: "RECOMMENDED", detail: "No limits · no ATP · earn gold, XP & recruits", tint: Color(hex: "4A8A3C"), height: 100)
                    }
                    .buttonStyle(.plain)
                    .tutorialAnchor("battle.endless")
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
                TutorialManager.shared.complete("battle.startEndless")
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
            bossOverrideID: battleMode == .campaign ? campaignBossHeroID : nil,
            stageLabel: "STAGE \(selectedStage.id) · \(selectedStage.difficulty)",
            autoMode: autoMode,
            answerMode: answerMode,
            answerCardID: session.current?.id,
            mcOptions: session.current.map(answerOptions(for:)) ?? [],
            onReveal: {
                showingAnswer = true
                AudioManager.shared.play(.cardShow)
                Haptics.tap()
                TutorialManager.shared.complete("battle.showAnswer")
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
        TutorialManager.shared.complete("battle.grade")

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
        TutorialManager.shared.complete("battle.ability")
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
                // Recruit-stage bosses join the team; other stages may drop a
                // capturable wild creature instead.
                if let hero = campaignRecruitHero {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { recruitOffer = hero }
                } else {
                    offerCaptureIfWild()
                }
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

