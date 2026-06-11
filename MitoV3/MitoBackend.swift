import Foundation
import Combine
import Security
import Supabase

enum MitoBackendConfig {
    static let projectRef = "ncnkvgpulnalauzxvfoh"
    static let url = URL(string: "https://ncnkvgpulnalauzxvfoh.supabase.co")!
    static let publishableKey = "sb_publishable_o3SwMMi_ao7IkVuV-azqxg_beGzmWzi"
}

/// Keychain-backed auth session store with a UserDefaults fallback.
///
/// supabase-swift's default Keychain storage fails silently in the Simulator /
/// without a keychain entitlement, which is why this app originally persisted
/// sessions in UserDefaults — but that leaves the refresh token in a plaintext
/// plist that is included in device backups. This store writes our own
/// kSecClassGenericPassword items (no entitlement needed for an app's own
/// items, device-only so tokens never leave via backup), falls back to
/// UserDefaults only if a keychain call fails (Simulator edge cases), and
/// transparently migrates sessions saved by the old UserDefaults store.
struct MitoAuthStorage: AuthLocalStorage {
    private let service = "com.yukinabe.mitov3.auth"
    private let defaults = UserDefaults.standard

    func store(key: String, value: Data) throws {
        let query = baseQuery(key: key)
        let status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = value
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
                defaults.set(value, forKey: key)
                return
            }
        } else if status != errSecSuccess {
            defaults.set(value, forKey: key)
            return
        }
        // Keychain write succeeded — never leave a stale plaintext copy behind.
        defaults.removeObject(forKey: key)
    }

    func retrieve(key: String) throws -> Data? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data {
            return data
        }
        // Session saved by the old UserDefaults store (or keychain fallback):
        // return it and promote it into the keychain.
        if let legacy = defaults.data(forKey: key) {
            try? store(key: key, value: legacy)
            return legacy
        }
        return nil
    }

    func remove(key: String) throws {
        SecItemDelete(baseQuery(key: key) as CFDictionary)
        defaults.removeObject(forKey: key)
    }

    private func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

@MainActor
final class MitoBackend: ObservableObject {
    static let shared = MitoBackend()

    let client: SupabaseClient

    @Published private(set) var isReady = false
    @Published private(set) var lastError: String?
    /// The email of the signed-in account, or nil when anonymous / offline.
    /// Drives the "signed in as…" UI so a real login is distinguishable from
    /// the silent anonymous session that backs offline play.
    @Published private(set) var accountEmail: String?

    /// True only for a real (email) account — NOT the anonymous session.
    var isLoggedIn: Bool { accountEmail != nil }

    /// Sync `accountEmail` from the current Supabase user (anonymous → nil).
    private func refreshAccountState() {
        let user = client.auth.currentUser
        if let user, user.isAnonymous == false, let email = user.email, !email.isEmpty {
            accountEmail = email
        } else {
            accountEmail = nil
        }
    }

    private init() {
        // IMPORTANT: supabase-swift defaults to Keychain session storage, which
        // silently fails in the Simulator / apps without a keychain entitlement —
        // the session never persists, so every authenticated call goes out
        // unauthenticated (manifesting as profiles RLS 42501 / missingSession and
        // the whole cloud layer falling back to offline). MitoAuthStorage writes
        // our own keychain items (with a UserDefaults fallback for the Simulator)
        // so sessions reliably persist without keeping tokens in a plaintext plist.
        client = SupabaseClient(
            supabaseURL: MitoBackendConfig.url,
            supabaseKey: MitoBackendConfig.publishableKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: MitoAuthStorage()
                )
            )
        )
    }

    func bootstrapExistingSession() async {
        do {
            let session = try await authenticatedSession()
            try? await upsertProfile(for: session.user.id, displayName: "Mito Scholar")
            isReady = true
            lastError = nil
            refreshAccountState()
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
            refreshAccountState()
            return
        }

        try await client.auth.signUp(email: email, password: password)
        if let session = try? await client.auth.session {
            try await upsertProfile(for: session.user.id, displayName: displayName)
            isReady = true
            lastError = nil
        }
        refreshAccountState()
    }

    func signIn(email: String, password: String, displayName: String = "Mito Scholar") async throws {
        try await client.auth.signIn(email: email, password: password)
        let session = try await client.auth.session
        try await upsertProfile(for: session.user.id, displayName: displayName)
        isReady = true
        lastError = nil
        refreshAccountState()
    }

    func signInAnonymously(displayName: String = "Mito Scholar") async throws {
        let session = try await client.auth.signInAnonymously()
        // Profile creation is best-effort: a profiles RLS/trigger hiccup must not
        // disable the whole cloud layer (cards/FSRS/AI don't depend on it).
        try? await upsertProfile(for: session.user.id, displayName: displayName)
        isReady = true
        lastError = nil
        refreshAccountState()
    }

    func signOut() async throws {
        try await client.auth.signOut()
        isReady = false
        accountEmail = nil
        // Re-open a silent anonymous session so offline play + local sync keep
        // working after logout (matches first-launch behaviour).
        try? await signInAnonymously()
    }

    /// Permanently delete the signed-in account and all server-side data
    /// (required by App Store Guideline 5.1.1(v)). The `delete_account` RPC
    /// (migration 0011) removes the auth.users row as the caller; owner-keyed
    /// rows cascade. Sign-out is local-only — the server session is already
    /// gone once the user row is deleted.
    func deleteAccount() async throws {
        _ = try await authenticatedSession()
        try await client.rpc("delete_account").execute()
        try? await client.auth.signOut(scope: .local)
        isReady = false
        accountEmail = nil
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

    // MARK: - Waitlist / invite

    /// Capture a waitlist/invite submission against the current (anon) user.
    /// Best-effort: returns true on a successful write, false on failure so the
    /// gate can still admit a valid code even if the network is down.
    @discardableResult
    func submitWaitlist(email: String, referral: String, inviteCode: String, cohort: String) async -> Bool {
        guard let session = try? await authenticatedSession() else { return false }
        let payload = WaitlistInsert(
            userID: session.user.id,
            email: email.isEmpty ? nil : email,
            referralSource: referral.isEmpty ? nil : referral,
            inviteCode: inviteCode.isEmpty ? nil : inviteCode,
            cohort: cohort
        )
        do {
            try await client.from("waitlist").upsert(payload, onConflict: "user_id").execute()
            return true
        } catch {
            return false
        }
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
        // Editing content invalidates any cached distractors — clear them so the
        // next generation pass rebuilds against the new answer.
        try await client
            .from("cards")
            .update(CardUpdate(front: front, back: back, tags: tags, choices: []))
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Persist freshly-generated multiple-choice distractors for one card.
    func updateCardChoices(id: UUID, choices: [String]) async throws {
        _ = try await authenticatedSession()
        try await client
            .from("cards")
            .update(CardChoicesUpdate(choices: choices))
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

    // MARK: - Friends
    //
    // Backed by supabase/migrations/0008_friends.sql (friendships table +
    // friend_code on profiles + get_friends / find_profile_by_friend_code RPCs).

    /// The signed-in user's id, if any (synchronous, cached session).
    var currentUserID: UUID? { client.auth.currentSession?.user.id }

    /// The signed-in user's display name (from their profile; falls back).
    func myDisplayName() async -> String {
        guard let id = currentUserID else { return "Scholar" }
        struct Row: Decodable { let display_name: String? }
        let row: Row? = try? await client.from("profiles")
            .select("display_name").eq("id", value: id.uuidString)
            .single().execute().value
        return row?.display_name ?? "Scholar"
    }

    /// This user's shareable friend code (generates lazily if missing).
    func myFriendCode() async throws -> String {
        let session = try await authenticatedSession()
        struct Row: Decodable { let friend_code: String? }
        let row: Row = try await client.from("profiles")
            .select("friend_code").eq("id", value: session.user.id.uuidString)
            .single().execute().value
        return row.friend_code ?? ""
    }

    /// Look up a profile by its friend code (security-definer RPC).
    func findFriend(byCode code: String) async throws -> FriendProfile? {
        _ = try await authenticatedSession()
        let rows: [FriendProfile] = try await client
            .rpc("find_profile_by_friend_code", params: ["code": code])
            .execute().value
        return rows.first
    }

    /// Send a friend request to a user id.
    func sendFriendRequest(to userID: UUID) async throws {
        let session = try await authenticatedSession()
        let payload = FriendshipInsert(requester: session.user.id, addressee: userID)
        try await client.from("friendships").insert(payload).execute()
    }

    /// Accept an incoming request (I'm the addressee; flip the row to accepted).
    func acceptFriendRequest(from requester: UUID) async throws {
        let session = try await authenticatedSession()
        try await client.from("friendships")
            .update(["status": "accepted"])
            .eq("requester", value: requester.uuidString)
            .eq("addressee", value: session.user.id.uuidString)
            .execute()
    }

    /// Remove a friend / cancel a request in either direction.
    func removeFriend(_ other: UUID) async throws {
        let session = try await authenticatedSession()
        let me = session.user.id.uuidString
        let them = other.uuidString
        try await client.from("friendships").delete()
            .or("and(requester.eq.\(me),addressee.eq.\(them)),and(requester.eq.\(them),addressee.eq.\(me))")
            .execute()
    }

    /// This week's focus-minutes league across me + accepted friends
    /// (get_friend_league RPC, migration 0012). Rows arrive pre-ranked.
    func fetchLeague() async throws -> [LeagueRow] {
        _ = try await authenticatedSession()
        return try await client.rpc("get_friend_league").execute().value
    }

    // MARK: - Classes (study groups + shared decks)
    //
    // Backed by supabase/migrations/0013_classes.sql. Every call is a
    // security-definer RPC that enforces membership server-side; the free-tier
    // caps (join 3 / create 1) are enforced client-side against Mito+.

    /// All classes I'm a member of, with member counts.
    func fetchMyClasses() async throws -> [ClassRecord] {
        _ = try await authenticatedSession()
        return try await client.rpc("get_my_classes").execute().value
    }

    /// Create a class and become its owner. Returns the new class + join code.
    func createClass(name: String) async throws -> CreatedClass {
        _ = try await authenticatedSession()
        let rows: [CreatedClass] = try await client
            .rpc("create_class", params: ["p_name": name]).execute().value
        guard let first = rows.first else { throw MitoBackendError.noResult }
        return first
    }

    /// Join a class by code. Returns nil if no class has that code.
    func joinClass(code: String) async throws -> JoinedClass? {
        _ = try await authenticatedSession()
        let rows: [JoinedClass] = try await client
            .rpc("join_class", params: ["p_code": code.uppercased()]).execute().value
        return rows.first
    }

    /// Leave a class (owner leaving deletes it).
    func leaveClass(_ id: UUID) async throws {
        _ = try await authenticatedSession()
        try await client.rpc("leave_class", params: ["p_class_id": id.uuidString]).execute()
    }

    /// Roster of a class I belong to.
    func fetchClassRoster(_ id: UUID) async throws -> [ClassRosterEntry] {
        _ = try await authenticatedSession()
        return try await client
            .rpc("get_class_roster", params: ["p_class_id": id.uuidString]).execute().value
    }

    /// Shared decks in a class I belong to.
    func fetchClassDecks(_ id: UUID) async throws -> [ClassDeckRecord] {
        _ = try await authenticatedSession()
        return try await client
            .rpc("get_class_decks", params: ["p_class_id": id.uuidString]).execute().value
    }

    /// Cards of a shared class deck (for preview / copying).
    func fetchClassDeckCards(_ classDeckID: UUID) async throws -> [ClassCardRecord] {
        _ = try await authenticatedSession()
        return try await client
            .rpc("get_class_deck_cards", params: ["p_class_deck_id": classDeckID.uuidString])
            .execute().value
    }

    /// Snapshot one of my decks into a class for everyone to copy.
    @discardableResult
    func shareDeckToClass(classID: UUID, name: String, cards: [ClassCardPayload]) async throws -> UUID {
        _ = try await authenticatedSession()
        let params = ShareDeckParams(p_class_id: classID.uuidString, p_name: name, p_cards: cards)
        return try await client.rpc("share_deck_to_class", params: params).execute().value
    }

    /// All my relationships with names + status + direction (get_friends RPC).
    func fetchFriends() async throws -> [FriendEdge] {
        _ = try await authenticatedSession()
        return try await client.rpc("get_friends").execute().value
    }

    // MARK: - Lobbies (co-op + PvP)
    //
    // Durable membership lives in lobbies/lobby_members (0009_lobbies.sql); the
    // live roster + in-game events ride Supabase Realtime (see LobbyService).

    /// Create a lobby with a fresh join code and join it as host.
    @discardableResult
    func createLobby(mode: String, deckID: UUID? = nil, characterIDs: [String]) async throws -> LobbyRecord {
        let session = try await authenticatedSession()
        let code = Self.makeLobbyCode()
        let payload = LobbyInsert(code: code, host: session.user.id, mode: mode, deckID: deckID)
        let lobby: LobbyRecord = try await client.from("lobbies")
            .insert(payload).select().single().execute().value
        try await client.from("lobby_members")
            .insert(LobbyMemberInsert(lobbyID: lobby.id, userID: session.user.id, characterIDs: characterIDs))
            .execute()
        return lobby
    }

    /// Join a lobby by code (one-shot RPC). Returns the lobby id, or nil if no
    /// open lobby has that code.
    func joinLobby(code: String, characterIDs: [String]) async throws -> UUID? {
        _ = try await authenticatedSession()
        let params = JoinLobbyParams(p_code: code.uppercased(), p_character_ids: characterIDs)
        let id: UUID? = try await client.rpc("join_lobby", params: params).execute().value
        return id
    }

    /// Fetch a lobby record by code (visible if you're host or a member).
    func fetchLobby(code: String) async throws -> LobbyRecord? {
        _ = try await authenticatedSession()
        let rows: [LobbyRecord] = try await client.from("lobbies")
            .select().eq("code", value: code.uppercased()).limit(1).execute().value
        return rows.first
    }

    /// Leave a lobby (remove my membership row).
    func leaveLobby(_ lobbyID: UUID) async throws {
        let session = try await authenticatedSession()
        try await client.from("lobby_members").delete()
            .eq("lobby_id", value: lobbyID.uuidString)
            .eq("user_id", value: session.user.id.uuidString)
            .execute()
    }

    /// Host closes the lobby (cascades members).
    func closeLobby(_ lobbyID: UUID) async throws {
        _ = try await authenticatedSession()
        try await client.from("lobbies").delete().eq("id", value: lobbyID.uuidString).execute()
    }

    /// Record a finished PvP duel (bragging rights only — no FSRS impact).
    func recordPvPResult(lobbyID: UUID?, deckID: UUID?, opponent: UUID, didWin: Bool) async throws {
        let session = try await authenticatedSession()
        let me = session.user.id
        let payload = PvPMatchInsert(
            lobbyID: lobbyID, deckID: deckID,
            playerA: me, playerB: opponent,
            winner: didWin ? me : opponent)
        try await client.from("pvp_matches").insert(payload).execute()
    }

    /// 5-char join code from an ambiguity-free alphabet.
    static func makeLobbyCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<5).map { _ in alphabet.randomElement()! })
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
                sched: byCard[record.id]?.scheduling ?? .newCard(),
                choices: (record.choices?.isEmpty == false) ? record.choices : nil
            )
        }
    }

    // MARK: - AI (DeepSeek via the `mito-ai` Edge Function)
    //
    // The DeepSeek key never ships in the app: requests go to a Supabase Edge
    // Function (`supabase/functions/mito-ai`) that holds the key as a secret and
    // is authenticated with the user's JWT (attached automatically by the SDK).

    struct AIGrade: Sendable {
        let rating: Rating
        let confidence: Double
        let feedback: String?
    }

    /// Ask the AI for `count` plausible-but-wrong multiple-choice distractors for
    /// a card. The card is referenced by id only — the edge function reads its
    /// text server-side (so the model can't be fed arbitrary prompts). `correct`
    /// is passed only to strip accidental collisions locally. Throws on
    /// network/auth/parse failure so callers can fall back.
    func generateDistractors(cardID: UUID, correct: String, count: Int = 3) async throws -> [String] {
        _ = try await authenticatedSession()
        let req = AIRequest(task: "distractors", cardId: cardID,
                            count: count, userAnswer: nil, elapsedMs: nil, signals: nil)
        let out: DistractorsResponse = try await client.functions.invoke(
            "mito-ai",
            options: FunctionInvokeOptions(body: req)
        ) { data, _ in try JSONDecoder().decode(DistractorsResponse.self, from: data) }
        // Drop anything that collides with the real answer.
        let correctKey = AnswerGrading.normalize(correct)
        return out.distractors
            .filter { AnswerGrading.normalize($0) != correctKey }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Grade a typed answer for a card (referenced by id; the correct answer is
    /// read server-side). Timing/hesitation are secondary evidence. Throws so
    /// callers can fall back to the local similarity grader when offline.
    func gradeTypedAnswer(cardID: UUID, userAnswer: String,
                          elapsedMs: Int, signals: TypingSignals) async throws -> AIGrade {
        _ = try await authenticatedSession()
        let req = AIRequest(task: "grade", cardId: cardID,
                            count: nil, userAnswer: userAnswer, elapsedMs: elapsedMs, signals: signals)
        let out: GradeResponse = try await client.functions.invoke(
            "mito-ai",
            options: FunctionInvokeOptions(body: req)
        ) { data, _ in try JSONDecoder().decode(GradeResponse.self, from: data) }
        let rating = Rating(rawValue: max(1, min(4, out.rating))) ?? .good
        return AIGrade(rating: rating, confidence: out.confidence ?? 0, feedback: out.feedback)
    }

    /// Best-effort: generate + persist distractors for any cards missing them.
    /// Safe to fire-and-forget when the player picks multiple-choice mode.
    func backfillDistractors(for cards: [ReviewCard]) async {
        for card in cards where (card.choices?.isEmpty ?? true) {
            guard let distractors = try? await generateDistractors(
                cardID: card.id, correct: card.back), !distractors.isEmpty
            else { continue }
            try? await updateCardChoices(id: card.id, choices: distractors)
        }
    }

    #if DEBUG
    /// UI-test only: exercise the AI edge function both ways.
    func runAISelfTest() async -> String {
        do {
            for _ in 0..<25 where !isReady { try? await Task.sleep(nanoseconds: 200_000_000) }
            if !isReady {
                // Force a session and surface the real reason if it fails.
                do { try await signInAnonymously() }
                catch { return "SIGNIN ERROR: \(error)" }
            }
            guard isReady else { return "FAIL: still not signed in after retry" }
            try await seedStarterContentIfEmpty()
            let cards = try await fetchReviewCards()
            guard let card = cards.first else { return "FAIL: no cards to test against" }
            let distractors = try await generateDistractors(cardID: card.id, correct: card.back)
            let grade = try await gradeTypedAnswer(
                cardID: card.id, userAnswer: card.back,
                elapsedMs: 3200, signals: TypingSignals(elapsedMs: 3200, timeToFirstKeystrokeMs: 800, deletions: 0, keystrokes: 3))
            return "AI OK · card=\(card.id) · distractors=\(distractors) · grade=\(grade.rating) conf=\(String(format: "%.2f", grade.confidence)) fb=\"\(grade.feedback ?? "")\""
        } catch {
            return "ERROR: \(error)"
        }
    }

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
    case noResult

    var errorDescription: String? {
        switch self {
        case .missingSession:
            "No Supabase session is active. Sign in before writing backend data."
        case .noResult:
            "The server returned no result."
        }
    }
}

// MARK: - Classes models

/// A class I belong to (get_my_classes RPC).
struct ClassRecord: Decodable, Identifiable {
    let id: UUID
    let code: String
    let name: String
    let owner: UUID?
    let member_count: Int
    let is_owner: Bool
}

/// Result of create_class.
struct CreatedClass: Decodable {
    let id: UUID
    let code: String
    let name: String
}

/// Result of join_class.
struct JoinedClass: Decodable {
    let id: UUID
    let name: String
}

/// One member in a class roster (get_class_roster RPC).
struct ClassRosterEntry: Decodable, Identifiable {
    let user_id: UUID
    let display_name: String?
    let role: String
    var id: UUID { user_id }
    var displayName: String { display_name ?? "Scholar" }
    var isOwner: Bool { role == "owner" }
}

/// A deck shared into a class (get_class_decks RPC).
struct ClassDeckRecord: Decodable, Identifiable {
    let id: UUID
    let name: String
    let shared_by_name: String?
    let card_count: Int
    var sharedBy: String { shared_by_name ?? "Scholar" }
}

/// One card of a shared class deck (get_class_deck_cards RPC).
struct ClassCardRecord: Decodable {
    let front: String
    let back: String
    let tags: [String]
}

/// One card sent up when sharing a deck into a class.
struct ClassCardPayload: Encodable {
    let front: String
    let back: String
    let tags: [String]
}

private struct ShareDeckParams: Encodable {
    let p_class_id: String
    let p_name: String
    let p_cards: [ClassCardPayload]
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
    /// Cached multiple-choice distractors (optional: absent on pre-migration rows).
    let choices: [String]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case deckID = "deck_id"
        case creatorID = "creator_id"
        case front
        case back
        case tags
        case choices
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

private struct WaitlistInsert: Encodable {
    let userID: UUID
    let email: String?
    let referralSource: String?
    let inviteCode: String?
    let cohort: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email
        case referralSource = "referral_source"
        case inviteCode = "invite_code"
        case cohort
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
    let choices: [String]
}

private struct CardChoicesUpdate: Encodable {
    let choices: [String]
}

// MARK: - Friends

/// A profile found by friend code (find_profile_by_friend_code RPC).
struct FriendProfile: Decodable, Identifiable {
    let id: UUID
    let display_name: String?
    let friend_code: String?
    var displayName: String { display_name ?? "Scholar" }
    var friendCode: String { friend_code ?? "" }
}

/// One ranked row of the weekly friends league (get_friend_league RPC).
struct LeagueRow: Decodable, Identifiable {
    let user_id: UUID
    let display_name: String?
    let minutes: Int
    let is_me: Bool

    var id: UUID { user_id }
    var displayName: String { display_name ?? "Scholar" }
}

/// One relationship row from the get_friends RPC.
struct FriendEdge: Decodable, Identifiable {
    let friend_id: UUID
    let display_name: String?
    let friend_code: String?
    let status: String          // "pending" | "accepted"
    let direction: String       // "incoming" | "outgoing"

    var id: UUID { friend_id }
    var displayName: String { display_name ?? "Scholar" }
    var isAccepted: Bool { status == "accepted" }
    var isIncomingRequest: Bool { status == "pending" && direction == "incoming" }
    var isOutgoingRequest: Bool { status == "pending" && direction == "outgoing" }
}

private struct FriendshipInsert: Encodable {
    let requester: UUID
    let addressee: UUID
}

// MARK: - Lobbies

struct LobbyRecord: Decodable, Identifiable {
    let id: UUID
    let code: String
    let host: UUID
    let mode: String
    let deckID: UUID?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, code, host, mode, status
        case deckID = "deck_id"
    }
}

private struct LobbyInsert: Encodable {
    let code: String
    let host: UUID
    let mode: String
    let deckID: UUID?
    enum CodingKeys: String, CodingKey {
        case code, host, mode
        case deckID = "deck_id"
    }
}

private struct LobbyMemberInsert: Encodable {
    let lobbyID: UUID
    let userID: UUID
    let characterIDs: [String]
    enum CodingKeys: String, CodingKey {
        case lobbyID = "lobby_id"
        case userID = "user_id"
        case characterIDs = "character_ids"
    }
}

private struct JoinLobbyParams: Encodable {
    let p_code: String
    let p_character_ids: [String]
}

private struct PvPMatchInsert: Encodable {
    let lobbyID: UUID?
    let deckID: UUID?
    let playerA: UUID
    let playerB: UUID
    let winner: UUID
    enum CodingKeys: String, CodingKey {
        case lobbyID = "lobby_id"
        case deckID = "deck_id"
        case playerA = "player_a"
        case playerB = "player_b"
        case winner
    }
}

// MARK: - AI edge-function payloads

private struct AIRequest: Encodable {
    let task: String              // "distractors" | "grade"
    let cardId: UUID              // card looked up server-side; never card text
    let count: Int?
    let userAnswer: String?
    let elapsedMs: Int?
    let signals: TypingSignals?
}

private struct DistractorsResponse: Decodable {
    let distractors: [String]
}

private struct GradeResponse: Decodable {
    let rating: Int               // 1...4
    let confidence: Double?
    let feedback: String?
}
