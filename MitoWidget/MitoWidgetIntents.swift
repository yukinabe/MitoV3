import AppIntents
import WidgetKit

enum MitoWidgetRatingChoice: String, AppEnum {
    case again
    case hard
    case good
    case easy

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Review Rating")
    static var caseDisplayRepresentations: [MitoWidgetRatingChoice: DisplayRepresentation] = [
        .again: "Again",
        .hard: "Hard",
        .good: "Good",
        .easy: "Easy"
    ]

    var reviewRating: WidgetRating {
        switch self {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }
}

struct RevealWidgetCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Reveal Bio Bud Card"
    static var description = IntentDescription("Shows the answer for the current Mito widget card.")

    @Parameter(title: "Card ID")
    var cardID: String

    init() {
        cardID = ""
    }

    init(cardID: String?) {
        self.cardID = cardID ?? ""
    }

    func perform() async throws -> some IntentResult {
        WidgetReviewStore.reveal(cardID: cardID.isEmpty ? nil : cardID)
        return .result()
    }
}

struct GradeWidgetCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Grade Bio Bud Card"
    static var description = IntentDescription("Grades the current Mito widget card with the shared FSRS scheduler.")

    @Parameter(title: "Rating")
    var rating: MitoWidgetRatingChoice

    init() {
        rating = .good
    }

    init(rating: MitoWidgetRatingChoice) {
        self.rating = rating
    }

    func perform() async throws -> some IntentResult {
        _ = WidgetReviewStore.grade(rating.reviewRating)
        return .result()
    }
}

struct ContinueReviewIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue in Mito"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
