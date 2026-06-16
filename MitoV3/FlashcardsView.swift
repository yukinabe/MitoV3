import SwiftUI
import UniformTypeIdentifiers
import Compression
import SQLite3

struct CardsScreen: View {
    var selectedTab: AppTab = .cards
    @ObservedObject private var session = ReviewSession.shared
    @ObservedObject private var backend = MitoBackend.shared
    @State private var decks = CardsScreen.seedDecks
    @State private var cardsByDeckID: [String: [Flashcard]] = CardsScreen.sampleCards
    @State private var route: CardsRoute = .library
    @State private var showingNewDeck = false
    @State private var newDeckName = ""
    @State private var didLoad = false
    @State private var didDeepLink = false
    @State private var showingImport = false
    @State private var importDeckID: String?   // nil = import into a new deck
    @State private var showDeckLimit = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                switch route {
                case .library:
                    cardsLibrary(proxy: proxy)
                case .detail(let deckID):
                    DeckDetailScreen(
                        deck: deck(for: deckID),
                        cards: cardsByDeckID[deckID, default: []],
                        onBack: { route = .library },
                        onAdd: { route = .editor(deckID: deckID, cardID: nil) },
                        onEdit: { card in route = .editor(deckID: deckID, cardID: card.id) },
                        onImport: { importDeckID = deckID; showingImport = true },
                        onDeleteDeck: { Task { await deleteDeck(deckID: deckID) } }
                    )
                case .editor(let deckID, let cardID):
                    FlashcardEditorScreen(
                        deckName: deck(for: deckID).name,
                        existingCard: cardID.flatMap { card(in: deckID, cardID: $0) },
                        onBack: { route = .detail(deckID: deckID) },
                        onSave: { front, back, tags in
                            Task {
                                await saveCard(deckID: deckID, cardID: cardID, front: front, back: back, tags: tags)
                                route = .detail(deckID: deckID)
                            }
                        },
                        onDelete: cardID.map { id in
                            { Task {
                                await deleteCard(deckID: deckID, cardID: id)
                                route = .detail(deckID: deckID)
                            } }
                        }
                    )
                }

                if showingNewDeck {
                    Color.black.opacity(0.62).ignoresSafeArea()
                    NewDeckModal(
                        name: $newDeckName,
                        onCancel: { showingNewDeck = false },
                        onCreate: {
                            let clean = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !clean.isEmpty else { return }
                            newDeckName = ""
                            showingNewDeck = false
                            Task { await createDeck(named: clean) }
                        }
                    )
                    .frame(width: proxy.size.width * 0.82)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.40)
                }

                if showingImport {
                    Color.black.opacity(0.66).ignoresSafeArea()
                    ImportSheet(
                        existingDeckName: importDeckID.flatMap { id in decks.first { $0.id == id }?.name },
                        onCancel: { showingImport = false },
                        onImport: { deckName, cards, source in
                            showingImport = false
                            Task { await runImport(targetDeckID: importDeckID, newDeckName: deckName, cards: cards, source: source) }
                        }
                    )
                    .frame(width: proxy.size.width * 0.92)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.46)
                }
            }
            .task(id: backend.isReady) { await loadLibrary() }
            .alert("Deck limit reached", isPresented: $showDeckLimit) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Free accounts keep up to \(DeckLimits.free) decks. Unlock Mito+ for unlimited decks — every deck stays available offline either way.")
            }
            .onAppear {
                #if DEBUG
                if !didDeepLink, ProcessInfo.processInfo.arguments.contains("-uitestImport") {
                    didDeepLink = true
                    importDeckID = nil
                    showingImport = true
                }
                #endif
            }
            .onChange(of: selectedTab) { _, tab in
                // Reset to the deck library on leave, but keep an open editor
                // so unsaved card edits aren't lost.
                if tab != .cards {
                    if case .editor = route {} else { route = .library }
                    showingNewDeck = false
                    showingImport = false
                }
            }
        }
    }

    @ViewBuilder
    private func cardsLibrary(proxy: GeometryProxy) -> some View {
        ZStack {
            Image("library-bg")
                .screenBackground()
            Color.black.opacity(0.20).ignoresSafeArea()

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("DECK LIBRARY")
                        .pixelText(size: 16, color: Color(hex: "F4E6C0"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Button {
                        guard DeckLimits.canCreate(currentCount: decks.count) else {
                            showDeckLimit = true; return
                        }
                        importDeckID = nil
                        showingImport = true
                    } label: {
                        Text("IMPORT")
                            .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 11)
                            .background(Color(hex: "4A8A3C"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    Button {
                        guard DeckLimits.canCreate(currentCount: decks.count) else {
                            showDeckLimit = true; return
                        }
                        newDeckName = ""
                        showingNewDeck = true
                    } label: {
                        Text("+ NEW")
                            .pixelText(size: 10, color: Color(hex: "18100A"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 11)
                            .background(Color(hex: "F7C943"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 9) {
                        ForEach(decks) { deck in
                            Button {
                                route = .detail(deckID: deck.id)
                            } label: {
                                DeckLibraryRow(deck: deck, progress: progress(for: deck.id))
                            }
                            .buttonStyle(.plain)
                        }

                        Text("\(decks.count) decks · \(decks.reduce(0) { $0 + $1.cards }) cards")
                            .font(.custom(MitoFont.regular, size: 13))
                            .foregroundStyle(Color(hex: "EAD4A4"))
                            .padding(.top, 8)
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, 96)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private enum CardsRoute {
        case library
        case detail(deckID: String)
        case editor(deckID: String, cardID: String?)
    }

    private func deck(for deckID: String) -> Deck {
        decks.first { $0.id == deckID } ?? decks[0]
    }

    private func card(in deckID: String, cardID: String) -> Flashcard? {
        cardsByDeckID[deckID, default: []].first { $0.id == cardID }
    }

    private func progress(for deckID: String) -> Double {
        let count = Double(cardsByDeckID[deckID, default: []].count)
        return min(count / 12, 1)
    }

    /// Load the library from the SAME source the battle uses — the review
    /// session's deck summaries — so the Cards screen and battle always agree.
    /// (Previously this read the Supabase `decks` table directly, which could be
    /// empty or out of sync with what the session had synced, so battle showed
    /// cards the Cards screen didn't.) Falls back to bundled samples when empty.
    private func loadLibrary() async {
        guard !didLoad else { return }
        // Pull cloud cards into the session when signed in; otherwise the session
        // already holds local/seed cards. Either way we build from the session.
        if backend.isReady { await backend.attachSync(to: session) }
        let summaries = session.deckSummaries
        guard !summaries.isEmpty else { return }   // nothing yet — keep samples, retry next pass
        didLoad = true

        var loadedDecks: [Deck] = []
        var byDeck: [String: [Flashcard]] = [:]
        for summary in summaries {
            let id = summary.id
            let cards = session.cards(in: id)
            byDeck[id] = cards.map { Flashcard(id: $0.id.uuidString, front: $0.front, back: $0.back, tags: $0.tags) }
            let tags = Array(Set(cards.flatMap(\.tags))).sorted()
            loadedDecks.append(Deck(id: id, name: summary.name, cards: cards.count,
                                    tags: tags.isEmpty ? ["new"] : tags, color: Self.deckColor(id)))
        }
        decks = loadedDecks
        cardsByDeckID = byDeck
        #if DEBUG
        // Deep-link straight into the editor for screenshots, only once cards
        // are actually loaded, and without an animated transition (no blank
        // flash on a cold launch).
        if ProcessInfo.processInfo.arguments.contains("-uitestEditor"),
           let d = decks.first, let c = cardsByDeckID[d.id]?.first {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { route = .editor(deckID: d.id, cardID: c.id) }
        }
        // Deep-link into the deck with the most cards so its tag row is visible.
        if !didDeepLink, ProcessInfo.processInfo.arguments.contains("-uitestDeck"),
           let d = decks.max(by: { cardsByDeckID[$0.id, default: []].count < cardsByDeckID[$1.id, default: []].count }) {
            didDeepLink = true
            route = .detail(deckID: d.id)
        }
        #endif
    }

    /// Create a deck on the backend (or locally when offline), then open it.
    private func createDeck(named name: String) async {
        if DeckLimits.wouldExceedFree(currentCount: decks.count) {
            await backend.logEvent("cap_would_block", props: ["cap": "deck", "count": "\(decks.count)"])
        }
        guard DeckLimits.canCreate(currentCount: decks.count) else { showDeckLimit = true; return }
        var deckID = UUID().uuidString
        if backend.isReady, let record = try? await backend.createDeck(named: name) {
            deckID = record.id.uuidString
        }
        if !decks.contains(where: { $0.id == deckID }) {
            decks.append(Deck(id: deckID, name: name, cards: 0, tags: ["new"], color: Self.deckColor(deckID)))
        }
        cardsByDeckID[deckID] = []
        await backend.logEvent("deck_created", props: ["name": name])
        route = .detail(deckID: deckID)
    }

    /// Create a deck (cloud when signed in) and return its id, without routing.
    private func makeDeck(named name: String) async -> String {
        if DeckLimits.wouldExceedFree(currentCount: decks.count) {
            await backend.logEvent("cap_would_block", props: ["cap": "deck", "count": "\(decks.count)"])
        }
        var deckID = UUID().uuidString
        // Note: callers gate on DeckLimits before reaching here (IMPORT button).
        if backend.isReady, let record = try? await backend.createDeck(named: name) {
            deckID = record.id.uuidString
        }
        if !decks.contains(where: { $0.id == deckID }) {
            decks.append(Deck(id: deckID, name: name, cards: 0, tags: ["new"], color: Self.deckColor(deckID)))
        }
        if cardsByDeckID[deckID] == nil { cardsByDeckID[deckID] = [] }
        return deckID
    }

    /// Resolve the import target (existing deck or a freshly made one), bulk
    /// add the cards, then open the deck.
    private func runImport(targetDeckID: String?, newDeckName: String?, cards: [ParsedCard], source: String) async {
        let deckID: String
        if let targetDeckID {
            deckID = targetDeckID
        } else {
            let name = (newDeckName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            deckID = await makeDeck(named: name)
            await backend.logEvent("deck_created", props: ["name": name, "via": "import"])
        }
        await importCards(into: deckID, parsed: cards, source: source)
        route = .detail(deckID: deckID)
    }

    /// Persist a batch of parsed cards into a deck (cloud + session + local).
    private func importCards(into deckID: String, parsed: [ParsedCard], source: String) async {
        var existing = cardsByDeckID[deckID, default: []]
        let name = decks.first { $0.id == deckID }?.name ?? ""
        let deckUUID = UUID(uuidString: deckID)
        for card in parsed {
            let tags = card.tags.isEmpty ? ["new"] : Array(Set(card.tags.map { $0.lowercased() })).sorted()
            var resolvedID = UUID()
            if backend.isReady, let deckUUID,
               let record = try? await backend.createCard(deckID: deckUUID, front: card.front, back: card.back, tags: tags) {
                resolvedID = record.id
            }
            existing.append(Flashcard(id: resolvedID.uuidString, front: card.front, back: card.back, tags: tags))
            let reviewCard = ReviewCard(id: resolvedID, deckID: deckID, deckName: name,
                                        front: card.front, back: card.back, tags: tags,
                                        sched: card.sched ?? .newCard())
            session.upsertContent(reviewCard)
            if card.sched != nil, backend.isReady {
                try? await backend.upsertCardState(reviewCard)
            }
        }
        cardsByDeckID[deckID] = existing
        refreshDeckMeta(deckID: deckID)
        await backend.logEvent("deck_imported", props: ["count": "\(parsed.count)", "source": source])
    }

    private func saveCard(deckID: String, cardID: String?, front: String, back: String, tags: [String]) async {
        let cleanFront = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBack = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanFront.isEmpty, !cleanBack.isEmpty else { return }

        var cards = cardsByDeckID[deckID, default: []]
        let cleanTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        let finalTags = cleanTags.isEmpty ? ["new"] : Array(Set(cleanTags)).sorted()
        let deckUUID = UUID(uuidString: deckID)
        let name = decks.first { $0.id == deckID }?.name ?? ""

        // Resolve the card id: edit keeps it; create makes a new one (using the
        // backend-assigned id when signed in, so cloud + session stay aligned).
        var resolvedID = cardID.flatMap(UUID.init(uuidString:)) ?? UUID()
        // Branch on edit-intent (a valid existing id), not on whether the card
        // happens to be in the in-memory list — otherwise an edit whose card
        // isn't loaded locally would fall through and create a duplicate.
        if let cardID, let uuid = UUID(uuidString: cardID) {
            if let index = cards.firstIndex(where: { $0.id == cardID }) {
                cards[index].front = cleanFront
                cards[index].back = cleanBack
                cards[index].tags = finalTags
            } else {
                cards.append(Flashcard(id: cardID, front: cleanFront, back: cleanBack, tags: finalTags))
            }
            try? await backend.updateCard(id: uuid, front: cleanFront, back: cleanBack, tags: finalTags)
        } else {
            if backend.isReady, let deckUUID,
               let record = try? await backend.createCard(deckID: deckUUID, front: cleanFront, back: cleanBack, tags: finalTags) {
                resolvedID = record.id
            }
            cards.append(Flashcard(id: resolvedID.uuidString, front: cleanFront, back: cleanBack, tags: finalTags))
            await backend.logEvent("card_created", props: ["deck": deckID, "tags": "\(finalTags.count)"])
        }
        cardsByDeckID[deckID] = cards

        // Make the card immediately reviewable through the shared session.
        session.upsertContent(ReviewCard(id: resolvedID, deckID: deckID, deckName: name,
                                         front: cleanFront, back: cleanBack, tags: finalTags))
        refreshDeckMeta(deckID: deckID)
        // (Multiple-choice mode was retired, so we no longer pre-generate
        // distractors on save — that's one fewer AI call per card.)
    }

    /// Delete a card from the deck list, backend, and review session.
    private func deleteCard(deckID: String, cardID: String) async {
        cardsByDeckID[deckID] = cardsByDeckID[deckID, default: []].filter { $0.id != cardID }
        if let uuid = UUID(uuidString: cardID) {
            session.remove(cardID: uuid)
            try? await backend.deleteCard(id: uuid)
        }
        refreshDeckMeta(deckID: deckID)
    }

    /// Delete an entire deck (and its cards) from the library, backend, session.
    private func deleteDeck(deckID: String) async {
        decks.removeAll { $0.id == deckID }
        cardsByDeckID[deckID] = nil
        session.remove(deckID: deckID)
        if let uuid = UUID(uuidString: deckID) {
            try? await backend.deleteDeck(id: uuid)
        }
        route = .library
    }

    /// Recompute a deck's card count + tag summary after a card change.
    private func refreshDeckMeta(deckID: String) {
        guard let index = decks.firstIndex(where: { $0.id == deckID }) else { return }
        let cards = cardsByDeckID[deckID, default: []]
        let deck = decks[index]
        let uniqueTags = Array(Set(cards.flatMap(\.tags))).sorted()
        decks[index] = Deck(
            id: deck.id,
            name: deck.name,
            cards: cards.count,
            tags: uniqueTags.isEmpty ? ["new"] : uniqueTags,
            color: deck.color
        )
    }

    private static func deckColor(_ id: String) -> Color {
        let known: [String: Color] = [
            "bio": Color(hex: "6DB04C"), "phys": Color(hex: "5FA3D4"),
            "jp": Color(hex: "E7A0B8"), "orgo": Color(hex: "D4873A"),
        ]
        if let c = known[id] { return c }
        let palette = [
            Color(hex: "6DB04C"), Color(hex: "5FA3D4"), Color(hex: "E7A0B8"),
            Color(hex: "D4873A"), Color(hex: "A98FD0"), Color(hex: "E8C64A"),
        ]
        return palette[abs(id.hashValue) % palette.count]
    }

    private static let sampleCards: [String: [Flashcard]] = [
        "bio": [
            Flashcard(id: "bio-1", front: "What organelle produces most cellular ATP?", back: "The mitochondrion produces ATP through cellular respiration.", tags: ["cell", "dna", "mitosis"]),
            Flashcard(id: "bio-2", front: "What happens during mitosis?", back: "One cell divides its duplicated chromosomes into two identical daughter nuclei.", tags: ["cell", "mitosis"]),
            Flashcard(id: "bio-3", front: "What does DNA store?", back: "DNA stores genetic instructions used to build and regulate living cells.", tags: ["dna"])
        ],
        "phys": [
            Flashcard(id: "phys-1", front: "What is the kinetic energy formula?", back: "Kinetic energy equals one half times mass times velocity squared.", tags: ["kinematics", "energy"]),
            Flashcard(id: "phys-2", front: "What does frequency measure?", back: "Frequency measures cycles per second, in hertz.", tags: ["waves"])
        ],
        "jp": [
            Flashcard(id: "jp-1", front: "What does taberu mean?", back: "Taberu means to eat.", tags: ["n5", "verbs"]),
            Flashcard(id: "jp-2", front: "What does mizu mean?", back: "Mizu means water.", tags: ["n5", "nouns"])
        ],
        "orgo": [
            Flashcard(id: "orgo-1", front: "What stereochemistry does SN2 give?", back: "SN2 reactions invert stereochemistry at the reacting center.", tags: ["sn2"]),
            Flashcard(id: "orgo-2", front: "What favors SN1?", back: "Stable carbocations, polar protic solvent, and good leaving groups favor SN1.", tags: ["sn1"])
        ]
    ]

    private static let seedDecks: [Deck] = DataSet.decks.map { deck in
        Deck(
            id: deck.id,
            name: deck.name,
            cards: sampleCards[deck.id, default: []].count,
            tags: deck.tags,
            color: deck.color
        )
    }
}

struct DeckDetailScreen: View {
    let deck: Deck
    let cards: [Flashcard]
    let onBack: () -> Void
    let onAdd: () -> Void
    let onEdit: (Flashcard) -> Void
    let onImport: () -> Void
    let onDeleteDeck: () -> Void
    @State private var confirmingDelete = false

    /// Every distinct tag used by this deck's cards (placeholder "new" hidden).
    private var deckTags: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for tag in cards.flatMap(\.tags) where tag != "new" && !seen.contains(tag) {
            seen.insert(tag)
            out.append(tag)
        }
        return out
    }

    var body: some View {
        ZStack {
            DottedDarkBackground()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(action: onBack) {
                        Text("< BACK")
                            .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    Text(deck.name)
                        .pixelText(size: 17, color: Color(hex: "F4E6C0"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Text("\(cards.count) CARDS")
                        .pixelText(size: 10, color: Color(hex: "B89868"))
                }

                HStack {
                    SmallToggle("ALL", active: true)
                    SmallToggle("NEW", active: false)
                }

                if deckTags.isEmpty {
                    Text("No tags yet — add tags when you create cards.")
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "8A6B42"))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(deckTags, id: \.self) { tag in
                                Text(tag.uppercased())
                                    .pixelText(size: 8, color: Color(hex: "3A2A18"))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: "F4E6C0"))
                                    .overlay(Rectangle().stroke(Color(hex: "B89868"), lineWidth: 1))
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }

                if cards.isEmpty {
                    Spacer()
                    Text("No cards in this deck yet.")
                        .font(.custom(MitoFont.regular, size: 17))
                        .foregroundStyle(Color(hex: "B89868"))
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(cards) { card in
                                Button {
                                    onEdit(card)
                                } label: {
                                    FlashcardListRow(card: card)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                HStack(spacing: 8) {
                    Button(action: onAdd) {
                        Text("+ ADD CARD")
                            .pixelText(size: 13, color: Color(hex: "3A2A18"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "EAD4A4"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    Button(action: onImport) {
                        Text("IMPORT")
                            .pixelText(size: 13, color: Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "4A8A3C"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }

                Button { confirmingDelete = true } label: {
                    Text("DELETE DECK")
                        .pixelText(size: 11, color: .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(hex: "C4452F"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Delete \(deck.name) and all its cards?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete deck", role: .destructive) { onDeleteDeck() }
                    Button("Cancel", role: .cancel) {}
                }
            }
            .padding(18)
        }
    }
}

struct FlashcardListRow: View {
    let card: Flashcard

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color(hex: "6DB04C"))
                .frame(width: 7)
            VStack(alignment: .leading, spacing: 5) {
                Text(card.front)
                    .pixelText(size: 12, color: Color(hex: "3A2A18"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(card.back)
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    ForEach(card.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .pixelText(size: 7, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: "F4E6C0"))
                            .overlay(Rectangle().stroke(Color(hex: "B89868"), lineWidth: 1))
                    }
                }
            }
            Spacer()
            Text("EDIT")
                .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(hex: "6B4324"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .frame(minHeight: 76)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

struct NewDeckModal: View {
    @Binding var name: String
    let onCancel: () -> Void
    let onCreate: () -> Void

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NEW DECK")
                    .pixelText(size: 17, color: Color(hex: "3A2A18"))
                Spacer()
                Button(action: onCancel) {
                    Text("×")
                        .font(.custom(MitoFont.regular, size: 28))
                        .foregroundStyle(Color(hex: "3A2A18"))
                }
                .buttonStyle(.plain)
            }
            Text("DECK NAME")
                .pixelText(size: 10, color: Color(hex: "6B4324"))
            TextField("e.g. Organic mechanisms", text: $name)
                .font(.custom(MitoFont.regular, size: 20))
                .foregroundStyle(Color(hex: "3A2A18"))
                .padding(10)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            Text("You'll be able to add cards and tags after creating.")
                .font(.custom(MitoFont.regular, size: 13))
                .foregroundStyle(Color(hex: "8A6B42"))
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("CANCEL")
                        .pixelText(size: 12, color: Color(hex: "3A2A18"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(hex: "EAD4A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                Button(action: onCreate) {
                    Text("CREATE")
                        .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(canCreate ? Color(hex: "4A8A3C") : Color(hex: "9EB46F"))
                        .overlay(Rectangle().stroke(canCreate ? Color(hex: "18100A") : Color(hex: "8A9A62"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(!canCreate)
            }
        }
        .padding(16)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

struct DeckLibraryRow: View {
    let deck: Deck
    let progress: Double

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(deck.color)
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(deck.name)
                        .pixelText(size: 14, color: Color(hex: "3A2A18"))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(deck.cards)")
                            .pixelText(size: 18, color: Color(hex: "3A2A18"))
                        Text("cards")
                            .font(.custom(MitoFont.regular, size: 11))
                            .foregroundStyle(Color(hex: "8A6B42"))
                    }
                }
                HStack(spacing: 5) {
                    ForEach(deck.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .pixelText(size: 7, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: "F4E6C0"))
                            .overlay(Rectangle().stroke(Color(hex: "B89868"), lineWidth: 1))
                    }
                    if deck.id == "bio" || deck.id == "orgo" {
                        Text("+1")
                            .font(.custom(MitoFont.regular, size: 11))
                            .foregroundStyle(Color(hex: "6B4324"))
                    }
                }
                HStack(spacing: 8) {
                    ProgressBar(progress: progress, color: deck.color)
                    Text("\(Int(progress * 100))%")
                        .font(.custom(MitoFont.regular, size: 11))
                        .foregroundStyle(Color(hex: "3A2A18"))
                    Text(">")
                        .font(.custom(MitoFont.regular, size: 14))
                        .foregroundStyle(Color(hex: "3A2A18"))
                }
            }
            .padding(.vertical, 9)
            .padding(.trailing, 10)
        }
        .frame(height: 76)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .padding(.horizontal, 16)
    }
}
