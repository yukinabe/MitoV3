import Foundation
import WidgetKit

enum WidgetRating: Int, Codable, CaseIterable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    var label: String {
        switch self {
        case .again: "AGAIN"
        case .hard: "HARD"
        case .good: "GOOD"
        case .easy: "EASY"
        }
    }
}

enum WidgetCardPhase: Int, Codable {
    case new
    case learning
    case review
    case relearning
}

struct WidgetMemoryState: Codable, Equatable {
    var stability: Double
    var difficulty: Double
}

struct WidgetSchedulingState: Codable, Equatable {
    var memory: WidgetMemoryState?
    var phase: WidgetCardPhase
    var due: Date
    var lastReview: Date?
    var reps: Int
    var lapses: Int
}

struct WidgetReviewCard: Identifiable, Codable, Equatable {
    let id: UUID
    var deckID: String
    var deckName: String
    var front: String
    var back: String
    var tags: [String]
    var sched: WidgetSchedulingState
    var choices: [String]?
}

struct WidgetReviewResult {
    let state: WidgetSchedulingState
    let intervalDays: Double
}

struct WidgetFSRS {
    static let defaultParameters: [Double] = [
        0.212,  1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
        1.8722, 0.1666, 0.796,  1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
        1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ]

    let w = WidgetFSRS.defaultParameters
    let desiredRetention = 0.9
    let maximumIntervalDays = 36500.0
    private let decay: Double
    private let factor: Double

    init() {
        decay = -Self.defaultParameters[20]
        factor = pow(0.9, 1.0 / decay) - 1.0
    }

    func review(_ state: WidgetSchedulingState, rating: WidgetRating, now: Date = Date()) -> WidgetReviewResult {
        let elapsedDays = state.lastReview.map { max(0, now.timeIntervalSince($0) / 86_400) } ?? 0
        var next = state
        next.reps += 1
        next.lastReview = now

        let memory: WidgetMemoryState
        if let old = state.memory {
            let d = nextDifficulty(old.difficulty, rating: rating)
            let s: Double
            if elapsedDays < 1.0 {
                s = shortTermStability(old.stability, rating: rating)
            } else {
                let r = retrievability(elapsedDays: elapsedDays, stability: old.stability)
                s = rating == .again
                    ? stabilityAfterForget(difficulty: d, stability: old.stability, retrievability: r)
                    : stabilityAfterRecall(difficulty: d, stability: old.stability, retrievability: r, rating: rating)
            }
            memory = WidgetMemoryState(stability: s, difficulty: d)
        } else {
            memory = WidgetMemoryState(stability: initialStability(rating), difficulty: initialDifficulty(rating))
        }

        next.memory = memory
        let wasReview = state.phase == .review
        switch rating {
        case .again:
            if wasReview { next.lapses += 1 }
            next.phase = .relearning
        case .hard, .good, .easy:
            next.phase = .review
        }

        let scheduledDays = max(1.0, interval(forStability: memory.stability).rounded())
        next.due = now.addingTimeInterval(scheduledDays * 86_400)
        return WidgetReviewResult(state: next, intervalDays: scheduledDays)
    }

    private func retrievability(elapsedDays t: Double, stability s: Double) -> Double {
        guard s > 0 else { return 0 }
        return pow(1.0 + factor * max(0, t) / s, decay)
    }

    private func interval(forStability s: Double) -> Double {
        let raw = (s / factor) * (pow(desiredRetention, 1.0 / decay) - 1.0)
        return min(max(raw, 1.0), maximumIntervalDays)
    }

    private func initialStability(_ rating: WidgetRating) -> Double {
        clampStability(w[rating.rawValue - 1])
    }

    private func initialDifficulty(_ rating: WidgetRating) -> Double {
        let g = Double(rating.rawValue)
        return clampDifficulty(w[4] - exp(w[5] * (g - 1.0)) + 1.0)
    }

    private func nextDifficulty(_ d: Double, rating: WidgetRating) -> Double {
        let g = Double(rating.rawValue)
        let deltaD = -w[6] * (g - 3.0)
        let damped = d + deltaD * (10.0 - d) / 9.0
        let reverted = w[7] * initialDifficulty(.easy) + (1.0 - w[7]) * damped
        return clampDifficulty(reverted)
    }

    private func stabilityAfterRecall(difficulty d: Double, stability s: Double, retrievability r: Double, rating: WidgetRating) -> Double {
        let hardPenalty = rating == .hard ? w[15] : 1.0
        let easyBonus = rating == .easy ? w[16] : 1.0
        let growth = exp(w[8])
            * (11.0 - d)
            * pow(s, -w[9])
            * (exp(w[10] * (1.0 - r)) - 1.0)
            * hardPenalty
            * easyBonus
        return clampStability(s * (1.0 + growth))
    }

    private func stabilityAfterForget(difficulty d: Double, stability s: Double, retrievability r: Double) -> Double {
        let sf = w[11]
            * pow(d, -w[12])
            * (pow(s + 1.0, w[13]) - 1.0)
            * exp(w[14] * (1.0 - r))
        let ceiling = s / exp(w[17] * w[18])
        return clampStability(min(sf, ceiling))
    }

    private func shortTermStability(_ s: Double, rating: WidgetRating) -> Double {
        let g = Double(rating.rawValue)
        let sinc = exp(w[17] * (g - 3.0 + w[18])) * pow(s, -w[19])
        return clampStability(s * (rating == .again ? sinc : max(sinc, 1.0)))
    }

    private func clampStability(_ s: Double) -> Double {
        s.isFinite ? max(0.01, s) : 0.01
    }

    private func clampDifficulty(_ d: Double) -> Double {
        guard d.isFinite else { return 1.0 }
        return min(10.0, max(1.0, d))
    }
}

enum WidgetReviewStore {
    static let suiteName = "group.com.yukinabe.mitov3"
    private static let reviewFileName = "mito_reviews.json"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func dueCards(now: Date = Date()) -> [WidgetReviewCard] {
        loadCards()
            .filter { $0.sched.phase == .new || $0.sched.due <= now }
            .sorted { lhs, rhs in
                if (lhs.sched.phase == .new) != (rhs.sched.phase == .new) {
                    return rhs.sched.phase == .new
                }
                return lhs.sched.due < rhs.sched.due
            }
    }

    static func isRevealed(cardID: String?) -> Bool {
        guard let cardID, let defaults else { return false }
        return defaults.string(forKey: "widget.card.revealedID") == cardID
            && defaults.bool(forKey: "widget.card.revealed")
    }

    static func reveal(cardID: String?) {
        guard let cardID, let defaults else { return }
        defaults.set(cardID, forKey: "widget.card.revealedID")
        defaults.set(true, forKey: "widget.card.revealed")
        WidgetCenter.shared.reloadAllTimelines()
    }

    @discardableResult
    static func grade(_ rating: WidgetRating) -> Bool {
        var cards = loadCards()
        let due = dueCards()
        let preferred = defaults?.string(forKey: "widget.card.id").flatMap(UUID.init(uuidString:))
        guard let target = due.first(where: { $0.id == preferred }) ?? due.first,
              let index = cards.firstIndex(where: { $0.id == target.id })
        else { return false }

        let result = WidgetFSRS().review(cards[index].sched, rating: rating)
        cards[index].sched = result.state
        save(cards)
        syncWidgetDefaults(afterGrading: cards, lastRating: rating)
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    static func syncWidgetDefaults(afterGrading cards: [WidgetReviewCard]? = nil, lastRating: WidgetRating? = nil) {
        guard let defaults else { return }
        let now = Date()
        let pool = cards ?? loadCards()
        let due = pool
            .filter { $0.sched.phase == .new || $0.sched.due <= now }
            .sorted { lhs, rhs in
                if (lhs.sched.phase == .new) != (rhs.sched.phase == .new) {
                    return rhs.sched.phase == .new
                }
                return lhs.sched.due < rhs.sched.due
            }
        defaults.set(due.count, forKey: "widget.due")
        defaults.set(false, forKey: "widget.card.revealed")
        defaults.removeObject(forKey: "widget.card.revealedID")
        if let lastRating {
            defaults.set(lastRating.label, forKey: "widget.card.lastGrade")
        }
        if let next = due.first {
            defaults.set(next.id.uuidString, forKey: "widget.card.id")
            defaults.set(next.deckName.isEmpty ? next.deckID : next.deckName, forKey: "widget.card.deck")
            defaults.set(next.front, forKey: "widget.card.front")
            defaults.set(next.back, forKey: "widget.card.back")
        } else {
            defaults.removeObject(forKey: "widget.card.id")
            defaults.removeObject(forKey: "widget.card.deck")
            defaults.removeObject(forKey: "widget.card.front")
            defaults.removeObject(forKey: "widget.card.back")
        }
    }

    private static func loadCards() -> [WidgetReviewCard] {
        guard let url = reviewURL(),
              let data = try? Data(contentsOf: url),
              let cards = try? JSONDecoder().decode([WidgetReviewCard].self, from: data)
        else { return [] }
        return cards
    }

    private static func save(_ cards: [WidgetReviewCard]) {
        guard let url = reviewURL(),
              let data = try? JSONEncoder().encode(cards)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func reviewURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent(reviewFileName)
    }
}
