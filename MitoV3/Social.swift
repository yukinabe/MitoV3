//  Social.swift
//  Extracted from ContentView.swift (behavior-preserving refactor).

import SwiftUI
import Supabase

struct FriendsView: View {
    @ObservedObject var backend: MitoBackend
    @Binding var isPresented: Bool

    @AppStorage("premium.social") private var premium = false
    @State private var myCode = "…"
    @State private var addCode = ""
    @State private var friends: [FriendEdge] = []
    @State private var league: [LeagueRow] = []
    @State private var message = ""
    @State private var loading = false
    @State private var showingLobby = false

    private var accepted: [FriendEdge] { friends.filter(\.isAccepted) }
    private var incoming: [FriendEdge] { friends.filter(\.isIncomingRequest) }
    private var outgoing: [FriendEdge] { friends.filter(\.isOutgoingRequest) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.64).ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text("FRIENDS")
                        .pixelText(size: 17, color: Color(hex: "3A2A18"))
                    Spacer()
                    Button { isPresented = false } label: {
                        Text("X").pixelText(size: 13, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                if !BetaConfig.premiumActive {
                    paywall
                } else if !backend.isReady {
                    Text("Sign in (Settings → Login) to use friends and co-op.")
                        .font(.custom(MitoFont.regular, size: 14))
                        .foregroundStyle(Color(hex: "6B4324"))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 20)
                } else {
                    content
                }
            }
            .padding(16)
            .frame(width: 340)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))

            if showingLobby {
                LobbyView(backend: backend, isPresented: $showingLobby)
            }
        }
        .task { await load() }
    }

    private var paywall: some View {
        VStack(spacing: 12) {
            Text("✦ MITO+ ✦").pixelText(size: 16, color: Color(hex: "B8860B"))
            Text("Study with friends. Unlock co-op focus sessions, shared endless runs, and head-to-head deck duels.")
                .font(.custom(MitoFont.regular, size: 14))
                .foregroundStyle(Color(hex: "4A2F1C"))
                .multilineTextAlignment(.center)
            VStack(spacing: 6) {
                Label("Friends & lobbies", systemImage: "person.2.fill")
                Label("Co-op focus + endless", systemImage: "bolt.heart.fill")
                Label("PvP deck duels", systemImage: "flag.checkered")
            }
            .font(.custom(MitoFont.regular, size: 13))
            .foregroundStyle(Color(hex: "4A2F1C"))
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                // TODO: replace with RevenueCat purchase. Dev unlock for now.
                premium = true
                Haptics.success()
            } label: {
                Text("UNLOCK MITO+")
                    .pixelText(size: 14, color: .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Color(hex: "B8860B"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
            Text("Payments coming soon — this dev build unlocks instantly.")
                .font(.custom(MitoFont.regular, size: 11))
                .foregroundStyle(Color(hex: "6B4324"))
        }
        .padding(.vertical, 6)
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                // My code
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR FRIEND CODE").pixelText(size: 9, color: Color(hex: "6B4324"))
                    HStack(spacing: 10) {
                        Text(myCode)
                            .pixelText(size: 22, color: Color(hex: "3A2A18"))
                            .textSelection(.enabled)
                        Spacer()
                        if !myCode.isEmpty {
                            ShareLink(item: "Study with me on Mito, the pixel study RPG! 🔥 Add me with friend code \(myCode) — we can run co-op focus sessions and deck duels.") {
                                Text("INVITE")
                                    .pixelText(size: 11, color: .white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .background(Color(hex: "4A7BA8"))
                                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Add by code
                VStack(alignment: .leading, spacing: 6) {
                    Text("ADD A FRIEND").pixelText(size: 9, color: Color(hex: "6B4324"))
                    HStack(spacing: 8) {
                        TextField("CODE", text: $addCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .authInputStyle()
                        Button { Task { await add() } } label: {
                            Text("ADD").pixelText(size: 12, color: .white)
                                .padding(.horizontal, 14).frame(height: 40)
                                .background(Color(hex: "4A8A3C"))
                                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !message.isEmpty {
                    Text(message).font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
                }

                if !incoming.isEmpty {
                    sectionHeader("REQUESTS")
                    ForEach(incoming) { edge in
                        friendRow(edge, trailing: AnyView(
                            Button { Task { await accept(edge) } } label: {
                                Text("ACCEPT").pixelText(size: 10, color: .white)
                                    .padding(.horizontal, 10).frame(height: 30)
                                    .background(Color(hex: "4A8A3C"))
                                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                            }.buttonStyle(.plain)
                        ))
                    }
                }

                sectionHeader("FRIENDS (\(accepted.count))")
                if loading && friends.isEmpty {
                    HStack { Spacer(); ProgressView().tint(Color(hex: "6B4324")); Spacer() }
                        .padding(.vertical, 6)
                } else if accepted.isEmpty {
                    Text("No friends yet — share your code above.")
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
                }
                ForEach(accepted) { edge in
                    friendRow(edge, trailing: AnyView(
                        Text("ONLINE?").pixelText(size: 8, color: Color(hex: "8A6B42"))
                    ))
                }

                if !outgoing.isEmpty {
                    sectionHeader("PENDING")
                    ForEach(outgoing) { edge in
                        friendRow(edge, trailing: AnyView(
                            Text("SENT").pixelText(size: 9, color: Color(hex: "8A6B42"))
                        ))
                    }
                }

                // Weekly league: focus minutes, me + accepted friends, resets Monday.
                if league.count > 1 {
                    sectionHeader("THIS WEEK'S LEAGUE")
                    ForEach(Array(league.enumerated()), id: \.element.id) { rank, row in
                        HStack(spacing: 8) {
                            Text(rank == 0 ? "👑" : "#\(rank + 1)")
                                .pixelText(size: 11, color: rank == 0 ? Color(hex: "C8881A") : Color(hex: "8A6B42"))
                                .frame(width: 32, alignment: .leading)
                            Text(row.is_me ? "\(row.displayName) (you)" : row.displayName)
                                .font(.custom(row.is_me ? MitoFont.bold : MitoFont.regular, size: 15))
                                .foregroundStyle(Color(hex: "3A2A18"))
                            Spacer()
                            Text("\(row.minutes) MIN")
                                .pixelText(size: 10, color: Color(hex: "3A2A18"))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(hex: row.is_me ? "F7C943" : "DCC79A").opacity(row.is_me ? 0.55 : 1))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    Text("Focus minutes this week. Resets Monday.")
                        .font(.custom(MitoFont.regular, size: 11))
                        .foregroundStyle(Color(hex: "6B4324"))
                }

                // Co-op & versus entry point → lobby (realtime presence).
                sectionHeader("CO-OP & VERSUS")
                Button { showingLobby = true } label: {
                    Text("OPEN LOBBY").pixelText(size: 13, color: .white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color(hex: "4A7BA8"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                Text("Study together (your friends' characters join your meadow) or duel a deck head-to-head. Needs migrations 0008/0009 deployed.")
                    .font(.custom(MitoFont.regular, size: 11))
                    .foregroundStyle(Color(hex: "6B4324"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 420)
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t).pixelText(size: 10, color: Color(hex: "3A2A18"))
            .padding(.top, 4)
    }

    private func friendRow(_ edge: FriendEdge, trailing: AnyView) -> some View {
        HStack {
            Text(edge.displayName).font(.custom(MitoFont.regular, size: 15))
                .foregroundStyle(Color(hex: "3A2A18"))
            Spacer()
            trailing
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(hex: "DCC79A"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }

    private func load() async {
        guard BetaConfig.premiumActive, backend.isReady, !loading else { return }
        loading = true; defer { loading = false }
        myCode = (try? await backend.myFriendCode()) ?? "—"
        friends = (try? await backend.fetchFriends()) ?? []
        league = (try? await backend.fetchLeague()) ?? []
    }

    private func add() async {
        let code = addCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count >= 4 else { message = "Enter a friend code."; return }
        do {
            guard let found = try await backend.findFriend(byCode: code) else {
                message = "No scholar with that code."; return
            }
            try await backend.sendFriendRequest(to: found.id)
            message = "Request sent to \(found.displayName)."
            addCode = ""
            await load()
        } catch {
            message = "Couldn't send request."
        }
    }

    private func accept(_ edge: FriendEdge) async {
        try? await backend.acceptFriendRequest(from: edge.friend_id)
        await load()
    }
}

// MARK: - Lobby realtime service

/// One member's live presence in a lobby: who they are + which characters of
/// theirs should spawn for everyone.
struct LobbyPresence: Codable, Identifiable {
    let userId: String
    let displayName: String
    let characterIds: [String]
    var id: String { userId }
}

/// A live in-lobby game event (co-op focus ticks, PvP answer/damage/turn).
/// Deliberately flat + flexible so one broadcast event covers every mode.
struct LobbyEvent: Codable {
    let kind: String          // "focusStart" | "answer" | "damage" | "turn" | "ready" | "start" | "win"
    let from: String          // sender userId
    var number: Int?          // damage / hp / index
    var text: String?         // card id / ability id
    var flag: Bool?           // correct? / ready?
}

/// Wraps a Supabase Realtime channel for a lobby: tracks presence (the live
/// roster + everyone's characters) and relays game events. Co-op spawn, co-op
/// sessions, and PvP all read from this one object.
@MainActor
final class LobbyService: ObservableObject {
    static let shared = LobbyService()

    @Published private(set) var members: [LobbyPresence] = []
    @Published private(set) var lobby: LobbyRecord?
    @Published private(set) var connected = false
    /// Most recent game event received (PvP/coop sessions observe this).
    @Published var lastEvent: LobbyEvent?

    private var channel: RealtimeChannelV2?
    private var roster: [String: LobbyPresence] = [:]
    private var streamTasks: [Task<Void, Never>] = []
    private var me: LobbyPresence?

    var isHost: Bool {
        guard let lobby, let me else { return false }
        return lobby.host.uuidString == me.userId
    }

    var myUserID: String { me?.userId ?? "" }

    func connect(to lobby: LobbyRecord, me: LobbyPresence) async {
        await disconnect()
        self.lobby = lobby
        self.me = me
        roster = [:]
        members = []

        let ch = MitoBackend.shared.client.channel("lobby:\(lobby.code)")
        channel = ch

        let presenceTask = Task { [weak self] in
            for await change in ch.presenceChange() {
                await self?.applyPresence(change)
            }
        }
        let eventTask = Task { [weak self] in
            for await json in ch.broadcastStream(event: "game") {
                await self?.applyEvent(json)
            }
        }
        streamTasks = [presenceTask, eventTask]

        await ch.subscribe()
        try? await ch.track(me)
        connected = true
    }

    func disconnect() async {
        streamTasks.forEach { $0.cancel() }
        streamTasks = []
        if let ch = channel {
            await ch.untrack()
            await ch.unsubscribe()
        }
        channel = nil
        connected = false
        lobby = nil
        roster = [:]
        members = []
    }

    func send(_ event: LobbyEvent) async {
        try? await channel?.broadcast(event: "game", message: event)
    }

    private func applyPresence(_ action: any PresenceAction) {
        for (key, presence) in action.joins {
            if let p = try? presence.decodeState(as: LobbyPresence.self) {
                roster[key] = p
            }
        }
        for (key, _) in action.leaves {
            roster.removeValue(forKey: key)
        }
        members = Array(roster.values)
    }

    private func applyEvent(_ json: JSONObject) {
        // The broadcast callback yields the outer envelope {type,event,payload};
        // our LobbyEvent is the inner `payload`.
        guard let inner = json["payload"],
              let data = try? JSONEncoder().encode(inner),
              let event = try? JSONDecoder().decode(LobbyEvent.self, from: data) else { return }
        lastEvent = event
    }

    /// Build my presence from the signed-in user + active party.
    func makePresence() async -> LobbyPresence? {
        guard let id = MitoBackend.shared.currentUserID else { return nil }
        let name = await MitoBackend.shared.myDisplayName()
        return LobbyPresence(userId: id.uuidString, displayName: name,
                             characterIds: BattleRules.partyHeroes.map(\.id))
    }
}

// MARK: - Lobby UI

/// Create or join a lobby, see the live roster, and launch co-op / versus.
struct LobbyView: View {
    @ObservedObject var backend: MitoBackend
    @Binding var isPresented: Bool
    @ObservedObject private var service = LobbyService.shared

    @State private var joinCode = ""
    @State private var busy = false
    @State private var message = ""
    @State private var duel: DuelStart?

    var body: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    Text(service.lobby == nil ? "CO-OP & VERSUS" : "LOBBY \(service.lobby!.code)")
                        .pixelText(size: 15, color: Color(hex: "3A2A18"))
                    Spacer()
                    Button { Task { await close() } } label: {
                        Text("X").pixelText(size: 13, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                    }.buttonStyle(.plain)
                }

                if service.lobby == nil {
                    lobbyPicker
                } else {
                    lobbyRoom
                }

                if !message.isEmpty {
                    Text(message).font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324")).multilineTextAlignment(.center)
                }
            }
            .padding(18)
            .frame(width: 330)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
        }
        .onReceive(service.$lastEvent) { ev in
            // Guest side: host picked a deck → drop into the duel.
            guard let ev, ev.kind == "start", ev.from != service.myUserID,
                  let deckID = ev.text, let seed = ev.number, duel == nil else { return }
            duel = DuelStart(deckID: deckID, seed: UInt64(seed))
        }
        .fullScreenCover(item: $duel) { d in
            PvPDuelView(start: d, lobby: service.lobby, duel: $duel)
        }
    }

    private var lobbyPicker: some View {
        VStack(spacing: 12) {
            Text("Invite a friend to study together or duel a deck head-to-head.")
                .font(.custom(MitoFont.regular, size: 14))
                .foregroundStyle(Color(hex: "4A2F1C")).multilineTextAlignment(.center)

            bigButton("✦ CREATE CO-OP ROOM", Color(hex: "4A8A3C")) { Task { await create(mode: "coop") } }
            bigButton("⚔ CREATE VERSUS ROOM", Color(hex: "C84A3A")) { Task { await create(mode: "pvp") } }

            Text("OR JOIN A CODE").pixelText(size: 9, color: Color(hex: "6B4324")).padding(.top, 4)
            HStack(spacing: 8) {
                TextField("CODE", text: $joinCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .authInputStyle()
                Button { Task { await join() } } label: {
                    Text("JOIN").pixelText(size: 12, color: .white)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(Color(hex: "4A7BA8"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }.buttonStyle(.plain)
            }
        }
        .disabled(busy)
    }

    private var lobbyRoom: some View {
        VStack(spacing: 10) {
            Text("SHARE CODE").pixelText(size: 9, color: Color(hex: "6B4324"))
            Text(service.lobby?.code ?? "")
                .pixelText(size: 26, color: Color(hex: "3A2A18")).textSelection(.enabled)

            Text("IN THE ROOM (\(service.members.count))")
                .pixelText(size: 9, color: Color(hex: "6B4324")).padding(.top, 4)
            ForEach(service.members) { m in
                HStack {
                    Text(m.displayName).font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "3A2A18"))
                    Spacer()
                    Text("\(m.characterIds.count) heroes").pixelText(size: 8, color: Color(hex: "8A6B42"))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color(hex: "DCC79A"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }

            if service.lobby?.mode == "coop" {
                Text("Your friends' characters now wander your home meadow. Start a focus session together from the home screen!")
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "4A2F1C")).multilineTextAlignment(.center).padding(.top, 4)
            } else if service.isHost {
                Text("PICK A DECK TO DUEL").pixelText(size: 9, color: Color(hex: "6B4324")).padding(.top, 4)
                ForEach(ReviewSession.shared.deckSummaries) { deck in
                    Button { startDuel(deckID: deck.id) } label: {
                        HStack {
                            Text(deck.name).font(.custom(MitoFont.regular, size: 14))
                                .foregroundStyle(Color(hex: "3A2A18"))
                            Spacer()
                            Text("\(deck.cardCount) cards").pixelText(size: 8, color: Color(hex: "8A6B42"))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(hex: "C7D7B0"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.members.count < 2)
                }
                if service.members.count < 2 {
                    Text("Waiting for an opponent to join…")
                        .font(.custom(MitoFont.regular, size: 12)).foregroundStyle(Color(hex: "6B4324"))
                }
            } else {
                Text("Waiting for the host to pick a deck…")
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "4A2F1C")).multilineTextAlignment(.center).padding(.top, 4)
            }

            bigButton("LEAVE ROOM", Color(hex: "6B4324")) { Task { await leave() } }
        }
    }

    private func startDuel(deckID: String) {
        let seed = Int.random(in: 1...2_000_000_000)
        duel = DuelStart(deckID: deckID, seed: UInt64(seed))
        Task { await service.send(LobbyEvent(kind: "start", from: service.myUserID, number: seed, text: deckID)) }
    }

    private func bigButton(_ title: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).pixelText(size: 13, color: .white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(color).overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        }.buttonStyle(.plain)
    }

    private func create(mode: String) async {
        guard backend.isReady, !busy else { message = "Sign in first."; return }
        busy = true; defer { busy = false }
        do {
            let party = BattleRules.partyHeroes.map(\.id)
            let lobby = try await backend.createLobby(mode: mode, characterIDs: party)
            guard let me = await service.makePresence() else { return }
            await service.connect(to: lobby, me: me)
        } catch { message = "Couldn't create room." }
    }

    private func join() async {
        let code = joinCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard backend.isReady, code.count >= 4, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let party = BattleRules.partyHeroes.map(\.id)
            guard let _ = try await backend.joinLobby(code: code, characterIDs: party),
                  let lobby = try await backend.fetchLobby(code: code) else {
                message = "No open room with that code."; return
            }
            guard let me = await service.makePresence() else { return }
            await service.connect(to: lobby, me: me)
        } catch { message = "Couldn't join room." }
    }

    private func leave() async {
        if let id = service.lobby?.id {
            if service.isHost { try? await backend.closeLobby(id) }
            else { try? await backend.leaveLobby(id) }
        }
        await service.disconnect()
    }

    private func close() async {
        // Leaving the sheet keeps you connected (co-op spawn persists on home);
        // only fully leave via the LEAVE button.
        isPresented = false
    }
}

// MARK: - PvP duel

struct DuelStart: Identifiable, Equatable {
    let deckID: String
    let seed: UInt64
    var id: String { "\(deckID)-\(seed)" }
}

/// Multiple-choice options for a card outside the battle screen (PvP). Correct
/// answer + up to three distractors (cached or sibling-card answers), shuffled
/// deterministically per card.
func multipleChoiceOptions(for card: ReviewCard, in pool: [ReviewCard]) -> [String] {
    let correctKey = AnswerGrading.normalize(card.back)
    var distractors: [String] = (card.choices?.isEmpty == false) ? card.choices! : []
    if distractors.count < 3 {
        var rng = SeededGenerator(seed: card.id)
        let siblings = pool
            .filter { $0.id != card.id && AnswerGrading.normalize($0.back) != correctKey }
            .map(\.back)
            .shuffled(using: &rng)
        distractors += siblings
    }
    var seen: Set<String> = [correctKey]
    var picked: [String] = []
    for d in distractors {
        let k = AnswerGrading.normalize(d)
        guard !k.isEmpty, !seen.contains(k) else { continue }
        seen.insert(k); picked.append(d)
        if picked.count == 3 { break }
    }
    var rng = SeededGenerator(seed: card.id)
    return ([card.back] + picked).shuffled(using: &rng)
}

/// Head-to-head deck duel. Both players answer the SAME deck in the same seeded
/// order; a correct answer damages the opponent. Wrong answers recirculate
/// (Quizlet-Learn mastery) and deal no damage. First to drain the opponent's HP
/// wins. Ephemeral — never touches FSRS. Each client is authoritative over the
/// damage it deals and relays it over the lobby's realtime channel.
struct PvPDuelView: View {
    let start: DuelStart
    let lobby: LobbyRecord?
    @Binding var duel: DuelStart?
    @ObservedObject private var service = LobbyService.shared

    @State private var queue: [ReviewCard] = []
    @State private var myHP = 100
    @State private var oppHP = 100
    @State private var finished = false
    @State private var won = false
    @State private var resolving = false

    private let maxHP = 100
    private let hitDamage = 18

    private var opponentID: UUID? {
        service.members.first { $0.userId != service.myUserID }.flatMap { UUID(uuidString: $0.userId) }
    }
    private var opponentName: String {
        service.members.first { $0.userId != service.myUserID }?.displayName ?? "Opponent"
    }

    var body: some View {
        ZStack {
            Color(hex: "1A130A").ignoresSafeArea()
            VStack(spacing: 12) {
                hpBar(label: opponentName.uppercased(), hp: oppHP, color: Color(hex: "C84A3A"))
                Spacer(minLength: 8)

                if finished {
                    resultCard
                } else if let card = queue.first {
                    VStack(spacing: 10) {
                        Text("ANSWER TO ATTACK").pixelText(size: 10, color: Color(hex: "FFD24D"))
                        Text(card.front)
                            .font(.custom(MitoFont.regular, size: 18))
                            .foregroundStyle(Color(hex: "F4E6C0"))
                            .multilineTextAlignment(.center)
                            .padding().frame(maxWidth: .infinity)
                            .background(Color(hex: "2A1B0E"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        MultipleChoicePanel(
                            options: multipleChoiceOptions(for: card, in: queue),
                            correctAnswer: card.back,
                            onReveal: {},
                            onResolved: { rating in resolve(correct: rating != .again) }
                        )
                        .id(card.id)
                    }
                    .padding(.horizontal, 16)
                } else {
                    Text("Loading deck…").pixelText(size: 12, color: .white)
                }

                Spacer(minLength: 8)
                hpBar(label: "YOU", hp: myHP, color: Color(hex: "4A9B3F"))
                Button { Task { await quit() } } label: {
                    Text(finished ? "BACK TO LOBBY" : "FORFEIT")
                        .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color(hex: "6B4324"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .onAppear(perform: loadDeck)
        .onReceive(service.$lastEvent) { ev in handle(ev) }
    }

    private func hpBar(label: String, hp: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).pixelText(size: 10, color: Color(hex: "F4E6C0"))
                Spacer()
                Text("\(max(0, hp))/\(maxHP)").pixelText(size: 9, color: Color(hex: "F4E6C0"))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(hex: "2A1A0D"))
                    Rectangle().fill(color)
                        .frame(width: geo.size.width * CGFloat(max(0, hp)) / CGFloat(maxHP))
                }
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }
            .frame(height: 16)
        }
    }

    private var resultCard: some View {
        VStack(spacing: 12) {
            Text(won ? "VICTORY!" : "DEFEAT")
                .pixelText(size: 22, color: won ? Color(hex: "FFD24D") : Color(hex: "C84A3A"))
            Text(won ? "You out-studied \(opponentName)." : "\(opponentName) was faster this time.")
                .font(.custom(MitoFont.regular, size: 15))
                .foregroundStyle(Color(hex: "F4E6C0")).multilineTextAlignment(.center)
        }
        .padding(20)
        .background(Color(hex: "2A1B0E"))
        .overlay(Rectangle().stroke(Color(hex: won ? "FFD24D" : "C84A3A"), lineWidth: 4))
    }

    private func loadDeck() {
        guard queue.isEmpty else { return }
        let pool = ReviewSession.shared.allCards()
        var cards = pool.filter { $0.deckID == start.deckID }
        if cards.isEmpty { cards = pool }
        var rng = SeededGenerator(seed: start.seed == 0 ? 1 : start.seed)
        queue = cards.shuffled(using: &rng)
    }

    private func resolve(correct: Bool) {
        guard !finished, !queue.isEmpty else { return }
        if correct {
            oppHP = max(0, oppHP - hitDamage)
            AudioManager.shared.play(.gradeGood); Haptics.success()
            let dmg = hitDamage
            Task { await service.send(LobbyEvent(kind: "damage", from: service.myUserID, number: dmg)) }
            queue.removeFirst()
            if oppHP <= 0 {
                finished = true; won = true
                Task {
                    await service.send(LobbyEvent(kind: "win", from: service.myUserID))
                    await recordResult(win: true)
                }
            }
        } else {
            // Missed card recirculates to the back; no damage.
            let missed = queue.removeFirst()
            queue.append(missed)
            AudioManager.shared.play(.gradeAgain); Haptics.warning()
        }
        if queue.isEmpty { loadDeck() } // refill so the duel never stalls
    }

    private func handle(_ ev: LobbyEvent?) {
        guard let ev, ev.from != service.myUserID, !finished else { return }
        switch ev.kind {
        case "damage":
            myHP = max(0, myHP - (ev.number ?? 0))
            if myHP <= 0 { finished = true; won = false }
        case "win":
            finished = true; won = false
        default:
            break
        }
    }

    private func recordResult(win: Bool) async {
        guard let opp = opponentID else { return }
        try? await MitoBackend.shared.recordPvPResult(
            lobbyID: lobby?.id, deckID: UUID(uuidString: start.deckID), opponent: opp, didWin: win)
    }

    private func quit() async {
        if !finished, let opp = opponentID {
            try? await MitoBackend.shared.recordPvPResult(
                lobbyID: lobby?.id, deckID: UUID(uuidString: start.deckID), opponent: opp, didWin: false)
        }
        duel = nil
    }
}



















































