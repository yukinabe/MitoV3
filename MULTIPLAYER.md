# Mito — Multiplayer (Friends · Lobbies · Co-op · PvP)

Status as of this build:

| Piece | State |
|---|---|
| Premium gate (Mito+) | ✅ in app (`FriendsView`, `@AppStorage("premium.social")`; dev-unlock until RevenueCat) |
| Friend system (code, add, requests, list) | ✅ app UI + backend methods + SQL (`0008_friends.sql`) — **needs migration applied** |
| Friends button on home screen | ✅ |
| Lobbies / co-op / PvP schema | ✅ SQL written (`0009_lobbies.sql`) — **needs migration applied** |
| Lobby join (one-shot RPC) | ✅ `join_lobby()` in SQL |
| Lobby create/join + live roster (Realtime presence) | ✅ built (`LobbyService`, `LobbyView`) |
| Co-op: friends' characters spawn in your home meadow | ✅ built (`StudyWanderer.forLobbyGuests`) |
| PvP duel (same deck, MC, correctness→damage, mastery queue, no FSRS) | ✅ built (`PvPDuelView`) |
| **Live two-device test of presence + duel sync** | ⏳ **still needed** — couldn't verify realtime on one simulator |

**Now built and compiling — needs the migrations deployed + a real two-device
test pass.** The realtime sync (presence roster, PvP damage broadcasts, win
detection) is correct-by-construction but unverified live; tune timing/feel with
two devices. Remaining polish ideas + the co-op-focus shared-timer extension are
below.

---

## Why this split
Everything that can be built and compile-verified solo is in the app now. The
realtime layer (presence + synced battle moves) needs two live clients to test,
so it's specced here rather than shipped unverified.

## Transport
Use **Supabase Realtime** channels keyed by lobby code (`lobby:CODE`):
- **Presence** → who's in the lobby + each member's active party hero ids.
- **Broadcast** → live events (focus ticks, answer results, damage, turn handoff).
Durable bits (membership, PvP results) live in `lobbies` / `lobby_members` /
`pvp_matches` (migration 0009). Live bits never touch the DB.

## Lobbies
- Host taps **Create Lobby** → insert `lobbies` row with a random 5-char `code`,
  `mode` = coop|pvp → join own `lobby_members` with their party `character_ids`.
- Friend taps **Join** (from the Friends screen) → `rpc join_lobby(code, myParty)`.
- Both subscribe to `lobby:CODE` presence; the roster + everyone's characters sync.

## Co-op (the "study together" fantasy)
**Spawn:** every member's party heroes wander everyone's home meadow
(`StudyWanderer.forActiveTeam()` already renders a party — extend it to take a
union of all lobby members' `character_ids` from presence). Seeing your friends'
characters milling around your home is the ambient hook.

**Co-op focus session:** host starts a shared timer; all members study at once.
- Shared pooled ATP bar; a **co-op bonus** (e.g. ×1.25 ATP while ≥2 are actively
  in-session) rewards studying together.
- Presence shows who's still focused vs bailed → social accountability (the real
  point — like a study room, à la Finch/Forest but with friends).

**Co-op endless:** one shared enemy with a combined HP pool. Each player answers
their *own* due cards; correct answers from either player damage the shared
enemy; rewards split. A downed player (campaign-style HP) can be revived when the
partner clears a card. Merge both teams into one HSR turn order.

## PvP (deck duel — the headline premium feature)
- Host picks a **deck**; both players duel on the **same cards in the same order**
  (seed the shuffle by `match_id` so both clients agree). **Only** multiple-choice
  or type-in modes (no self-grade — can't trust it in PvP).
- **No FSRS writes.** PvP uses an ephemeral, internal **mastery queue** (Quizlet
  Learn style): every card in the deck must be answered correctly; wrong answers
  recirculate to the back until the whole deck is cleared. (Reuse the answer-mode
  grading: MC = correctness+speed; type-in = AI/local grader, correctness only.)
- **Battle loop = same engine, gated on correctness:** it's the existing turn
  battle, except **a player may only use an ability on a turn where they answered
  correctly.** Wrong answer → that turn they can do **basic attack only**
  (recommended over "lose the turn entirely" — keeps both players engaged and
  avoids dead air; tune later). Correct + fast → bigger hit / ult charge.
- First to drain the opponent's HP wins → write a `pvp_matches` row (bragging
  rights only). HP, damage, and the mastery queue are all client-side + broadcast.

**Anti-cheat (later):** route PvP answer-validation through the `mito-ai` edge
function (it already looks cards up server-side) so a tampered client can't claim
correct answers. Not needed for friends-only v1.

## Build order when we pick this up (with two devices)
1. Apply migrations `0008` + `0009`; redeploy nothing else needed.
2. `MitoBackend`: `createLobby`, `joinLobby` (rpc), `leaveLobby`, presence
   subscribe/track helpers over `RealtimeChannelV2`.
3. `LobbyView` (create/join + roster + ready) reached from `FriendsView`.
4. Co-op presence spawn in `HomeScreen` (union of member parties).
5. Co-op focus (shared timer + pooled ATP) → then co-op endless.
6. PvP: mastery queue + correctness-gated battle + broadcast sync + result row.
7. Replace the Mito+ dev-unlock with a RevenueCat purchase.
