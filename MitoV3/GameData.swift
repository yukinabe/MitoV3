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

struct BattleAbility: Identifiable, Equatable {
    let id: String
    let name: String
    let damage: Int
    let detail: String
    let color: Color
}

enum BattleAbilityBook {
    static func abilities(for hero: Hero) -> [BattleAbility] {
        switch hero.id {
        case "mito":
            return [
                BattleAbility(id: "mito-atp-spark", name: "ATP Spark", damage: 24, detail: "Mito zaps the target with stored focus energy.", color: Color(hex: "F48FB1")),
                BattleAbility(id: "mito-cristae-burst", name: "Cristae Burst", damage: 34, detail: "A charged burst erupts from Mito's folds.", color: Color(hex: "FFD24D")),
                BattleAbility(id: "mito-powerhouse", name: "Powerhouse", damage: 46, detail: "Mito overclocks for a heavy strike.", color: Color(hex: "E77878"))
            ]
        case "cloro":
            return [
                BattleAbility(id: "cloro-sunbeam", name: "Sunbeam", damage: 22, detail: "Chloro fires a clean beam of light.", color: Color(hex: "A8D95B")),
                BattleAbility(id: "cloro-growth-pop", name: "Growth Pop", damage: 31, detail: "Stored light pops into rapid damage.", color: Color(hex: "7BB55C")),
                BattleAbility(id: "cloro-photon-bloom", name: "Photon Bloom", damage: 42, detail: "A bright bloom hits the whole field.", color: Color(hex: "CFEF74"))
            ]
        case "astro":
            return [
                BattleAbility(id: "astro-signal-tap", name: "Signal Tap", damage: 23, detail: "Astro taps a fast support signal.", color: Color(hex: "A98FD0")),
                BattleAbility(id: "astro-memory-web", name: "Memory Web", damage: 33, detail: "A web of recall snaps onto the enemy.", color: Color(hex: "C7A6F2")),
                BattleAbility(id: "astro-neural-assist", name: "Neural Assist", damage: 40, detail: "Astro boosts the team's next thought.", color: Color(hex: "8B6BD9"))
            ]
        case "dendri":
            return [
                BattleAbility(id: "dendri-scout-ping", name: "Scout Ping", damage: 20, detail: "Dendri marks a weak point.", color: Color(hex: "E8C64A")),
                BattleAbility(id: "dendri-branch-snap", name: "Branch Snap", damage: 30, detail: "A branching strike catches the enemy.", color: Color(hex: "F2D85B")),
                BattleAbility(id: "dendri-antigen-call", name: "Antigen Call", damage: 39, detail: "Dendri calls in a focused response.", color: Color(hex: "D7A72F"))
            ]
        case "neuro":
            return [
                BattleAbility(id: "neuro-spark", name: "Neuro Spark", damage: 21, detail: "Neuro sends a sharp signal forward.", color: Color(hex: "5FA3D4")),
                BattleAbility(id: "neuro-axon-rush", name: "Axon Rush", damage: 32, detail: "A signal rush slams into the target.", color: Color(hex: "7EB9F0")),
                BattleAbility(id: "neuro-synapse-storm", name: "Synapse Storm", damage: 41, detail: "Neuro chains a storm of tiny sparks.", color: Color(hex: "4D7FD4"))
            ]
        default:
            return [
                BattleAbility(id: "\(hero.id)-tap", name: "Study Tap", damage: 20, detail: "\(hero.name) keeps the review moving.", color: hero.color),
                BattleAbility(id: "\(hero.id)-burst", name: "Focus Burst", damage: 30, detail: "\(hero.name) turns recall into damage.", color: hero.color),
                BattleAbility(id: "\(hero.id)-combo", name: "Recall Combo", damage: 40, detail: "\(hero.name) lands a clean combo.", color: hero.color)
            ]
        }
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
        Hero(id: "mito", asset: "hero-mito-hop", name: "Mito", role: "Support", level: 12, hp: 48, attack: 18, defense: 14, color: Color(hex: "E77878"), lore: "A bean-shaped mitochondria helper with bright cristae. Turns focus into ATP and keeps the party steady when long study sessions get rough."),
        Hero(id: "cloro", asset: "hero-chloroplast-hop", name: "Chloro", role: "Striker", level: 11, hp: 42, attack: 22, defense: 11, color: Color(hex: "7BB55C"), lore: "A chloroplast striker who stores momentum between waves. Quick, bright, and built for clean bursts of damage."),
        Hero(id: "astro", asset: "hero-astrocyte-hop", name: "Astro", role: "Mage", level: 10, hp: 36, attack: 24, defense: 9, color: Color(hex: "A98FD0"), lore: "A star-shaped astrocyte mage who supports sharp thinking with quick bursts of cellular energy."),
        Hero(id: "dendri", asset: "hero-dendritic-cell-hop", name: "Dendri", role: "Support", level: 9, hp: 38, attack: 16, defense: 12, color: Color(hex: "E8C64A"), lore: "A branching dendritic-cell scout who keeps the team alert and turns small wins into streaks."),
        Hero(id: "neuro", asset: "hero-neuron-hop", name: "Neuro", role: "Tank", level: 13, hp: 56, attack: 14, defense: 22, color: Color(hex: "5FA3D4"), lore: "A sturdy neuron buffer with branching signals. Soaks pressure while fragile allies line up the next answer."),
        Hero(id: "bcell", asset: "hero-b-cell-hop", name: "B Cell", role: "Scholar", level: 8, hp: 34, attack: 17, defense: 10, color: Color(hex: "F4C6B8"), lore: "A careful immune scholar who translates effort into growth. Not flashy, but every session becomes something useful.")
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
