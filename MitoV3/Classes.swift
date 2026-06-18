import SwiftUI

/// Free-tier caps for classes. Mito+ removes them. Enforced client-side; the
/// RPCs enforce membership + a 30-member hard cap server-side.
enum ClassLimits {
    static let freeJoin = 3
    static let freeCreate = 1
}

// Pixel palette helpers (kept local + simple so SwiftUI's type-checker doesn't
// choke on inline ternary Color expressions).
private let cInk = Color(hex: "3A2A18")
private let cBark = Color(hex: "6B4324")
private let cPanel = Color(hex: "EAD4A4")
private let cRow = Color(hex: "DCC79A")
private let cCream = Color(hex: "F4E6C0")
private let cGreen = Color(hex: "4A8A3C")
private let cBlue = Color(hex: "4A7BA8")
private let cMuted = Color(hex: "8A8A70")
private let cStroke = Color(hex: "18100A")

// MARK: - Classes hub

/// Study-group hub: see your classes, create one (Mito+ / first is free), join
/// by code (free up to 3), and open a class to share + copy decks. Joining is
/// intentionally NOT premium-gated — that's the viral loop.
struct ClassesView: View {
    @ObservedObject var backend: MitoBackend
    @Binding var isPresented: Bool

    @State private var classes: [ClassRecord] = []
    @State private var newName = ""
    @State private var joinCode = ""
    @State private var message = ""
    @State private var loading = false
    @State private var selected: ClassRecord?

    private var ownedCount: Int { classes.filter(\.is_owner).count }
    private var canCreate: Bool { BetaConfig.premiumActive || ownedCount < ClassLimits.freeCreate }
    private var canJoin: Bool { BetaConfig.premiumActive || classes.count < ClassLimits.freeJoin }

    var body: some View {
        ZStack {
            Color.black.opacity(0.64).ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                header
                content
            }
            .padding(16)
            .frame(width: 340)
            .background(cPanel)
            .overlay(Rectangle().stroke(cStroke, lineWidth: 4))
        }
        .task { await load() }
    }

    @ViewBuilder private var header: some View {
        HStack {
            Text(selected == nil ? "CLASSES" : "CLASS").pixelText(size: 17, color: cInk)
            Spacer()
            if selected != nil {
                Button { selected = nil } label: {
                    Text("BACK").pixelText(size: 10, color: cInk)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                }.buttonStyle(.plain)
            }
            Button { isPresented = false } label: {
                Text("X").pixelText(size: 13, color: cInk)
                    .padding(.horizontal, 9).padding(.vertical, 6)
            }.buttonStyle(.plain)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder private var content: some View {
        if !backend.isReady {
            Text("Sign in (Settings → Login) to use classes.")
                .font(.custom(MitoFont.regular, size: 14))
                .foregroundStyle(cBark)
                .multilineTextAlignment(.center)
                .padding(.vertical, 20)
        } else if let selected {
            ClassDetailView(backend: backend, klass: selected) {
                self.selected = nil
                Task { await load() }
            }
        } else {
            hub
        }
    }

    private var hub: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                createSection
                joinSection
                if !message.isEmpty {
                    Text(message).font(.custom(MitoFont.regular, size: 13)).foregroundStyle(cBark)
                }
                myClassesSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 440)
    }

    @ViewBuilder private var createSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CREATE A CLASS").pixelText(size: 9, color: cBark)
            HStack(spacing: 8) {
                TextField("Class name", text: $newName)
                    .autocorrectionDisabled()
                    .authInputStyle()
                Button { Task { await create() } } label: {
                    pillLabel("NEW", bg: canCreate ? cGreen : cMuted)
                }.buttonStyle(.plain).disabled(!canCreate)
            }
            if !canCreate { gateNote("Free plan creates \(ClassLimits.freeCreate). Unlock Mito+ for unlimited.") }
        }
    }

    @ViewBuilder private var joinSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("JOIN BY CODE").pixelText(size: 9, color: cBark)
            HStack(spacing: 8) {
                TextField("CODE", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .authInputStyle()
                Button { Task { await join() } } label: {
                    pillLabel("JOIN", bg: canJoin ? cBlue : cMuted)
                }.buttonStyle(.plain).disabled(!canJoin)
            }
            if !canJoin { gateNote("Free plan joins \(ClassLimits.freeJoin). Unlock Mito+ for unlimited.") }
        }
    }

    @ViewBuilder private var myClassesSection: some View {
        Text("MY CLASSES (\(classes.count))").pixelText(size: 10, color: cInk).padding(.top, 2)
        if loading && classes.isEmpty {
            HStack { Spacer(); ProgressView().tint(cBark); Spacer() }.padding(.vertical, 6)
        } else if classes.isEmpty {
            Text("No classes yet. Create one or join with a code.")
                .font(.custom(MitoFont.regular, size: 13)).foregroundStyle(cBark)
        }
        ForEach(classes) { klass in
            Button { selected = klass } label: { ClassRow(klass: klass) }
                .buttonStyle(.plain)
        }
    }

    private func pillLabel(_ text: String, bg: Color) -> some View {
        Text(text).pixelText(size: 12, color: .white)
            .padding(.horizontal, 14).frame(height: 40)
            .background(bg)
            .overlay(Rectangle().stroke(cStroke, lineWidth: 3))
    }

    private func gateNote(_ text: String) -> some View {
        Text(text).font(.custom(MitoFont.regular, size: 11)).foregroundStyle(Color(hex: "8A5A2A"))
    }

    private func load() async {
        guard backend.isReady, !loading else { return }
        loading = true; defer { loading = false }
        classes = (try? await backend.fetchMyClasses()) ?? []
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard canCreate, name.count >= 2 else { message = "Enter a class name."; return }
        // Beta: caps aren't enforced, but log where they WOULD bite so we learn
        // the friction point without blocking testers.
        if ownedCount >= ClassLimits.freeCreate {
            await backend.logEvent("cap_would_block", props: ["cap": "class_create", "count": "\(ownedCount)"])
        }
        do {
            _ = try await backend.createClass(name: name)
            newName = ""; message = ""
            await load()
        } catch { message = "Couldn't create the class." }
    }

    private func join() async {
        let code = joinCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard canJoin, code.count >= 4 else { message = "Enter a class code."; return }
        if classes.count >= ClassLimits.freeJoin {
            await backend.logEvent("cap_would_block", props: ["cap": "class_join", "count": "\(classes.count)"])
        }
        do {
            if let joined = try await backend.joinClass(code: code) {
                message = "Joined \(joined.name)."
                joinCode = ""
                await load()
            } else {
                message = "No class with that code."
            }
        } catch { message = "Couldn't join. The class may be full." }
    }
}

private struct ClassRow: View {
    let klass: ClassRecord
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(klass.name).font(.custom(MitoFont.bold, size: 15)).foregroundStyle(cInk)
                Text("\(klass.member_count) member\(klass.member_count == 1 ? "" : "s") · \(klass.code)")
                    .font(.custom(MitoFont.regular, size: 12)).foregroundStyle(cBark)
            }
            Spacer()
            if klass.is_owner { Text("OWNER").pixelText(size: 7, color: Color(hex: "8A6B42")) }
            Text("›").pixelText(size: 16, color: cBark)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(cRow)
        .overlay(Rectangle().stroke(cStroke, lineWidth: 2))
    }
}

// MARK: - Class detail

struct ClassDetailView: View {
    @ObservedObject var backend: MitoBackend
    let klass: ClassRecord
    let onLeave: () -> Void

    @ObservedObject private var session = ReviewSession.shared
    @State private var roster: [ClassRosterEntry] = []
    @State private var decks: [ClassDeckRecord] = []
    @State private var message = ""
    @State private var working = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                titleSection
                shareDeckMenu
                if !message.isEmpty {
                    Text(message).font(.custom(MitoFont.regular, size: 12)).foregroundStyle(cBark)
                }
                sharedDecksSection
                rosterSection
                leaveButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 460)
        .task { await load() }
    }

    @ViewBuilder private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(klass.name).pixelText(size: 15, color: cInk)
            HStack(spacing: 10) {
                Text("CODE \(klass.code)").pixelText(size: 11, color: cBark).textSelection(.enabled)
                Spacer()
                ShareLink(item: "Join my class on Mito! Use code \(klass.code) to study together and share decks.") {
                    Text("INVITE").pixelText(size: 10, color: .white)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(cBlue)
                        .overlay(Rectangle().stroke(cStroke, lineWidth: 2))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var shareDeckMenu: some View {
        if !myDecks.isEmpty {
            Menu {
                ForEach(myDecks, id: \.id) { deck in
                    Button("\(deck.name) (\(deck.cardCount))") {
                        Task { await shareDeck(deckID: deck.id, name: deck.name) }
                    }
                }
            } label: {
                Text(working ? "…" : "+ SHARE A DECK").pixelText(size: 11, color: .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(cGreen)
                    .overlay(Rectangle().stroke(cStroke, lineWidth: 3))
            }
            .disabled(working)
        }
    }

    @ViewBuilder private var sharedDecksSection: some View {
        Text("SHARED DECKS (\(decks.count))").pixelText(size: 10, color: cInk)
        if decks.isEmpty {
            Text("No shared decks yet. Share one above to help the class.")
                .font(.custom(MitoFont.regular, size: 12)).foregroundStyle(cBark)
        }
        ForEach(decks) { deck in
            SharedDeckRow(deck: deck, working: working) { Task { await copyDeck(deck) } }
        }
    }

    @ViewBuilder private var rosterSection: some View {
        Text("MEMBERS (\(roster.count))").pixelText(size: 10, color: cInk).padding(.top, 2)
        ForEach(roster) { m in
            HStack {
                Text(m.displayName).font(.custom(MitoFont.regular, size: 14)).foregroundStyle(cInk)
                Spacer()
                if m.isOwner { Text("OWNER").pixelText(size: 7, color: Color(hex: "8A6B42")) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(cRow.opacity(0.7))
            .overlay(Rectangle().stroke(cStroke, lineWidth: 1))
        }
    }

    @ViewBuilder private var leaveButton: some View {
        Button { Task { await leave() } } label: {
            Text(klass.is_owner ? "DELETE CLASS" : "LEAVE CLASS")
                .pixelText(size: 10, color: Color(hex: "D84A3A"))
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .overlay(Rectangle().stroke(Color(hex: "D84A3A"), lineWidth: 2))
        }.buttonStyle(.plain).padding(.top, 4)
    }

    /// My local decks that actually have cards (the ones worth sharing).
    private var myDecks: [DeckSummary] {
        session.deckSummaries.filter { $0.cardCount > 0 }
    }

    private func load() async {
        roster = (try? await backend.fetchClassRoster(klass.id)) ?? []
        decks = (try? await backend.fetchClassDecks(klass.id)) ?? []
    }

    private func shareDeck(deckID: String, name: String) async {
        working = true; defer { working = false }
        let cards = session.cards(in: deckID).map {
            ClassCardPayload(front: $0.front, back: $0.back, tags: $0.tags)
        }
        guard !cards.isEmpty else { message = "That deck has no cards."; return }
        do {
            try await backend.shareDeckToClass(classID: klass.id, name: name, cards: cards)
            message = "Shared \(name)."
            await load()
        } catch { message = "Couldn't share that deck." }
    }

    private func copyDeck(_ deck: ClassDeckRecord) async {
        working = true; defer { working = false }
        // Copying adds a deck to the player's own collection, so it counts
        // against the free deck cap.
        if DeckLimits.wouldExceedFree(currentCount: session.deckSummaries.count) {
            await backend.logEvent("cap_would_block", props: ["cap": "deck", "count": "\(session.deckSummaries.count)"])
        }
        guard DeckLimits.canCreate(currentCount: session.deckSummaries.count) else {
            message = "Deck limit reached (\(DeckLimits.free) free). Unlock Mito+ for unlimited decks."
            return
        }
        guard let cards = try? await backend.fetchClassDeckCards(deck.id), !cards.isEmpty else {
            message = "Couldn't copy. The deck was empty."; return
        }
        // Persist into the player's own cloud decks, then reload the review
        // session so the copy is immediately studyable and syncs across devices.
        if let newDeck = try? await backend.createDeck(named: deck.name) {
            for c in cards {
                _ = try? await backend.createCard(deckID: newDeck.id, front: c.front, back: c.back, tags: c.tags)
            }
            await backend.attachSync(to: .shared)
        } else {
            let localDeckID = UUID().uuidString
            for c in cards {
                session.upsertContent(ReviewCard(id: UUID(), deckID: localDeckID, deckName: deck.name,
                                                 front: c.front, back: c.back, tags: c.tags))
            }
        }
        message = "Copied \(deck.name) to your decks."
    }

    private func leave() async {
        working = true; defer { working = false }
        try? await backend.leaveClass(klass.id)
        onLeave()
    }
}

private struct SharedDeckRow: View {
    let deck: ClassDeckRecord
    let working: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.name).font(.custom(MitoFont.bold, size: 14)).foregroundStyle(cInk)
                Text("\(deck.card_count) cards · by \(deck.sharedBy)")
                    .font(.custom(MitoFont.regular, size: 11)).foregroundStyle(cBark)
            }
            Spacer()
            Button(action: onCopy) {
                Text("COPY").pixelText(size: 9, color: .white)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(cGreen)
                    .overlay(Rectangle().stroke(cStroke, lineWidth: 2))
            }.buttonStyle(.plain).disabled(working)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(cRow)
        .overlay(Rectangle().stroke(cStroke, lineWidth: 2))
    }
}
