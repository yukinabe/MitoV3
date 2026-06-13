//  BackendModels.swift
//  Decodable/Encodable DTOs for MitoBackend / Supabase RPCs.
//  Extracted from MitoBackend.swift (behavior-preserving refactor, refactor/architecture).

import Foundation

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

struct ShareDeckParams: Encodable {
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

struct EventInsert: Encodable {
    let userID: UUID
    let name: String
    let props: [String: String]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name
        case props
    }
}

struct WaitlistInsert: Encodable {
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

struct CharacterProgressUpsert: Encodable {
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

struct CardStateUpsert: Encodable {
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
struct SeedDeckInsert: Encodable {
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
struct SeedCardInsert: Encodable {
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

struct ProfileUpsert: Encodable {
    let id: UUID
    let displayName: String
    let avatar: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatar
    }
}

struct StudySessionInsert: Encodable {
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

struct DeckInsert: Encodable {
    let ownerUserID: UUID
    let name: String
    let category: String

    enum CodingKeys: String, CodingKey {
        case ownerUserID = "owner_user_id"
        case name
        case category
    }
}

struct CardInsert: Encodable {
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

struct CardUpdate: Encodable {
    let front: String
    let back: String
    let tags: [String]
    let choices: [String]
}

struct CardChoicesUpdate: Encodable {
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

struct FriendshipInsert: Encodable {
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

struct LobbyInsert: Encodable {
    let code: String
    let host: UUID
    let mode: String
    let deckID: UUID?
    enum CodingKeys: String, CodingKey {
        case code, host, mode
        case deckID = "deck_id"
    }
}

struct LobbyMemberInsert: Encodable {
    let lobbyID: UUID
    let userID: UUID
    let characterIDs: [String]
    enum CodingKeys: String, CodingKey {
        case lobbyID = "lobby_id"
        case userID = "user_id"
        case characterIDs = "character_ids"
    }
}

struct JoinLobbyParams: Encodable {
    let p_code: String
    let p_character_ids: [String]
}

struct PvPMatchInsert: Encodable {
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

struct AIRequest: Encodable {
    let task: String              // "distractors" | "grade"
    let cardId: UUID              // card looked up server-side; never card text
    let count: Int?
    let userAnswer: String?
    let elapsedMs: Int?
    let signals: TypingSignals?
}

struct DistractorsResponse: Decodable {
    let distractors: [String]
}

struct GradeResponse: Decodable {
    let rating: Int               // 1...4
    let confidence: Double?
    let feedback: String?
}
