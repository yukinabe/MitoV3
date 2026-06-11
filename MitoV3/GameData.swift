import SwiftUI

struct Hero: Identifiable {
    let id: String
    let asset: String
    let name: String
    let role: String
    let level: Int
    let hp: Int
    let attack: Int
    let defense: Int
    var speed: Int = 100          // turn frequency (HSR-style action value)
    let color: Color
    let lore: String

    func applying(_ progress: CharacterProgress) -> Hero {
        Hero(
            id: id,
            asset: asset,
            name: name,
            role: role,
            level: progress.level,
            hp: progress.hp,
            attack: progress.attack,
            defense: progress.defense,
            speed: speed,
            color: color,
            lore: lore
        )
    }
}

struct CharacterProgress {
    var level: Int
    var hp: Int
    var attack: Int
    var defense: Int

    init(level: Int, hp: Int, attack: Int, defense: Int) {
        self.level = level
        self.hp = hp
        self.attack = attack
        self.defense = defense
    }

    init(hero: Hero) {
        self.init(level: hero.level, hp: hero.hp, attack: hero.attack, defense: hero.defense)
    }

    init(record: CharacterProgressRecord) {
        self.init(level: record.level, hp: record.hp, attack: record.attack, defense: record.defense)
    }

    mutating func levelUp() {
        level += 1
        hp += 5
        attack += 3
        defense += 2
    }
}

enum AbilityKind: String, CaseIterable {
    case basic = "Basic"
    case skill = "Skill"
    case ultimate = "Ultimate"
}

/// The distinct buff/effect types abilities can apply.
enum BuffKind: String, Equatable {
    case attack      // +% team damage
    case defense     // −% recoil taken (campaign)
    case speed       // +flat speed → acts sooner / more often
    case shield      // flat damage-absorb pool (campaign)
    case heal        // instant HP restore to lowest ally (campaign)
    case ultEnergy   // instant ultimate-energy to all allies
    case mark        // enemy takes +% damage (debuff)

    var label: String {
        switch self {
        case .attack: "ATK"; case .defense: "DEF"; case .speed: "SPD"
        case .shield: "SHIELD"; case .heal: "HEAL"; case .ultEnergy: "ENERGY"; case .mark: "MARK"
        }
    }
    var icon: String {
        switch self {
        case .attack: "⚔"; case .defense: "🛡"; case .speed: "✦"
        case .shield: "❖"; case .heal: "✚"; case .ultEnergy: "⚡"; case .mark: "◎"
        }
    }
    /// Applied immediately rather than tracked as a timed team buff.
    var isInstant: Bool { self == .heal || self == .ultEnergy }
}

struct BuffGrant: Equatable {
    let kind: BuffKind
    let magnitude: Double   // % (0.2 = +20%) for stat buffs; flat HP/energy otherwise
    let turns: Int          // duration for timed buffs (0 for instant)
}

struct BattleAbility: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: AbilityKind
    let damage: Int
    let detail: String
    let theme: String
    let animationKey: String
    let color: Color
    let energyCost: Int?
    let ultimateChargeRequired: Int?

    /// Support abilities that buff the whole party (the aura/team-hop visuals).
    static let teamBuffKeys: Set<String> = [
        "mito-cristae-surge", "mito-powerhouse-burst",
        "astro-synapse-buffer", "astro-glial-network",
        "dendri-immune-rally", "neuro-myelin-guard",
        "bcell-affinity-shield", "bcell-memory-response"
    ]

    /// Buffs/effects this ability applies — gives each hero a distinct identity.
    var grants: [BuffGrant] {
        switch animationKey {
        // Mito — energy & sustain
        case "mito-cristae-surge":
            // No damage, so it shields + heals more to be worth a turn.
            return [BuffGrant(kind: .shield, magnitude: 16, turns: 3),
                    BuffGrant(kind: .heal, magnitude: 10, turns: 0)]
        case "mito-powerhouse-burst":
            return [BuffGrant(kind: .ultEnergy, magnitude: 1, turns: 0),
                    BuffGrant(kind: .attack, magnitude: 0.15, turns: 3)]
        // Astro — speed
        case "astro-synapse-buffer":
            return [BuffGrant(kind: .speed, magnitude: 20, turns: 3)]
        case "astro-glial-network":
            return [BuffGrant(kind: .speed, magnitude: 30, turns: 3),
                    BuffGrant(kind: .attack, magnitude: 0.10, turns: 3)]
        // Dendri — mark & attack
        case "dendri-present-antigen":
            // No damage — a strong, longer Mark instead.
            return [BuffGrant(kind: .mark, magnitude: 0.30, turns: 4)]
        case "dendri-immune-rally":
            return [BuffGrant(kind: .attack, magnitude: 0.20, turns: 3),
                    BuffGrant(kind: .mark, magnitude: 0.15, turns: 3)]
        // Neuro — defense (tank)
        case "neuro-myelin-guard":
            return [BuffGrant(kind: .defense, magnitude: 0.40, turns: 3)]
        case "neuro-synaptic-overload":
            return [BuffGrant(kind: .defense, magnitude: 0.30, turns: 3)]
        // B Cell — shields
        case "bcell-affinity-shield":
            return [BuffGrant(kind: .shield, magnitude: 16, turns: 3)]
        case "bcell-memory-response":
            return [BuffGrant(kind: .attack, magnitude: 0.18, turns: 3),
                    BuffGrant(kind: .shield, magnitude: 12, turns: 3)]
        // Cloro & basics — pure damage, no buffs.
        default:
            return []
        }
    }

    /// Whether casting this applies any team buff (drives the aura/hop visuals).
    var isTeamBuff: Bool { !grants.isEmpty || Self.teamBuffKeys.contains(animationKey) }

    /// Pure-support abilities (damage 0) don't strike the enemy at all.
    var dealsDamage: Bool { damage > 0 }

    /// Skills go on cooldown for this many of the hero's own turns after use.
    /// Basics are free; ultimates are gated by energy instead.
    var cooldownTurns: Int { kind == .skill ? 3 : 0 }

    /// One-line in-world reason the buff matters (shown in the HUD/tooltip).
    var buffReason: String {
        switch animationKey {
        case "mito-cristae-surge", "mito-powerhouse-burst":
            return "Floods allies with ATP — +dmg on the next hits."
        case "neuro-myelin-guard":
            return "Myelin shielding — softens incoming recoil."
        case "bcell-affinity-shield", "bcell-memory-response":
            return "Antibody priming — the team strikes harder."
        case "astro-synapse-buffer", "astro-glial-network":
            return "Glial sync — sharpens the whole party's focus."
        case "dendri-immune-rally":
            return "Immune rally — momentum boosts team damage."
        default:
            return "Energizes the team."
        }
    }
}

/// A single timed stat buff (magnitude + remaining turns).
struct TimedBuff: Equatable {
    var magnitude: Double = 0
    var turns: Int = 0
    var active: Bool { turns > 0 && magnitude != 0 }

    mutating func apply(_ m: Double, _ t: Int) {
        magnitude = Swift.max(magnitude, m)   // refresh, don't stack unbounded
        turns = Swift.max(turns, t)
    }
    mutating func tick() {
        guard turns > 0 else { return }
        turns -= 1
        if turns == 0 { magnitude = 0 }
    }
}

/// All active combat buffs/debuffs on the team and enemy.
struct CombatBuffs: Equatable {
    var attack = TimedBuff()    // +% team damage
    var defense = TimedBuff()   // −% recoil
    var speed = TimedBuff()     // +flat speed
    var mark = TimedBuff()      // enemy +% damage taken
    var shield = 0              // flat absorb pool

    var damageMultiplier: Double { 1.0 + attack.magnitude }
    var markMultiplier: Double { 1.0 + mark.magnitude }
    var recoilMultiplier: Double { Swift.max(0, 1.0 - defense.magnitude) }
    var speedBonus: Int { speed.active ? Int(speed.magnitude) : 0 }

    mutating func tickAll() {
        attack.tick(); defense.tick(); speed.tick(); mark.tick()
    }

    /// Timed buffs to show as HUD chips (instant heal/energy aren't tracked).
    var chips: [(kind: BuffKind, text: String)] {
        var out: [(BuffKind, String)] = []
        if attack.active  { out.append((.attack,  "+\(Int(attack.magnitude * 100))%")) }
        if defense.active { out.append((.defense, "-\(Int(defense.magnitude * 100))%")) }
        if speed.active   { out.append((.speed,   "+\(Int(speed.magnitude))")) }
        if mark.active    { out.append((.mark,    "+\(Int(mark.magnitude * 100))%")) }
        if shield > 0     { out.append((.shield,  "\(shield)")) }
        return out
    }
}

/// HSR-style action-value turn order: every hero has an action value that ticks
/// down; the one that reaches 0 acts next. Higher Speed = lower value between
/// turns = acts more often. `reset` seeds it; `advance` resets the actor.
struct TurnEngine {
    static let base: Double = 10000
    private(set) var av: [String: Double] = [:]

    mutating func reset(_ heroes: [Hero]) {
        av = Dictionary(uniqueKeysWithValues: heroes.map {
            ($0.id, TurnEngine.base / Double(max($0.speed, 1)))
        })
    }

    /// Hero id whose turn it is now (lowest action value among the living).
    func current(alive: Set<String>) -> String? {
        av.filter { alive.contains($0.key) }.min { $0.value < $1.value }?.key
    }

    /// The actor just took their turn: advance the clock and reset their value.
    mutating func advance(actor: String, speed: Int, alive: Set<String>) {
        let elapsed = av[actor] ?? 0
        for k in av.keys where alive.contains(k) { av[k]! -= elapsed }
        av[actor] = TurnEngine.base / Double(max(speed, 1))
    }

    /// Advance everyone's action gauge a little (HSR "advance forward") so a
    /// speed buff has an immediate "act sooner" feel.
    mutating func advanceGauge(_ fraction: Double, alive: Set<String>) {
        for k in av.keys where alive.contains(k) { av[k]! *= (1 - fraction) }
    }

    /// Simulate the next `n` turn-takers (for the on-screen timeline).
    func upcoming(_ n: Int, heroes: [Hero], alive: Set<String>) -> [String] {
        let speedById = Dictionary(uniqueKeysWithValues: heroes.map { ($0.id, $0.speed) })
        var sim = av.filter { alive.contains($0.key) }
        var out: [String] = []
        for _ in 0..<Swift.max(n, 0) {
            guard let pick = sim.min(by: { $0.value < $1.value }) else { break }
            out.append(pick.key)
            for k in sim.keys { sim[k]! -= pick.value }
            sim[pick.key] = TurnEngine.base / Double(max(speedById[pick.key] ?? 100, 1))
        }
        return out
    }
}

enum BattleAbilityBook {
    static func abilities(for hero: Hero) -> [BattleAbility] {
        switch hero.id {
        case "mito":
            return [
                BattleAbility(id: "mito-atp-tap", name: "ATP Tap", kind: .basic, damage: 18, detail: "A free ATP spark keeps pressure on the enemy while Mito saves energy for support turns.", theme: "ATP / energy", animationKey: "spark", color: Color(hex: "F48FB1"), energyCost: nil, ultimateChargeRequired: nil),
                BattleAbility(id: "mito-cristae-surge", name: "Cristae Surge", kind: .skill, damage: 0, detail: "Pure support — no attack. Shields the whole team and restores a little HP.", theme: "ATP support / shield", animationKey: "mito-cristae-surge", color: Color(hex: "FFD24D"), energyCost: 2, ultimateChargeRequired: nil),
                BattleAbility(id: "mito-powerhouse-burst", name: "Powerhouse Burst", kind: .ultimate, damage: 34, detail: "Mito floods the field with ATP, stabilizing the whole team and turning stored focus into one safe burst.", theme: "ATP support / team sustain", animationKey: "mito-powerhouse-burst", color: Color(hex: "E77878"), energyCost: nil, ultimateChargeRequired: 4)
            ]
        case "cloro":
            return [
                BattleAbility(id: "cloro-photon-shot", name: "Photon Shot", kind: .basic, damage: 22, detail: "A clean flash of light hits the target with simple DPS pressure.", theme: "Light / photosynthesis", animationKey: "beam", color: Color(hex: "A8D95B"), energyCost: nil, ultimateChargeRequired: nil),
                BattleAbility(id: "cloro-sugar-rush", name: "Sugar Rush", kind: .skill, damage: 34, detail: "Stored photosynthetic energy pops into a stronger burst.", theme: "Light / photosynthesis", animationKey: "cloro-sugar-rush", color: Color(hex: "7BB55C"), energyCost: 2, ultimateChargeRequired: nil),
                BattleAbility(id: "cloro-photosynthesis-bloom", name: "Photosynthesis Bloom", kind: .ultimate, damage: 52, detail: "A bright bloom turns captured light into the party's biggest DPS hit.", theme: "Light / photosynthesis", animationKey: "cloro-photosynthesis-bloom", color: Color(hex: "CFEF74"), energyCost: nil, ultimateChargeRequired: 4)
            ]
        case "astro":
            return [
                BattleAbility(id: "astro-calcium-ping", name: "Calcium Ping", kind: .basic, damage: 16, detail: "A small support signal pings the target without slowing review down.", theme: "Neural support / network", animationKey: "pulse", color: Color(hex: "A98FD0"), energyCost: nil, ultimateChargeRequired: nil),
                BattleAbility(id: "astro-synapse-buffer", name: "Synapse Buffer", kind: .skill, damage: 14, detail: "A glial pulse: light damage plus a team Speed boost.", theme: "Neural support / network", animationKey: "astro-synapse-buffer", color: Color(hex: "C7A6F2"), energyCost: 2, ultimateChargeRequired: nil),
                BattleAbility(id: "astro-glial-network", name: "Glial Network", kind: .ultimate, damage: 40, detail: "A star-shaped network lights up, supporting the team while striking back.", theme: "Neural support / network", animationKey: "astro-glial-network", color: Color(hex: "8B6BD9"), energyCost: nil, ultimateChargeRequired: 4)
            ]
        case "dendri":
            return [
                BattleAbility(id: "dendri-scout-prick", name: "Scout Prick", kind: .basic, damage: 16, detail: "A quick immune scout jab marks the enemy's position visually.", theme: "Immune scouting / antigen", animationKey: "jab", color: Color(hex: "E8C64A"), energyCost: nil, ultimateChargeRequired: nil),
                BattleAbility(id: "dendri-present-antigen", name: "Present Antigen", kind: .skill, damage: 0, detail: "No attack — marks the enemy so the whole team hits it harder.", theme: "Immune scouting / antigen", animationKey: "dendri-present-antigen", color: Color(hex: "F2D85B"), energyCost: 2, ultimateChargeRequired: nil),
                BattleAbility(id: "dendri-immune-rally", name: "Immune Rally", kind: .ultimate, damage: 42, detail: "A focused immune call turns one spotted target into team momentum.", theme: "Immune scouting / antigen", animationKey: "dendri-immune-rally", color: Color(hex: "D7A72F"), energyCost: nil, ultimateChargeRequired: 4)
            ]
        case "neuro":
            return [
                BattleAbility(id: "neuro-axon-zap", name: "Axon Zap", kind: .basic, damage: 18, detail: "A free electrical signal snaps forward from Neuro's axon.", theme: "Electric / signal", animationKey: "zap", color: Color(hex: "5FA3D4"), energyCost: nil, ultimateChargeRequired: nil),
                BattleAbility(id: "neuro-myelin-guard", name: "Myelin Guard", kind: .skill, damage: 20, detail: "Pushes damage back while raising the team's defense (less recoil).", theme: "Electric / signal", animationKey: "neuro-myelin-guard", color: Color(hex: "7EB9F0"), energyCost: 2, ultimateChargeRequired: nil),
                BattleAbility(id: "neuro-synaptic-overload", name: "Synaptic Overload", kind: .ultimate, damage: 44, detail: "Neuro releases a heavy chain of signals for a tank-style finisher.", theme: "Electric / signal", animationKey: "neuro-synaptic-overload", color: Color(hex: "4D7FD4"), energyCost: nil, ultimateChargeRequired: 4)
            ]
        case "bcell":
            return [
                BattleAbility(id: "bcell-antibody-tap", name: "Antibody Tap", kind: .basic, damage: 15, detail: "A tiny antibody projectile tags the enemy with steady support damage.", theme: "Immune / antibody", animationKey: "projectile", color: Color(hex: "F4C6B8"), energyCost: nil, ultimateChargeRequired: nil),
                BattleAbility(id: "bcell-affinity-shield", name: "Affinity Shield", kind: .skill, damage: 14, detail: "A light antibody jab that also shields the team.", theme: "Immune / antibody", animationKey: "bcell-affinity-shield", color: Color(hex: "F0AFA4"), energyCost: 2, ultimateChargeRequired: nil),
                BattleAbility(id: "bcell-memory-response", name: "Memory Response", kind: .ultimate, damage: 38, detail: "A remembered immune response surges back as a reliable support ultimate.", theme: "Immune / antibody", animationKey: "bcell-memory-response", color: Color(hex: "E8877C"), energyCost: nil, ultimateChargeRequired: 4)
            ]
        default:
            return [
                BattleAbility(id: "\(hero.id)-tap", name: "Study Tap", kind: .basic, damage: 18, detail: "\(hero.name) keeps the review moving.", theme: "Study", animationKey: "tap", color: hero.color, energyCost: nil, ultimateChargeRequired: nil),
                BattleAbility(id: "\(hero.id)-burst", name: "Focus Burst", kind: .skill, damage: 28, detail: "\(hero.name) turns recall into damage.", theme: "Study", animationKey: "burst", color: hero.color, energyCost: 2, ultimateChargeRequired: nil),
                BattleAbility(id: "\(hero.id)-combo", name: "Recall Combo", kind: .ultimate, damage: 40, detail: "\(hero.name) lands a clean combo.", theme: "Study", animationKey: "combo", color: hero.color, energyCost: nil, ultimateChargeRequired: 4)
            ]
        }
    }
}

extension Hero {
    var abilities: [BattleAbility] {
        BattleAbilityBook.abilities(for: self)
    }
}

struct Deck: Identifiable {
    let id: String
    let name: String
    let cards: Int
    let tags: [String]
    let color: Color
}

struct Flashcard: Identifiable, Equatable {
    let id: String
    var front: String
    var back: String
    var tags: [String]
}

struct Stage: Identifiable {
    let id: Int
    let name: String
    let status: StageStatus
    let x: CGFloat
    let y: CGFloat
    let difficulty: String
}

enum StageStatus {
    case cleared
    case active
    case locked

    var asset: String {
        switch self {
        case .cleared: "node-cleared"
        case .active: "node-active"
        case .locked: "node-locked"
        }
    }
}

enum DataSet {
    static let heroes: [Hero] = [
        Hero(id: "mito", asset: "hero-mito-hop", name: "Mito", role: "Support", level: 12, hp: 48, attack: 18, defense: 14, speed: 96, color: Color(hex: "E77878"), lore: "A bean-shaped mitochondria helper with bright cristae. Turns focus into ATP and keeps the party steady when long study sessions get rough."),
        Hero(id: "cloro", asset: "hero-chloroplast-hop", name: "Chloro", role: "DPS", level: 11, hp: 42, attack: 22, defense: 11, speed: 112, color: Color(hex: "7BB55C"), lore: "A chloroplast DPS who captures light and stores it as clean burst damage. Quick, bright, and built for photosynthesis-themed pressure."),
        Hero(id: "astro", asset: "hero-astrocyte-hop", name: "Astro", role: "Support", level: 10, hp: 36, attack: 24, defense: 9, speed: 103, color: Color(hex: "A98FD0"), lore: "A star-shaped astrocyte support who stabilizes the neural field. Astro's attacks feel like glial network signals instead of raw force."),
        Hero(id: "dendri", asset: "hero-dendritic-cell-hop", name: "Dendri", role: "Support", level: 9, hp: 38, attack: 16, defense: 12, speed: 108, color: Color(hex: "E8C64A"), lore: "A branching dendritic-cell scout who keeps the team alert and turns small wins into streaks."),
        Hero(id: "neuro", asset: "hero-neuron-hop", name: "Neuro", role: "Tank", level: 13, hp: 56, attack: 14, defense: 22, speed: 88, color: Color(hex: "5FA3D4"), lore: "A sturdy neuron buffer with branching signals. Soaks pressure while fragile allies line up the next answer."),
        Hero(id: "bcell", asset: "hero-b-cell-hop", name: "B Cell", role: "Support", level: 8, hp: 34, attack: 17, defense: 10, speed: 94, color: Color(hex: "F4C6B8"), lore: "A careful immune support who turns repeated exposure into stronger responses. Antibody-themed moves make B Cell feel defensive without extra combat math.")
    ]

    static let decks: [Deck] = [
        Deck(id: "bio", name: "Biology 220", cards: 6, tags: ["cell", "dna", "mitosis"], color: Color(hex: "6DB04C")),
        Deck(id: "phys", name: "Physics formulas", cards: 4, tags: ["kinematics", "energy", "waves"], color: Color(hex: "5FA3D4")),
        Deck(id: "jp", name: "Japanese vocab", cards: 3, tags: ["n5", "verbs", "nouns"], color: Color(hex: "E7A0B8")),
        Deck(id: "orgo", name: "Organic mechanisms", cards: 2, tags: ["sn1", "sn2", "e1"], color: Color(hex: "D4873A"))
    ]

    static let stages: [Stage] = [
        Stage(id: 1, name: "Petri Plain", status: .cleared, x: 0.50, y: 0.84, difficulty: "EASY"),
        Stage(id: 2, name: "Membrane Marsh", status: .cleared, x: 0.40, y: 0.775, difficulty: "EASY"),
        Stage(id: 3, name: "Nucleus Hollow", status: .cleared, x: 0.55, y: 0.71, difficulty: "NORMAL"),
        Stage(id: 4, name: "Mitochondria Cave", status: .active, x: 0.45, y: 0.645, difficulty: "NORMAL"),
        Stage(id: 5, name: "Ribosome Ridge", status: .locked, x: 0.58, y: 0.58, difficulty: "NORMAL"),
        Stage(id: 6, name: "Golgi Gorge", status: .locked, x: 0.42, y: 0.515, difficulty: "HARD"),
        Stage(id: 7, name: "Lysosome Lair", status: .locked, x: 0.56, y: 0.45, difficulty: "HARD"),
        Stage(id: 8, name: "Vacuole Vale", status: .locked, x: 0.44, y: 0.385, difficulty: "BOSS"),
        Stage(id: 9, name: "Cytoskel Span", status: .locked, x: 0.57, y: 0.32, difficulty: "HARD"),
        Stage(id: 10, name: "Plastid Pass", status: .locked, x: 0.43, y: 0.255, difficulty: "HARD"),
        Stage(id: 11, name: "Vesicle Vault", status: .locked, x: 0.54, y: 0.19, difficulty: "HARD"),
        Stage(id: 12, name: "Spike Citadel", status: .locked, x: 0.47, y: 0.125, difficulty: "BOSS")
    ]
}

extension Stage {
    /// HP / damage multiplier applied on top of stage-index scaling.
    var tierMultiplier: Double {
        switch difficulty {
        case "EASY": return 1.0
        case "NORMAL": return 1.25
        case "HARD": return 1.55
        case "BOSS": return 1.9
        default: return 1.0
        }
    }
}

/// Centralized difficulty scaling so endless waves and campaign stages stay
/// challenging as the team levels up — no one-shotting, no brick walls.
enum BattleScaling {
    /// Player hits scale gently with team level so progression matters.
    static func heroDamageMultiplier(teamLevel: Int) -> Double {
        max(0.7, 1 + 0.05 * Double(teamLevel - 10))
    }

    /// Endless enemies grow each wave (and with team level), so later waves
    /// take more cards to clear instead of dying in one hit.
    static func endlessEnemyHP(teamLevel: Int, wave: Int) -> Int {
        Int((110 + 22 * Double(wave)) * (1 + 0.08 * Double(teamLevel - 10)))
    }

    /// Endless loot scales with the wave reached.
    static func endlessReward(wave: Int) -> (gold: Int, biomass: Int) {
        (18 + wave * 5, 1 + wave / 4)
    }

    /// Campaign enemy HP scales with stage index and tier.
    static func campaignEnemyHP(stageIndex: Int, tierMultiplier: Double, teamLevel: Int) -> Int {
        Int((80 + 14 * Double(stageIndex)) * tierMultiplier * (1 + 0.06 * Double(teamLevel - 10)))
    }
}

/// Single source of truth for team size + composition, shared by the Team
/// screen and both battle modes. Three characters: Support / DPS / Tank.
enum BattleRules {
    static let partySize = 3
    static let defaultParty = ["mito", "cloro", "neuro"]
    /// UserDefaults key for the player's persisted active party (see PartyStore).
    static let partyDefaultsKey = "party.active"

    /// The player's active party IDs — persisted so the Team screen, study
    /// meadow, and both battle modes always agree. A `-uitestTeam=` launch arg
    /// still overrides it for screenshot/UI-test runs.
    static var activePartyIDs: [String] {
        let launchArgs = ProcessInfo.processInfo.arguments
        if let arg = launchArgs.first(where: { $0.hasPrefix("-uitestTeam=") }) {
            let ids = String(arg.dropFirst("-uitestTeam=".count))
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !ids.isEmpty { return Array(ids.prefix(partySize)) }
        }
        let saved = UserDefaults.standard.stringArray(forKey: partyDefaultsKey) ?? []
        let ids = saved.isEmpty ? defaultParty : saved
        return Array(ids.prefix(partySize))
    }

    /// The active party as Hero records (base + captured creatures), in order.
    static var partyHeroes: [Hero] {
        let pool = DataSet.heroes + DataSet.capturables
        return activePartyIDs.compactMap { id in pool.first { $0.id == id } }
    }
}

/// Observable wrapper over the persisted active party so SwiftUI screens (Team,
/// home meadow) refresh the instant the roster changes. Battle reads the same
/// values straight from `BattleRules` at launch, so all three stay in sync.
@MainActor
final class PartyStore: ObservableObject {
    static let shared = PartyStore()

    @Published private(set) var partyIDs: [String] = BattleRules.activePartyIDs

    private init() {}

    /// Replace the active party (capped at partySize) and persist it.
    func setParty(_ ids: [String]) {
        let trimmed = Array(ids.prefix(BattleRules.partySize))
        UserDefaults.standard.set(trimmed, forKey: BattleRules.partyDefaultsKey)
        partyIDs = trimmed
    }
}

// MARK: - Capturable wild creatures + ownership

extension DataSet {
    /// Wild creatures that show up as enemies in campaign/endless and can be
    /// captured on defeat. They start UNOWNED (the base heroes are always owned),
    /// so they're purely additive collectibles. They use the default ability set
    /// (BattleAbilityBook handles unknown ids) and existing mob art.
    static let capturables: [Hero] = [
        Hero(id: "wild-mutagem", asset: "mob_1", name: "Mutagem", role: "DPS", level: 10, hp: 40, attack: 21, defense: 10, speed: 105, color: Color(hex: "A98FD0"), lore: "A mutated gem-spore that drifts through endless review. Capturing one binds its restless energy to your team."),
        Hero(id: "wild-spikevyrus", asset: "mob_1", name: "Spikevyrus", role: "Tank", level: 12, hp: 54, attack: 15, defense: 20, speed: 90, color: Color(hex: "5FA3D4"), lore: "A spike-shelled virus boss from the campaign depths. Stubborn, sturdy, and surprisingly loyal once captured."),
        Hero(id: "wild-cytocrawler", asset: "mob_0", name: "Cytocrawler", role: "DPS", level: 9, hp: 36, attack: 23, defense: 8, speed: 118, color: Color(hex: "E8C64A"), lore: "A fast cytoplasmic crawler that skitters between waves. Rare, twitchy, and a brutal attacker.")
    ]

    static func capturable(id: String) -> Hero? { capturables.first { $0.id == id } }
}

/// Persistent set of captured-creature ids. Base heroes are always owned; this
/// only tracks the extra `DataSet.capturables` the player has caught.
@MainActor
final class CaptureStore: ObservableObject {
    static let shared = CaptureStore()
    private let key = "captured.creatures"

    @Published private(set) var owned: Set<String>

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        owned = Set(saved)
    }

    func isOwned(_ id: String) -> Bool { owned.contains(id) }

    /// Capture a creature. Returns false if it was already owned.
    @discardableResult
    func capture(_ id: String) -> Bool {
        guard !owned.contains(id) else { return false }
        owned.insert(id)
        UserDefaults.standard.set(Array(owned), forKey: key)
        return true
    }

    /// Captured creatures as usable Hero records, for the collection/team screen.
    var capturedHeroes: [Hero] {
        DataSet.capturables.filter { owned.contains($0.id) }
    }
}
