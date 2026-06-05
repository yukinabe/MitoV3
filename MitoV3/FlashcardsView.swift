import SwiftUI
import UniformTypeIdentifiers

struct CardsScreen: View {
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
                        onImport: { deckName, cards in
                            showingImport = false
                            Task { await runImport(targetDeckID: importDeckID, newDeckName: deckName, cards: cards, source: "paste") }
                        }
                    )
                    .frame(width: proxy.size.width * 0.92)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.46)
                }
            }
            .task(id: backend.isReady) { await loadLibrary() }
            .onAppear {
                #if DEBUG
                if !didDeepLink, ProcessInfo.processInfo.arguments.contains("-uitestImport") {
                    didDeepLink = true
                    importDeckID = nil
                    showingImport = true
                }
                #endif
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

    /// Load the user's real decks from Supabase (cards come from the already-
    /// synced review session). Falls back to the bundled samples when offline.
    private func loadLibrary() async {
        guard !didLoad, backend.isReady else { return }
        didLoad = true
        await backend.attachSync(to: session) // make sure cloud cards are loaded
        guard let remote = try? await backend.fetchDecks(), !remote.isEmpty else { return }

        var loadedDecks: [Deck] = []
        var byDeck: [String: [Flashcard]] = [:]
        for record in remote {
            let id = record.id.uuidString
            let cards = session.cards(in: id)
            byDeck[id] = cards.map { Flashcard(id: $0.id.uuidString, front: $0.front, back: $0.back, tags: $0.tags) }
            let tags = Array(Set(cards.flatMap(\.tags))).sorted()
            loadedDecks.append(Deck(id: id, name: record.name, cards: cards.count,
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
        var deckID = UUID().uuidString
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
            session.upsertContent(ReviewCard(id: resolvedID, deckID: deckID, deckName: name,
                                             front: card.front, back: card.back, tags: tags))
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

struct FlashcardEditorScreen: View {
    let deckName: String
    let existingCard: Flashcard?
    let onBack: () -> Void
    let onSave: (String, String, [String]) -> Void
    let onDelete: (() -> Void)?
    @State private var front: String
    @State private var back: String
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var confirmingDelete = false
    @State private var activeSide: FlashcardSide = .front

    init(
        deckName: String,
        existingCard: Flashcard?,
        onBack: @escaping () -> Void,
        onSave: @escaping (String, String, [String]) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.deckName = deckName
        self.existingCard = existingCard
        self.onBack = onBack
        self.onSave = onSave
        self.onDelete = onDelete
        _front = State(initialValue: existingCard?.front ?? "")
        _back = State(initialValue: existingCard?.back ?? "")
        // Don't surface the placeholder "new" tag in the editor.
        _tags = State(initialValue: (existingCard?.tags ?? []).filter { $0 != "new" })
    }

    private var canSave: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty, !tags.contains(t) else { newTag = ""; return }
        tags.append(t)
        newTag = ""
    }

    var body: some View {
        ZStack {
            DottedDarkBackground()
            VStack(alignment: .leading, spacing: 12) {
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
                    VStack(alignment: .leading, spacing: 1) {
                        Text(deckName)
                            .pixelText(size: 17, color: Color(hex: "F4E6C0"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(existingCard == nil ? "NEW FLASHCARD" : "EDIT FLASHCARD")
                            .font(.custom(MitoFont.regular, size: 13))
                            .foregroundStyle(Color(hex: "B89868"))
                    }
                    Spacer()
                    Button {
                        onSave(front, back, tags)
                    } label: {
                        Text(existingCard == nil ? "CREATE" : "SAVE")
                            .pixelText(size: 11, color: canSave ? Color(hex: "F4E6C0") : Color(hex: "3A2A18"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(canSave ? Color(hex: "4A8A3C") : Color(hex: "B89868"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }

                VStack(alignment: .leading, spacing: 12) {
                    FlashcardSideTabs(activeSide: $activeSide)
                    FlippingFlashcardEditor(activeSide: activeSide, front: $front, back: $back)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: activeSide)

                    tagEditor
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                if onDelete != nil {
                    Button {
                        confirmingDelete = true
                    } label: {
                        Text("DELETE CARD")
                            .pixelText(size: 12, color: .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color(hex: "C4452F"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Delete this flashcard?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) { onDelete?() }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .padding(18)
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
                        Text("TAGS")
                            .pixelText(size: 9, color: Color(hex: "6B4324"))
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Button {
                                    tags.removeAll { $0 == tag }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(tag.uppercased())
                                            .pixelText(size: 8, color: .white)
                                        Text("×")
                                            .font(.custom(MitoFont.regular, size: 14))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "6B9C4A"))
                                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("add a tag", text: $newTag)
                                .font(.custom(MitoFont.regular, size: 15))
                                .foregroundStyle(Color(hex: "3A2A18"))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit(addTag)
                                .padding(8)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                            Button(action: addTag) {
                                Text("+ ADD")
                                    .pixelText(size: 9, color: Color(hex: "3A2A18"))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(Color(hex: "F7C943"))
                                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
        }
        .padding(10)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "B89868"), lineWidth: 2))
    }
}

enum FlashcardSide {
    case front
    case back

    var title: String {
        switch self {
        case .front: "FRONT"
        case .back: "BACK"
        }
    }

    var placeholder: String {
        switch self {
        case .front: "Write the question or prompt..."
        case .back: "Write the answer..."
        }
    }
}

struct FlashcardSideTabs: View {
    @Binding var activeSide: FlashcardSide

    var body: some View {
        HStack(spacing: 10) {
            FlashcardSideTab(side: .front, activeSide: $activeSide)
            Spacer(minLength: 0)
            FlashcardSideTab(side: .back, activeSide: $activeSide)
        }
    }
}

struct FlashcardSideTab: View {
    let side: FlashcardSide
    @Binding var activeSide: FlashcardSide

    private var isActive: Bool {
        activeSide == side
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                activeSide = side
            }
        } label: {
            Text(side.title)
                .pixelText(size: 13, color: isActive ? Color(hex: "F4E6C0") : Color(hex: "8A6B42"))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isActive ? Color(hex: "4A8A3C") : Color(hex: "6B4324").opacity(0.42))
                .overlay(Rectangle().stroke(isActive ? Color(hex: "18100A") : Color(hex: "8A6B42"), lineWidth: isActive ? 3 : 2))
                .opacity(isActive ? 1 : 0.72)
        }
        .buttonStyle(.plain)
    }
}

struct FlippingFlashcardEditor: View {
    let activeSide: FlashcardSide
    @Binding var front: String
    @Binding var back: String

    var body: some View {
        ZStack {
            FlashcardSidePage(side: .front, text: $front)
                .opacity(activeSide == .front ? 1 : 0)
                .animation(nil, value: activeSide)

            FlashcardSidePage(side: .back, text: $back)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(activeSide == .back ? 1 : 0)
                .animation(nil, value: activeSide)
        }
        .rotation3DEffect(.degrees(activeSide == .back ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
    }
}

struct FlashcardSidePage: View {
    let side: FlashcardSide
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(side.title)
                    .pixelText(size: 14, color: Color(hex: "3A2A18"))
                Spacer()
                Text(side == .front ? "QUESTION" : "ANSWER")
                    .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(hex: "6B4324"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.custom(MitoFont.regular, size: 23))
                    .foregroundStyle(Color(hex: "3A2A18"))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if text.isEmpty {
                    Text(side.placeholder)
                        .font(.custom(MitoFont.regular, size: 20))
                        .foregroundStyle(Color(hex: "8A6B42"))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color(hex: "B89868"))
                .frame(width: 14, height: 14)
                .padding(10)
        }
    }
}

struct SmallToggle: View {
    let title: String
    let active: Bool

    init(_ title: String, active: Bool) {
        self.title = title
        self.active = active
    }

    var body: some View {
        Text(title)
            .pixelText(size: 10, color: active ? Color(hex: "F4E6C0") : Color(hex: "3A2A18"))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(active ? Color(hex: "4A8A3C") : Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
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

// MARK: - Bulk import

struct ParsedCard {
    let front: String
    let back: String
    let tags: [String]
}

enum ImportFormat: String, CaseIterable, Identifiable {
    case lines, csv, json
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lines: "LINES"
        case .csv: "CSV"
        case .json: "JSON"
        }
    }
    var hint: String {
        switch self {
        case .lines: "One card per line, front and back split by a tab, ; or ,"
        case .csv: "front,back per row (a front,back header row is skipped)"
        case .json: #"[{"front":"…","back":"…","tags":["…"]}]  (q/a also accepted)"#
        }
    }
}

enum CardImporter {
    static func parse(_ text: String, format: ImportFormat) -> [ParsedCard] {
        switch format {
        case .lines: return parseLines(text)
        case .csv: return parseCSV(text)
        case .json: return parseJSON(text)
        }
    }

    private static func parseLines(_ text: String) -> [ParsedCard] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            for delimiter in ["\t", " | ", ";", " - ", ","] {
                if let range = line.range(of: delimiter) {
                    let front = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let back = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !front.isEmpty, !back.isEmpty {
                        return ParsedCard(front: front, back: back, tags: [])
                    }
                }
            }
            return nil
        }
    }

    private static func parseCSV(_ text: String) -> [ParsedCard] {
        var rows = text.split(whereSeparator: \.isNewline).map(String.init)
        if let header = rows.first?.lowercased().replacingOccurrences(of: " ", with: ""),
           header.hasPrefix("front,back") {
            rows.removeFirst()
        }
        return rows.compactMap { row in
            let cols = splitCSVRow(row)
            guard cols.count >= 2 else { return nil }
            let front = cols[0].trimmingCharacters(in: .whitespaces)
            let back = cols[1].trimmingCharacters(in: .whitespaces)
            guard !front.isEmpty, !back.isEmpty else { return nil }
            let tags = cols.count >= 3
                ? cols[2].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
                : []
            return ParsedCard(front: front, back: back, tags: tags)
        }
    }

    private static func splitCSVRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in row {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == ",", !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    private static func parseJSON(_ text: String) -> [ParsedCard] {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { obj in
            let frontRaw = (obj["front"] ?? obj["q"] ?? obj["question"]) as? String
            let backRaw = (obj["back"] ?? obj["a"] ?? obj["answer"]) as? String
            guard let front = frontRaw?.trimmingCharacters(in: .whitespaces), !front.isEmpty,
                  let back = backRaw?.trimmingCharacters(in: .whitespaces), !back.isEmpty else { return nil }
            let tags = (obj["tags"] as? [String])?.map { $0.lowercased() } ?? []
            return ParsedCard(front: front, back: back, tags: tags)
        }
    }
}

struct DeckTemplate: Identifiable {
    let id: String
    let name: String
    let cards: [ParsedCard]

    static let all: [DeckTemplate] = [
        DeckTemplate(id: "tmpl-cell", name: "Cell Biology", cards: [
            ParsedCard(front: "What organelle makes most ATP?", back: "The mitochondrion.", tags: ["cell"]),
            ParsedCard(front: "What does the nucleus store?", back: "The cell's DNA.", tags: ["cell"]),
            ParsedCard(front: "Where are proteins assembled?", back: "On ribosomes.", tags: ["cell"]),
            ParsedCard(front: "What packages and ships proteins?", back: "The Golgi apparatus.", tags: ["cell"]),
            ParsedCard(front: "What controls what enters the cell?", back: "The cell membrane.", tags: ["cell"])
        ]),
        DeckTemplate(id: "tmpl-es", name: "Spanish 101", cards: [
            ParsedCard(front: "hello", back: "hola", tags: ["spanish"]),
            ParsedCard(front: "thank you", back: "gracias", tags: ["spanish"]),
            ParsedCard(front: "water", back: "agua", tags: ["spanish"]),
            ParsedCard(front: "to eat", back: "comer", tags: ["spanish"]),
            ParsedCard(front: "good morning", back: "buenos días", tags: ["spanish"])
        ]),
        DeckTemplate(id: "tmpl-cap", name: "World Capitals", cards: [
            ParsedCard(front: "Japan", back: "Tokyo", tags: ["geography"]),
            ParsedCard(front: "France", back: "Paris", tags: ["geography"]),
            ParsedCard(front: "Brazil", back: "Brasília", tags: ["geography"]),
            ParsedCard(front: "Egypt", back: "Cairo", tags: ["geography"]),
            ParsedCard(front: "Canada", back: "Ottawa", tags: ["geography"])
        ])
    ]
}

struct ImportSheet: View {
    let existingDeckName: String?
    let onCancel: () -> Void
    let onImport: (_ deckName: String?, _ cards: [ParsedCard]) -> Void

    @State private var format: ImportFormat = .lines
    @State private var text = ""
    @State private var newDeckName = ""
    @State private var showFileImporter = false

    private var creatingNew: Bool { existingDeckName == nil }
    private var parsed: [ParsedCard] { CardImporter.parse(text, format: format) }
    private var canImport: Bool {
        !parsed.isEmpty && (!creatingNew || !newDeckName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(creatingNew ? "IMPORT NEW DECK" : "IMPORT INTO \(existingDeckName!.uppercased())")
                    .pixelText(size: 13, color: Color(hex: "3A2A18"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button(action: onCancel) {
                    Text("×")
                        .font(.custom(MitoFont.regular, size: 26))
                        .foregroundStyle(Color(hex: "3A2A18"))
                }
                .buttonStyle(.plain)
            }

            if creatingNew {
                TextField("Deck name", text: $newDeckName)
                    .font(.custom(MitoFont.regular, size: 17))
                    .foregroundStyle(Color(hex: "3A2A18"))
                    .padding(8)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }

            HStack(spacing: 6) {
                ForEach(ImportFormat.allCases) { item in
                    Button { format = item } label: {
                        Text(item.title)
                            .pixelText(size: 9, color: format == item ? Color(hex: "18100A") : Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(format == item ? Color(hex: "F7C943") : Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(format.hint)
                .font(.custom(MitoFont.regular, size: 12))
                .foregroundStyle(Color(hex: "6B4324"))
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.custom(MitoFont.regular, size: 15))
                    .foregroundStyle(Color(hex: "3A2A18"))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 132)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                if text.isEmpty {
                    Text("Paste your cards here…")
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "8A6B42"))
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Button { showFileImporter = true } label: {
                    Text("LOAD FILE")
                        .pixelText(size: 9, color: Color(hex: "3A2A18"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(hex: "EAD4A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(parsed.isEmpty ? "0 cards" : "✓ \(parsed.count) cards")
                    .pixelText(size: 10, color: parsed.isEmpty ? Color(hex: "8A6B42") : Color(hex: "4A8A3C"))
            }

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("CANCEL")
                        .pixelText(size: 11, color: Color(hex: "3A2A18"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "EAD4A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                Button {
                    onImport(creatingNew ? newDeckName.trimmingCharacters(in: .whitespaces) : nil, parsed)
                } label: {
                    Text(parsed.isEmpty ? "IMPORT" : "IMPORT \(parsed.count)")
                        .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canImport ? Color(hex: "4A8A3C") : Color(hex: "8A6B42"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(!canImport)
            }
        }
        .padding(14)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.commaSeparatedText, .json, .plainText, .text]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let loaded = try? String(contentsOf: url, encoding: .utf8) else { return }
            text = loaded
            switch url.pathExtension.lowercased() {
            case "json": format = .json
            case "csv": format = .csv
            default: break
            }
        }
    }
}
