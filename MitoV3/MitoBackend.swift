import Foundation
import Combine
import Supabase

enum MitoBackendConfig {
    static let projectRef = "ncnkvgpulnalauzxvfoh"
    static let url = URL(string: "https://ncnkvgpulnalauzxvfoh.supabase.co")!
    static let publishableKey = "sb_publishable_o3SwMMi_ao7IkVuV-azqxg_beGzmWzi"
}

@MainActor
final class MitoBackend: ObservableObject {
    static let shared = MitoBackend()

    let client: SupabaseClient

    @Published private(set) var isReady = false
    @Published private(set) var lastError: String?

    private init() {
        client = SupabaseClient(
            supabaseURL: MitoBackendConfig.url,
            supabaseKey: MitoBackendConfig.publishableKey
        )
    }

    func bootstrapExistingSession() async {
        do {
            let session = try await authenticatedSession()
            try await upsertProfile(for: session.user.id, displayName: "Mito Scholar")
            isReady = true
            lastError = nil
        } catch {
            // No stored session yet — open a silent anonymous one so cloud save
            // works without forcing a login. If anonymous auth is disabled on
            // the project, fall back to fully-offline local play.
            do {
                try await signInAnonymously()
            } catch {
                isReady = false
                lastError = nil
            }
        }
    }

    func signUp(email: String, password: String, displayName: String = "Mito Scholar") async throws {
        // If the user is currently anonymous, attach the email + password to
        // that SAME account (link), so their decks, cards and FSRS progress
        // carry over instead of being orphaned under a brand-new user id.
        if let current = client.auth.currentUser, current.isAnonymous {
            _ = try await client.auth.update(user: UserAttributes(email: email, password: password))
            try await upsertProfile(for: current.id, displayName: displayName)
            isReady = true
            lastError = nil
            return
        }

        try await client.auth.signUp(email: email, password: password)
        if let session = try? await client.auth.session {
            try await upsertProfile(for: session.user.id, displayName: displayName)
            isReady = true
            lastError = nil
        }
    }

    func signIn(email: String, password: String, displayName: String = "Mito Scholar") async throws {
        try await client.auth.signIn(email: email, password: password)
        let session = try await client.auth.session
        try await upsertProfile(for: session.user.id, displayName: displayName)
        isReady = true
        lastError = nil
    }

    func signInAnonymously(displayName: String = "Mito Scholar") async throws {
        let session = try await client.auth.signInAnonymously()
        try await upsertProfile(for: session.user.id, displayName: displayName)
        isReady = true
        lastError = nil
    }

    func signOut() async throws {
        try await client.auth.signOut()
        isReady = false
    }

    func recordStudySession(mode: String, durationMinutes: Int, completed: Bool, focusEnergy: Int, coins: Int, gems: Int) async throws {
        let session = try await authenticatedSession()
        let payload = StudySessionInsert(
            userID: session.user.id,
            mode: mode,
            durationMinutes: durationMinutes,
            completed: completed,
            focusEnergy: focusEnergy,
            coins: coins,
            gems: gems
        )

        try await client
            .from("study_sessions")
            .insert(payload)
            .execute()
    }

    // MARK: - Wallet (persisted on profiles)

    /// Load the signed-in player's wallet. Returns nil pre-migration / offline.
    func fetchWallet() async throws -> WalletRecord {
        let session = try await authenticatedSession()
        return try await client
            .from("profiles")
            .select("atp,gold,gems,biomass,shards")
            .eq("id", value: session.user.id.uuidString)
            .single()
            .execute()
            .value
    }

    /// Persist the wallet back onto the player's profile row.
    func saveWallet(atp: Int, gold: Int, gems: Int, biomass: Int, shards: Int) async throws {
        let session = try await authenticatedSession()
        try await client
            .from("profiles")
            .update(WalletRecord(atp: atp, gold: gold, gems: gems, biomass: biomass, shards: shards))
            .eq("id", value: session.user.id.uuidString)
            .execute()
    }

    // MARK: - Activation events

    /// Fire-and-forget analytics event. Never throws — telemetry must not break
    /// the app, and it no-ops cleanly before the events table is migrated in.
    /// Props are string-valued so call sites don't depend on the Supabase types.
    func logEvent(_ name: String, props: [String: String] = [:]) async {
        guard let session = try? await authenticatedSession() else { return }
        let payload = EventInsert(userID: session.user.id, name: name, props: props)
        _ = try? await client.from("events").insert(payload).execute()
    }

    func fetchDecks() async throws -> [MitoDeckRecord] {
        try await client
            .from("decks")
            .select()
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func createDeck(named name: String, category: String = "General") async throws -> MitoDeckRecord {
        let session = try await authenticatedSession()
        let payload = DeckInsert(ownerUserID: session.user.id, name: name, category: category)

        return try await client
            .from("decks")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func createCard(deckID: UUID, front: String, back: String, tags: [String]) async throws -> MitoCardRecord {
        let session = try await authenticatedSession()
        let payload = CardInsert(deckID: deckID, creatorID: session.user.id, front: front, back: back, tags: tags)

        return try await client
            .from("cards")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateCard(id: UUID, front: String, back: String, tags: [String]) async throws {
        _ = try await authenticatedSession()
        try await client
            .from("cards")
            .update(CardUpdate(front: front, back: back, tags: tags))
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Delete a deck and its cards (card_states cascade via FK).
    func deleteDeck(id: UUID) async throws {
        _ = try await authenticatedSession()
        try await client.from("cards").delete().eq("deck_id", value: id.uuidString).execute()
        try await client.from("decks").delete().eq("id", value: id.uuidString).execute()
    }

    /// Delete a single card (its card_states cascade via FK).
    func deleteCard(id: UUID) async throws {
        _ = try await authenticatedSession()
        try await client.from("cards").delete().eq("id", value: id.uuidString).execute()
    }

    // MARK: - Character progress

    func fetchCharacterProgress() async throws -> [CharacterProgressRecord] {
        _ = try await authenticatedSession()
        return try await client
            .from("character_progress")
            .select()
            .execute()
            .value
    }

    func upsertCharacterProgress(characterID: String, level: Int, hp: Int, attack: Int, defense: Int) async throws {
        let session = try await authenticatedSession()
        let payload = CharacterProgressUpsert(
            userID: session.user.id,
            characterID: characterID,
            level: level,
            hp: hp,
            attack: attack,
            defense: defense
        )

        try await client
            .from("character_progress")
            .upsert(payload, onConflict: "user_id,character_id")
            .execute()
    }

    // MARK: - FSRS scheduling sync
    //
    // Mirrors per-user FSRS state to the `card_states` table (see
    // supabase/migrations/0001_card_states.sql). RLS scopes every row to the
    // signed-in user, so the plain selects below only ever return their state.

    /// Push one card's freshly-scheduled FSRS state to the cloud (upsert on
    /// (user_id, card_id)). Safe to call fire-and-forget after each grade.
    func upsertCardState(_ card: ReviewCard) async throws {
        let session = try await authenticatedSession()
        let s = card.sched
        let payload = CardStateUpsert(
            userID: session.user.id,
            cardID: card.id,
            stability: s.memory?.stability,
            difficulty: s.memory?.difficulty,
            phase: s.phase.rawValue,
            due: s.due,
            lastReview: s.lastReview,
            reps: s.reps,
            lapses: s.lapses
        )
        try await client
            .from("card_states")
            .upsert(payload, onConflict: "user_id,card_id")
            .execute()
    }

    /// Load the user's cards joined with any saved FSRS state, ready to feed
    /// into `ReviewSession.ingest(_:)`. Cards without state start fresh.
    func fetchReviewCards(deckIDs: [UUID] = []) async throws -> [ReviewCard] {
        _ = try await authenticatedSession()

        let cardQuery = client.from("cards").select()
        let cards: [MitoCardRecord] = try await (
            deckIDs.isEmpty
                ? cardQuery.execute().value
                : cardQuery.in("deck_id", values: deckIDs.map(\.uuidString)).execute().value
        )

        // Deck names so the picker shows real titles, not raw UUIDs.
        let decks = try await fetchDecks()
        let deckName = Dictionary(decks.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        let states: [CardStateRow] = try await client
            .from("card_states")
            .select()
            .execute()
            .value
        let byCard = Dictionary(states.map { ($0.cardID, $0) }, uniquingKeysWith: { a, _ in a })

        return cards.map { record in
            ReviewCard(
                id: record.id,
                deckID: record.deckID.uuidString,
                deckName: deckName[record.deckID] ?? "Deck",
                front: record.front,
                back: record.back,
                tags: record.tags,
                sched: byCard[record.id]?.scheduling ?? .newCard()
            )
        }
    }

    #if DEBUG
    /// UI-test only: exercise the full cloud loop — grade a card through the
    /// real session, then re-fetch from Supabase to confirm the FSRS state
    /// round-tripped. Returns a human-readable result line.
    func runCloudSelfTest(session: ReviewSession) async -> String {
        do {
            // Auth bootstrap runs concurrently at launch — give it a moment.
            for _ in 0..<40 where !isReady { try? await Task.sleep(nanoseconds: 200_000_000) }
            guard isReady else { return "FAIL: not signed in (anon auth?)" }
            await attachSync(to: session)
            session.start(deckIDs: [])
            guard let card = session.current else { return "FAIL: no card to grade" }
            session.grade(.good)
            try await Task.sleep(nanoseconds: 2_000_000_000) // let the upsert land
            let refreshed = try await fetchReviewCards()
            let match = refreshed.first { $0.id == card.id }
            if let s = match?.sched.memory {
                return "CLOUD OK · card \(card.id) · stability=\(String(format: "%.4f", s.stability)) difficulty=\(String(format: "%.2f", s.difficulty)) · decks=\(Set(refreshed.map(\.deckID)).count) cards=\(refreshed.count)"
            }
            return "FAIL: card_states not found after grade"
        } catch {
            return "ERROR: \(error)"
        }
    }

    /// UI-test only: exercise the exact backend calls the card editor makes —
    /// createDeck → createCard → updateCard → fetchReviewCards — and confirm the
    /// authored card round-trips from Supabase.
    func runCardEditorSelfTest() async -> String {
        do {
            for _ in 0..<40 where !isReady { try? await Task.sleep(nanoseconds: 200_000_000) }
            guard isReady else { return "FAIL: not signed in" }
            // Clean up artifacts from any previous run first.
            if let existing = try? await fetchDecks() {
                for d in existing where d.name == "UITest Deck" { try? await deleteDeck(id: d.id) }
            }
            let deck = try await createDeck(named: "UITest Deck")
            let card = try await createCard(deckID: deck.id, front: "uitest front", back: "uitest back", tags: ["uitest"])
            try await updateCard(id: card.id, front: "uitest front v2", back: "uitest back v2", tags: ["uitest", "edited"])
            let all = try await fetchReviewCards()
            let found = all.first(where: { $0.id == card.id })
            try? await deleteDeck(id: deck.id) // self-cleaning: don't leave test data
            if let m = found {
                return "CARD EDITOR OK · deck=\(deck.name) · card=\(m.id) · front=\"\(m.front)\" · deckName=\"\(m.deckName)\" · tags=\(m.tags) · cleaned up"
            }
            return "FAIL: authored card not found in fetchReviewCards"
        } catch {
            return "ERROR: \(error)"
        }
    }
    #endif

    /// Wire a live `ReviewSession` to the backend: ensure starter content
    /// exists, load remote cards/state, and persist every future grade.
    /// Call once after sign-in.
    func attachSync(to session: ReviewSession, deckIDs: [UUID] = []) async {
        try? await seedStarterContentIfEmpty()
        if let remote = try? await fetchReviewCards(deckIDs: deckIDs), !remote.isEmpty {
            session.ingest(remote, authoritative: true)
        }
        session.onPersist = { card in
            Task { try? await MitoBackend.shared.upsertCardState(card) }
        }
    }

    /// Mirror the bundled starter decks/cards into Supabase the first time a
    /// user has none. Uses fresh per-user UUIDs (decks/cards are owner-scoped,
    /// so ids can't be shared across users) and inserts cards with explicit ids
    /// so `card_states.card_id` resolves. No-op once any deck exists.
    func seedStarterContentIfEmpty() async throws {
        let session = try await authenticatedSession()
        let userID = session.user.id
        guard try await fetchDecks().isEmpty else { return }

        // One fresh deck id per starter deck key, generated for this user.
        let deckMeta: [String: (name: String, category: String)] = [
            "bio":  ("Biology 220", "Biology"),
            "phys": ("Physics formulas", "Physics"),
            "orgo": ("Organic mechanisms", "Chemistry"),
        ]
        var deckID: [String: UUID] = [:]
        let deckPayloads = deckMeta.map { key, meta -> SeedDeckInsert in
            let id = UUID()
            deckID[key] = id
            return SeedDeckInsert(id: id, ownerUserID: userID, name: meta.name, category: meta.category)
        }
        try await client.from("decks").insert(deckPayloads).execute()

        let cardPayloads = SeedContent.cards.compactMap { card -> SeedCardInsert? in
            guard let did = deckID[card.deckID] else { return nil }
            return SeedCardInsert(
                id: UUID(),
                deckID: did,
                creatorID: userID,
                front: card.front,
                back: card.back,
                tags: card.tags
            )
        }
        try await client.from("cards").insert(cardPayloads).execute()
    }

    private func authenticatedSession() async throws -> Session {
        if let session = client.auth.currentSession {
            return session
        }

        do {
            return try await client.auth.session
        } catch {
            throw MitoBackendError.missingSession
        }
    }

    private func upsertProfile(for userID: UUID, displayName: String) async throws {
        let profile = ProfileUpsert(id: userID, displayName: displayName, avatar: "MS")
        try await client
            .from("profiles")
            .upsert(profile)
            .execute()
    }
}

enum MitoBackendError: LocalizedError {
    case missingSession

    var errorDescription: String? {
        switch self {
        case .missingSession:
            "No Supabase session is active. Sign in before writing backend data."
        }
    }
}

struct MitoDeckRecord: Decodable, Identifiable {
    let id: UUID
    let ownerUserID: UUID?
    let ownerRoomID: UUID?
    let name: String
    let category: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case ownerRoomID = "owner_room_id"
        case name
        case category
        case createdAt = "created_at"
    }
}

struct MitoCardRecord: Decodable, Identifiable {
    let id: UUID
    let deckID: UUID
    let creatorID: UUID
    let front: String
    let back: String
    let tags: [String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case deckID = "deck_id"
        case creatorID = "creator_id"
        case front
        case back
        case tags
        case createdAt = "created_at"
    }
}

/// A row of the `card_states` table — the user's FSRS state for one card.
struct CardStateRow: Decodable {
    let cardID: UUID
    let stability: Double?
    let difficulty: Double?
    let phase: Int
    let due: Date
    let lastReview: Date?
    let reps: Int
    let lapses: Int

    enum CodingKeys: String, CodingKey {
        case cardID = "card_id"
        case stability
        case difficulty
        case phase
        case due
        case lastReview = "last_review"
        case reps
        case lapses
    }

    /// Rebuild the FSRS `SchedulingState` this row represents.
    var scheduling: SchedulingState {
        let memory: MemoryState? = {
            guard let stability, let difficulty else { return nil }
            return MemoryState(stability: stability, difficulty: difficulty)
        }()
        return SchedulingState(
            memory: memory,
            phase: CardPhase(rawValue: phase) ?? .new,
            due: due,
            lastReview: lastReview,
            reps: reps,
            lapses: lapses
        )
    }
}

/// Round-trips the wallet columns on `profiles` (Codable both ways).
struct WalletRecord: Codable {
    let atp: Int
    let gold: Int
    let gems: Int
    let biomass: Int
    let shards: Int
}

private struct EventInsert: Encodable {
    let userID: UUID
    let name: String
    let props: [String: String]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name
        case props
    }
}

struct CharacterProgressRecord: Decodable {
    let characterID: String
    let level: Int
    let hp: Int
    let attack: Int
    let defense: Int

    enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
        case level
        case hp
        case attack
        case defense
    }
}

private struct CharacterProgressUpsert: Encodable {
    let userID: UUID
    let characterID: String
    let level: Int
    let hp: Int
    let attack: Int
    let defense: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case characterID = "character_id"
        case level
        case hp
        case attack
        case defense
    }
}

private struct CardStateUpsert: Encodable {
    let userID: UUID
    let cardID: UUID
    let stability: Double?
    let difficulty: Double?
    let phase: Int
    let due: Date
    let lastReview: Date?
    let reps: Int
    let lapses: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case cardID = "card_id"
        case stability
        case difficulty
        case phase
        case due
        case lastReview = "last_review"
        case reps
        case lapses
    }
}

/// Deck insert with an explicit id, for deterministic starter seeding.
private struct SeedDeckInsert: Encodable {
    let id: UUID
    let ownerUserID: UUID
    let name: String
    let category: String

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case name
        case category
    }
}

/// Card insert with an explicit id (matching the local SeedContent card id).
private struct SeedCardInsert: Encodable {
    let id: UUID
    let deckID: UUID
    let creatorID: UUID
    let front: String
    let back: String
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case deckID = "deck_id"
        case creatorID = "creator_id"
        case front
        case back
        case tags
    }
}

private struct ProfileUpsert: Encodable {
    let id: UUID
    let displayName: String
    let avatar: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatar
    }
}

private struct StudySessionInsert: Encodable {
    let userID: UUID
    let mode: String
    let durationMinutes: Int
    let completed: Bool
    let focusEnergy: Int
    let coins: Int
    let gems: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case mode
        case durationMinutes = "duration_minutes"
        case completed
        case focusEnergy = "focus_energy"
        case coins
        case gems
    }
}

private struct DeckInsert: Encodable {
    let ownerUserID: UUID
    let name: String
    let category: String

    enum CodingKeys: String, CodingKey {
        case ownerUserID = "owner_user_id"
        case name
        case category
    }
}

private struct CardInsert: Encodable {
    let deckID: UUID
    let creatorID: UUID
    let front: String
    let back: String
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case deckID = "deck_id"
        case creatorID = "creator_id"
        case front
        case back
        case tags
    }
}

private struct CardUpdate: Encodable {
    let front: String
    let back: String
    let tags: [String]
}
