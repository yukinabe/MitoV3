import Foundation

// MARK: - FSRS-6
//
// A from-scratch Swift port of the FSRS-6 scheduling algorithm used by Anki
// (open-spaced-repetition/fsrs-rs). This is an independent implementation of
// the published formulas + the shipping default weights — no GPL source is
// copied. References:
//   • https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm
//   • https://github.com/open-spaced-repetition/fsrs-rs
//
// The model tracks two latent variables per card:
//   • Stability  (S): days until retrievability decays to `desiredRetention`.
//   • Difficulty (D): how hard the card is, on a 1...10 scale.
// and a forgetting curve R(t, S) giving the probability of recall after t days.

/// A grade the learner gives after seeing the answer. Raw values match FSRS
/// (1...4) and map 1:1 onto the existing Again/Hard/Good/Easy battle buttons.
public enum Rating: Int, Codable, CaseIterable, Sendable {
    case again = 1
    case hard  = 2
    case good  = 3
    case easy  = 4
}

/// Lifecycle phase of a card. FSRS itself only needs S and D, but the phase
/// lets us decide between the long-term and same-day ("short-term") stability
/// updates, and drives learning/relearning steps.
public enum CardPhase: Int, Codable, Sendable {
    case new        // never reviewed
    case learning   // in initial learning steps (same-day)
    case review     // graduated, scheduled in days
    case relearning // lapsed, back in steps
}

/// The two latent memory variables for a card.
public struct MemoryState: Codable, Equatable, Sendable {
    public var stability: Double   // S, in days
    public var difficulty: Double  // D, in 1...10

    public init(stability: Double, difficulty: Double) {
        self.stability = stability
        self.difficulty = difficulty
    }
}

/// Everything the scheduler needs to persist for one card. Backend-agnostic:
/// store these fields on `MitoCardRecord`, SwiftData, or anything else.
public struct SchedulingState: Codable, Equatable, Sendable {
    public var memory: MemoryState?   // nil until the first review
    public var phase: CardPhase
    public var due: Date              // when the card is next owed
    public var lastReview: Date?      // when it was last graded
    public var reps: Int              // total successful-or-not reviews
    public var lapses: Int            // times graded `again` while in review

    public init(
        memory: MemoryState? = nil,
        phase: CardPhase = .new,
        due: Date = .distantPast,
        lastReview: Date? = nil,
        reps: Int = 0,
        lapses: Int = 0
    ) {
        self.memory = memory
        self.phase = phase
        self.due = due
        self.lastReview = lastReview
        self.reps = reps
        self.lapses = lapses
    }

    /// A brand-new, never-seen card that is due immediately.
    public static func newCard(due: Date = Date()) -> SchedulingState {
        SchedulingState(phase: .new, due: due)
    }
}

/// The outcome of grading a card: the new persistent state plus the interval
/// (in days) that was chosen, for display ("see again in 4d").
public struct ReviewResult: Sendable {
    public let state: SchedulingState
    public let intervalDays: Double
}

public struct FSRS {

    // MARK: Parameters

    /// The 21 FSRS-6 default weights shipped by fsrs-rs / Anki
    /// (`DEFAULT_PARAMETERS`, w[20] = `FSRS6_DEFAULT_DECAY` = 0.1542).
    public static let defaultParameters: [Double] = [
        0.212,  1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
        1.8722, 0.1666, 0.796,  1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
        1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ]

    public let w: [Double]
    /// Target probability of recall when a card comes due (Anki default 0.9).
    public let desiredRetention: Double
    public let maximumIntervalDays: Double

    private let decay: Double
    private let factor: Double

    // FSRS clamps both variables to keep the math well-behaved.
    private static let minStability = 0.01
    private static let minDifficulty = 1.0
    private static let maxDifficulty = 10.0

    public init(
        parameters: [Double] = FSRS.defaultParameters,
        desiredRetention: Double = 0.9,
        maximumIntervalDays: Double = 36500
    ) {
        precondition(parameters.count >= 21, "FSRS-6 needs 21 parameters")
        self.w = parameters
        self.desiredRetention = desiredRetention
        self.maximumIntervalDays = maximumIntervalDays
        // decay = -w20 ; factor chosen so that R(S, S) == 0.9.
        self.decay = -parameters[20]
        self.factor = pow(0.9, 1.0 / self.decay) - 1.0
    }

    // MARK: Forgetting curve

    /// Probability of recall t days after the last review, given stability S.
    /// R(t, S) = (1 + factor · t/S)^decay, with R(S, S) = 0.9.
    public func retrievability(elapsedDays t: Double, stability s: Double) -> Double {
        guard s > 0 else { return 0 }
        return pow(1.0 + factor * max(0, t) / s, decay)
    }

    /// Days until stability `s` decays to `desiredRetention`.
    /// Inverse of the forgetting curve solved for t.
    public func interval(forStability s: Double) -> Double {
        let raw = (s / factor) * (pow(desiredRetention, 1.0 / decay) - 1.0)
        return min(max(raw, 1.0), maximumIntervalDays)
    }

    // MARK: Initial values (first-ever review)

    /// S0(G) = w[G-1]
    public func initialStability(_ rating: Rating) -> Double {
        clampStability(w[rating.rawValue - 1])
    }

    /// D0(G) = w4 − e^(w5·(G−1)) + 1, clamped to 1...10.
    public func initialDifficulty(_ rating: Rating) -> Double {
        let g = Double(rating.rawValue)
        return clampDifficulty(w[4] - exp(w[5] * (g - 1.0)) + 1.0)
    }

    // MARK: Difficulty update

    /// Next difficulty with linear damping + mean reversion toward D0(easy).
    public func nextDifficulty(_ d: Double, rating: Rating) -> Double {
        let g = Double(rating.rawValue)
        let deltaD = -w[6] * (g - 3.0)
        // linear damping: changes shrink as difficulty approaches 10.
        let damped = d + deltaD * (10.0 - d) / 9.0
        // mean reversion toward the difficulty an "easy" first answer implies.
        let reverted = w[7] * initialDifficulty(.easy) + (1.0 - w[7]) * damped
        return clampDifficulty(reverted)
    }

    // MARK: Stability update — long term (>= 1 day since last review)

    /// Stability after a successful recall (hard/good/easy).
    public func stabilityAfterRecall(
        difficulty d: Double,
        stability s: Double,
        retrievability r: Double,
        rating: Rating
    ) -> Double {
        let hardPenalty = (rating == .hard) ? w[15] : 1.0
        let easyBonus   = (rating == .easy) ? w[16] : 1.0
        let growth = exp(w[8])
            * (11.0 - d)
            * pow(s, -w[9])
            * (exp(w[10] * (1.0 - r)) - 1.0)
            * hardPenalty
            * easyBonus
        return clampStability(s * (1.0 + growth))
    }

    /// Stability after a lapse (`again`). FSRS-6 caps the post-lapse stability
    /// at S / e^(w17·w18) — a short-term-aware ceiling, not simply the old S.
    public func stabilityAfterForget(
        difficulty d: Double,
        stability s: Double,
        retrievability r: Double
    ) -> Double {
        let sf = w[11]
            * pow(d, -w[12])
            * (pow(s + 1.0, w[13]) - 1.0)
            * exp(w[14] * (1.0 - r))
        let ceiling = s / exp(w[17] * w[18])
        return clampStability(min(sf, ceiling))
    }

    // MARK: Stability update — short term (same-day reviews / learning steps)

    /// S'(S, G) = S · e^(w17·(G − 3 + w18)) · S^(−w19)
    public func shortTermStability(_ s: Double, rating: Rating) -> Double {
        let g = Double(rating.rawValue)
        let sinc = exp(w[17] * (g - 3.0 + w[18])) * pow(s, -w[19])
        // Successful same-day grades never shrink stability.
        let bounded = rating == .again ? sinc : max(sinc, 1.0)
        return clampStability(s * bounded)
    }

    // MARK: The scheduler entry point

    /// Grade a card and produce its next scheduling state.
    ///
    /// - Parameters:
    ///   - state: the card's current persisted state.
    ///   - rating: the learner's grade.
    ///   - now: the review timestamp (injectable for tests).
    public func review(_ state: SchedulingState, rating: Rating, now: Date = Date()) -> ReviewResult {
        let elapsedDays: Double = {
            guard let last = state.lastReview else { return 0 }
            return max(0, now.timeIntervalSince(last) / 86_400)
        }()

        var next = state
        next.reps += 1
        next.lastReview = now

        let newMemory: MemoryState

        if let memory = state.memory {
            // Returning card: pick short- vs long-term update.
            let d = nextDifficulty(memory.difficulty, rating: rating)
            let s: Double
            if elapsedDays < 1.0 {
                // Same-day repeat (still in steps): short-term formula.
                s = shortTermStability(memory.stability, rating: rating)
            } else {
                let r = retrievability(elapsedDays: elapsedDays, stability: memory.stability)
                s = rating == .again
                    ? stabilityAfterForget(difficulty: d, stability: memory.stability, retrievability: r)
                    : stabilityAfterRecall(difficulty: d, stability: memory.stability, retrievability: r, rating: rating)
            }
            newMemory = MemoryState(stability: s, difficulty: d)
        } else {
            // First-ever review: seed S and D from the grade.
            newMemory = MemoryState(
                stability: initialStability(rating),
                difficulty: initialDifficulty(rating)
            )
        }

        next.memory = newMemory

        // Phase + lapse bookkeeping.
        let wasReviewPhase = (state.phase == .review)
        switch rating {
        case .again:
            if wasReviewPhase { next.lapses += 1 }
            next.phase = .relearning
        case .hard, .good, .easy:
            next.phase = .review
        }

        let days = interval(forStability: newMemory.stability)
        // Round to whole days for graduated cards; schedule from `now`.
        let scheduledDays = max(1.0, days.rounded())
        next.due = now.addingTimeInterval(scheduledDays * 86_400)

        return ReviewResult(state: next, intervalDays: scheduledDays)
    }

    /// Preview the interval each grade would produce, e.g. to label the four
    /// answer buttons with "1d / 3d / 8d / 21d".
    public func previewIntervals(for state: SchedulingState, now: Date = Date()) -> [Rating: Double] {
        var out: [Rating: Double] = [:]
        for rating in Rating.allCases {
            out[rating] = review(state, rating: rating, now: now).intervalDays
        }
        return out
    }

    // MARK: Clamping helpers

    private func clampStability(_ s: Double) -> Double {
        s.isFinite ? max(Self.minStability, s) : Self.minStability
    }

    private func clampDifficulty(_ d: Double) -> Double {
        guard d.isFinite else { return Self.minDifficulty }
        return min(Self.maxDifficulty, max(Self.minDifficulty, d))
    }
}

// MARK: - Review cards & persistence
//
// A `ReviewCard` is one flashcard plus its per-learner FSRS scheduling state.
// `ReviewSession` is the live queue the battle/review UI drives: it serves the
// next due card, applies a grade through `FSRS`, persists the new state, and
// advances. Persistence is local-first (a JSON file in Application Support) so
// the scheduler works offline and survives relaunches with no backend. A
// remote sync hook (`onPersist`) lets `MitoBackend` mirror state to Supabase.

import Combine

public struct ReviewCard: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var deckID: String
    public var deckName: String
    public var front: String
    public var back: String
    public var tags: [String]
    public var sched: SchedulingState
    /// Cached multiple-choice distractors (wrong answers only — the correct
    /// answer is `back`). AI-generated once and persisted; nil/empty means none
    /// generated yet, in which case the UI falls back to sibling-card answers.
    public var choices: [String]?

    public init(
        id: UUID,
        deckID: String,
        deckName: String = "",
        front: String,
        back: String,
        tags: [String] = [],
        sched: SchedulingState = .newCard(),
        choices: [String]? = nil
    ) {
        self.id = id
        self.deckID = deckID
        self.deckName = deckName
        self.front = front
        self.back = back
        self.tags = tags
        self.sched = sched
        self.choices = choices
    }
}

// MARK: - Answer modes
//
// How the player answers a card in battle. All three modes converge on the same
// FSRS `Rating` and feed `ReviewSession.grade(_:)` — only the way the rating is
// *derived* differs.

/// The way a card is answered during a battle/review session.
public enum AnswerMode: String, CaseIterable, Codable, Sendable {
    case classic        // reveal the answer, self-grade Again/Hard/Good/Easy
    case multipleChoice // RETIRED: kept for back-compat with saved prefs; not selectable
    case typeIn         // "Quiz": type the answer; AI compares it to `back` → rating

    /// Modes the player can actually pick. Multiple-choice was retired (long
    /// answers didn't fit), so only two ship; the enum case stays for decoding
    /// any previously-saved preference, which falls back to `.classic`.
    public static var selectable: [AnswerMode] { [.classic, .typeIn] }

    public var title: String {
        switch self {
        case .classic: "CLASSIC"
        case .multipleChoice: "MULTIPLE CHOICE"
        case .typeIn: "QUIZ"
        }
    }

    public var shortTitle: String {
        switch self {
        case .classic: "CLASSIC"
        case .multipleChoice: "CHOICE"
        case .typeIn: "QUIZ"
        }
    }

    public var icon: String {
        switch self {
        case .classic: "rectangle.on.rectangle"
        case .multipleChoice: "list.bullet"
        case .typeIn: "keyboard"
        }
    }
}

/// Behavioural signals captured while the player types an answer, sent to the AI
/// grader as secondary evidence of recall confidence.
public struct TypingSignals: Codable, Sendable {
    public var elapsedMs: Int            // reveal → submit, total
    public var timeToFirstKeystrokeMs: Int
    public var deletions: Int            // backspaces / corrections
    public var keystrokes: Int           // total characters typed (incl. deleted)

    public init(elapsedMs: Int = 0, timeToFirstKeystrokeMs: Int = 0, deletions: Int = 0, keystrokes: Int = 0) {
        self.elapsedMs = elapsedMs
        self.timeToFirstKeystrokeMs = timeToFirstKeystrokeMs
        self.deletions = deletions
        self.keystrokes = keystrokes
    }
}

/// First-pass, tunable mapping from answer performance to an FSRS `Rating`.
/// Centralised so thresholds are easy to retune as we gather data.
public enum AnswerGrading {
    // Multiple-choice speed thresholds (seconds), applied only when correct.
    public static let mcEasyUnderSeconds: Double = 3
    public static let mcGoodUnderSeconds: Double = 7

    /// Multiple-choice rating: a wrong pick is always `.again`; a correct pick is
    /// graded by how quickly it was chosen.
    public static func multipleChoiceRating(correct: Bool, elapsed: TimeInterval) -> Rating {
        guard correct else { return .again }
        if elapsed <= mcEasyUnderSeconds { return .easy }
        if elapsed <= mcGoodUnderSeconds { return .good }
        return .hard
    }

    /// Offline fallback for type-in mode when the AI grader is unavailable.
    /// Normalises both strings and scores token-overlap similarity → a rating.
    public static func localSimilarityRating(expected: String, answer: String) -> Rating {
        let e = normalize(expected)
        let a = normalize(answer)
        guard !a.isEmpty else { return .again }
        if e == a { return .easy }

        let eTokens = Set(e.split(separator: " ").map(String.init))
        let aTokens = Set(a.split(separator: " ").map(String.init))
        guard !eTokens.isEmpty else { return a.contains(e) ? .good : .again }
        let overlap = Double(eTokens.intersection(aTokens).count) / Double(eTokens.count)

        switch overlap {
        case 0.9...: return .easy
        case 0.6..<0.9: return .good
        case 0.3..<0.6: return .hard
        default: return .again
        }
    }

    /// Lowercase, strip punctuation/accents, collapse whitespace — so "F = m·a"
    /// and "f=ma" compare sensibly.
    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let kept = folded.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }
}

/// UUID seed for the existing `SeededGenerator` (defined in PixelViews), so a
/// card's multiple-choice options shuffle the same way every redraw instead of
/// jumping around on each render. Derived from the UUID's bytes (not `Hasher`,
/// which is randomized per process and would reshuffle across launches).
extension SeededGenerator {
    init(seed: UUID) {
        let b = seed.uuid
        let hi = UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
               | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        let lo = UInt64(b.8) << 56 | UInt64(b.9) << 48 | UInt64(b.10) << 40 | UInt64(b.11) << 32
               | UInt64(b.12) << 24 | UInt64(b.13) << 16 | UInt64(b.14) << 8 | UInt64(b.15)
        let seed64 = hi ^ lo
        self.init(seed: seed64 == 0 ? 0x9E37_79B9_7F4A_7C15 : seed64)
    }
}

/// A deck rolled up from the cards currently in a `ReviewSession`. Because it is
/// derived from the cards themselves, its `id` always matches the cards'
/// `deckID` — so a deck picker built from these never desyncs from the queue.
public struct DeckSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let cardCount: Int
    public let dueCount: Int
    public let tags: [String]
}

/// Free-tier deck cap. Mito Pro removes it. Every deck stays fully offline — the
/// gate is on how many decks you can keep, never on offline access (the app is
/// deliberately offline-first for everyone).
public enum DeckLimits {
    public static let free = 5

    /// Whether another deck can be created given the current count + Mito Pro.
    @MainActor public static func canCreate(currentCount: Int) -> Bool {
        BetaConfig.premiumActive || currentCount < free
    }

    /// True when this would be over the FREE cap regardless of beta/premium —
    /// used to log where the cap *would* bite, so we learn the friction point
    /// during the beta without actually blocking testers.
    public static func wouldExceedFree(currentCount: Int) -> Bool {
        currentCount >= free
    }
}

/// The starter content shipped with the app so the review loop has real,
/// scheduled cards from first launch (before any backend decks exist).
/// Stable UUIDs keep scheduling state attached across relaunches.
public enum SeedContent {
    public static let cards: [ReviewCard] = [
        card("11111111-0000-0000-0000-000000000001", "bio", "Biology 220", "What molecule stores usable cellular energy after mitochondria charge it?", "ATP, adenosine triphosphate.", ["cell", "energy"]),
        card("11111111-0000-0000-0000-000000000002", "bio", "Biology 220", "What structure controls what enters and leaves the cell?", "The plasma membrane.", ["cell", "organelles"]),
        card("11111111-0000-0000-0000-000000000003", "bio", "Biology 220", "Which organelle packages and ships proteins?", "The Golgi apparatus.", ["organelles"]),
        card("11111111-0000-0000-0000-000000000004", "bio", "Biology 220", "What carries electrons into the electron transport chain?", "NADH and FADH₂.", ["enzymes", "energy"]),
        card("11111111-0000-0000-0000-000000000005", "bio", "Biology 220", "Where does the citric acid (Krebs) cycle take place?", "The mitochondrial matrix.", ["energy"]),
        card("22222222-0000-0000-0000-000000000001", "phys", "Physics formulas", "State Newton's second law as an equation.", "F = m·a.", ["vectors"]),
        card("22222222-0000-0000-0000-000000000002", "phys", "Physics formulas", "What is the kinetic energy of a moving body?", "KE = ½·m·v².", ["energy"]),
        card("22222222-0000-0000-0000-000000000003", "phys", "Physics formulas", "What stays constant in uniform circular motion: speed or velocity?", "Speed. Velocity changes because direction changes.", ["vectors"]),
        card("33333333-0000-0000-0000-000000000001", "orgo", "Organic mechanisms", "What stereochemical outcome does an SN2 reaction give?", "Inversion of configuration (Walden inversion).", ["exam"]),
        card("33333333-0000-0000-0000-000000000002", "orgo", "Organic mechanisms", "Which mechanism is favoured by tertiary substrates and weak nucleophiles?", "SN1.", ["exam"]),
    ]

    private static func card(_ id: String, _ deck: String, _ deckName: String, _ front: String, _ back: String, _ tags: [String]) -> ReviewCard {
        ReviewCard(id: UUID(uuidString: id)!, deckID: deck, deckName: deckName, front: front, back: back, tags: tags)
    }
}

/// A live, persistent review queue. `@MainActor` so SwiftUI can observe it.
@MainActor
public final class ReviewSession: ObservableObject {
    /// Shared instance so both the auth flow and the battle screen drive the
    /// same queue (auth attaches Supabase sync; battle reviews cards).
    public static let shared = ReviewSession()

    @Published public private(set) var current: ReviewCard?
    @Published public private(set) var reviewedCount = 0
    @Published public private(set) var remainingDue = 0
    @Published public private(set) var lastResult: ReviewResult?
    /// Bumped whenever the card pool changes, so SwiftUI re-derives deck lists.
    @Published public private(set) var catalogVersion = 0

    private let fsrs: FSRS
    private var cards: [UUID: ReviewCard] = [:]
    private var queue: [UUID] = []
    private let storeURL: URL

    /// Optional sink for mirroring a freshly-scheduled card to a backend.
    public var onPersist: ((ReviewCard) -> Void)?

    public init(
        fsrs: FSRS = FSRS(),
        seed: [ReviewCard] = SeedContent.cards,
        fileName: String = "mito_reviews.json"
    ) {
        self.fsrs = fsrs
        self.storeURL = Self.applicationSupportFile(named: fileName)

        // A persisted file is the authoritative card set (honours deletions);
        // only fall back to the bundled seeds on the very first run.
        let saved = Self.load(from: storeURL)
        if saved.isEmpty {
            for c in seed { cards[c.id] = c }
        } else {
            for c in saved { cards[c.id] = c }
        }
    }

    /// Merge backend cards into the pool. When `authoritative` (a real cloud
    /// load), the bundled starter cards are dropped so they don't duplicate the
    /// user's own cloud decks. For each card we keep whichever FSRS schedule was
    /// reviewed most recently, so studying on another device (fresher cloud
    /// `card_states`) is never clobbered by stale local JSON — and offline local
    /// progress not yet pushed up isn't lost either.
    public func ingest(_ remote: [ReviewCard], authoritative: Bool = false) {
        if authoritative {
            var rebuilt: [UUID: ReviewCard] = [:]
            for var c in remote {
                if let local = cards[c.id], Self.localScheduleIsFresher(local.sched, than: c.sched) {
                    c.sched = local.sched
                }
                rebuilt[c.id] = c
            }
            cards = rebuilt
        } else {
            for var c in remote {
                if let local = cards[c.id], Self.localScheduleIsFresher(local.sched, than: c.sched) {
                    c.sched = local.sched
                }
                cards[c.id] = c
            }
        }
        persist()
        catalogVersion += 1
    }

    /// True when `local` reflects a more recent review than `remote` (so it
    /// should win the merge). Never-reviewed schedules count as oldest.
    private static func localScheduleIsFresher(_ local: SchedulingState, than remote: SchedulingState) -> Bool {
        (local.lastReview ?? .distantPast) > (remote.lastReview ?? .distantPast)
    }

    /// Wipe all locally-stored study content + scheduling (account deletion /
    /// privacy "delete means delete"). Reseeds the bundled starter cards so the
    /// app isn't left empty for the anonymous session that follows.
    public func wipeForAccountDeletion() {
        cards = [:]
        queue = []
        current = nil
        reviewedCount = 0
        remainingDue = 0
        lastResult = nil
        try? FileManager.default.removeItem(at: storeURL)
        for c in SeedContent.cards { cards[c.id] = c }
        persist()
        catalogVersion += 1
    }

    /// Every card currently tracked, ordered by deck then front text.
    public func allCards() -> [ReviewCard] {
        cards.values.sorted { ($0.deckName, $0.front) < ($1.deckName, $1.front) }
    }

    /// Refresh from the shared App Group review file. Widget App Intents grade
    /// cards while the app may be suspended, so the foreground app needs to
    /// adopt those persisted schedules before showing due counts or queues.
    public func reloadPersisted() {
        let saved = Self.load(from: storeURL)
        guard !saved.isEmpty else { return }
        cards = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        queue.removeAll()
        current = nil
        remainingDue = 0
        lastResult = nil
        catalogVersion += 1
    }

    /// Cards belonging to one deck, ordered by front text.
    public func cards(in deckID: String) -> [ReviewCard] {
        cards.values.filter { $0.deckID == deckID }.sorted { $0.front < $1.front }
    }

    /// Insert or update a card the user authored. Preserves any existing
    /// schedule, persists locally, and refreshes derived deck lists. (Cloud
    /// content is written separately via `MitoBackend.createCard`/`updateCard`.)
    public func upsertContent(_ card: ReviewCard) {
        var c = card
        if let existing = cards[card.id] { c.sched = existing.sched }
        cards[c.id] = c
        persist()
        catalogVersion += 1
    }

    /// Remove a card the user deleted (also drops it from the live queue).
    public func remove(cardID: UUID) {
        cards.removeValue(forKey: cardID)
        queue.removeAll { $0 == cardID }
        if current?.id == cardID { advance() }
        persist()
        catalogVersion += 1
    }

    /// Remove a whole deck's cards.
    public func remove(deckID: String) {
        for id in cards.values.filter({ $0.deckID == deckID }).map(\.id) {
            cards.removeValue(forKey: id)
        }
        queue.removeAll { !cards.keys.contains($0) }
        if let cur = current, cur.deckID == deckID { advance() }
        persist()
        catalogVersion += 1
    }

    /// Decks rolled up from the current card pool, sorted by name. The ids here
    /// are exactly the cards' `deckID`s, so a picker built from this can never
    /// select a deck that has no cards in the queue.
    public var deckSummaries: [DeckSummary] {
        let now = Date()
        let groups = Dictionary(grouping: cards.values, by: \.deckID)
        return groups.map { id, cards in
            let name = cards.first(where: { !$0.deckName.isEmpty })?.deckName ?? id
            let tags = Array(Set(cards.flatMap(\.tags))).sorted()
            let due = cards.filter { $0.sched.phase == .new || $0.sched.due <= now }.count
            return DeckSummary(id: id, name: name, cardCount: cards.count, dueCount: due, tags: tags)
        }
        .sorted { $0.name < $1.name }
    }

    /// Build the due queue for the given decks/tags (all decks/tags if empty) and begin.
    /// If a non-empty filter matches no cards (e.g. stale selection after a
    /// backend swap), fall back to the whole pool so review is never empty.
    public func start(deckIDs: Set<String> = [], tags: Set<String> = [], now: Date = Date()) {
        let all = Array(cards.values)
        let deckFiltered = deckIDs.isEmpty ? all : all.filter { deckIDs.contains($0.deckID) }
        let filtered = tags.isEmpty ? deckFiltered : deckFiltered.filter { !Set($0.tags).isDisjoint(with: tags) }
        let pool = filtered.isEmpty ? all : filtered
        // Due first (oldest due date), then never-seen new cards.
        queue = pool
            .sorted { lhs, rhs in
                if (lhs.sched.phase == .new) != (rhs.sched.phase == .new) {
                    return rhs.sched.phase == .new // due/seen cards ahead of new
                }
                return lhs.sched.due < rhs.sched.due
            }
            .map(\.id)
        reviewedCount = 0
        advance()
    }

    /// Interval (in days) each grade would schedule for the current card —
    /// for labelling the Again/Hard/Good/Easy buttons.
    public func previews(now: Date = Date()) -> [Rating: Double] {
        guard let card = current else { return [:] }
        return fsrs.previewIntervals(for: card.sched, now: now)
    }

    /// Grade the current card: run FSRS, persist, advance the queue.
    /// `again` re-queues the card later in the session (relearning step).
    @discardableResult
    public func grade(_ rating: Rating, now: Date = Date()) -> ReviewResult? {
        guard let card = current else { return nil }
        let result = fsrs.review(card.sched, rating: rating, now: now)

        var updated = card
        updated.sched = result.state
        cards[updated.id] = updated
        lastResult = result
        reviewedCount += 1

        if rating == .again {
            queue.append(updated.id) // see it again this session
        }

        persist()
        onPersist?(updated)
        advance()

        // Engagement: every grade feeds the daily quest; clearing the due
        // queue (or a solid 10-card run) keeps the daily streak alive.
        DailyQuests.shared.noteCardReviewed()
        if remainingDue == 0 || reviewedCount >= 10 {
            StreakStore.shared.registerActivity()
        }
        return result
    }

    private func advance() {
        let next = queue.isEmpty ? nil : queue.removeFirst()
        current = next.flatMap { cards[$0] }
        remainingDue = queue.count + (current == nil ? 0 : 1)
    }

    // MARK: Persistence

    private func persist() {
        let snapshot = Array(cards.values)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private static func load(from url: URL) -> [ReviewCard] {
        guard let data = try? Data(contentsOf: url),
              let cards = try? JSONDecoder().decode([ReviewCard].self, from: data)
        else { return [] }
        return cards
    }

    private static func applicationSupportFile(named name: String) -> URL {
        let fm = FileManager.default
        if let shared = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yukinabe.mitov3") {
            let sharedURL = shared.appendingPathComponent(name)
            let legacyBase = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? fm.temporaryDirectory
            let legacyURL = legacyBase.appendingPathComponent(name)
            if !fm.fileExists(atPath: sharedURL.path), fm.fileExists(atPath: legacyURL.path) {
                try? fm.copyItem(at: legacyURL, to: sharedURL)
            }
            return sharedURL
        }
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return base.appendingPathComponent(name)
    }
}
