//  Tutorial.swift
//  Extracted from ContentView.swift (behavior-preserving refactor).

import SwiftUI

struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Mark this view as a tutorial spotlight target (e.g. `.tutorialAnchor("study")`).
    func tutorialAnchor(_ id: String) -> some View {
        anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

/// One scripted moment in the tutorial.
enum TutorialBeat: Equatable {
    /// Mito (and an optional partner on the opposite side) speaks; tap anywhere to continue.
    case say(speaker: String, name: String, text: String, partner: String? = nil, partnerName: String? = nil)
    /// Dim everything except `target`; only the real target stays tappable. Advances when the
    /// game calls `TutorialManager.complete(target)`. If the target can't be found, the dim
    /// swallows taps (so a stray tap can't skip the lesson) and the persistent "skip" button is
    /// the soft-lock escape hatch.
    case spotlight(target: String, caption: String?)

    var spotlightTarget: String? {
        if case .spotlight(let t, _) = self { return t }
        return nil
    }
}

@MainActor
final class TutorialManager: ObservableObject {
    static let shared = TutorialManager()
    @Published var active = false
    @Published var index = 0
    @Published private(set) var script: [TutorialBeat] = []
    private init() {}

    var current: TutorialBeat? {
        guard active, index >= 0, index < script.count else { return nil }
        return script[index]
    }

    func start(goal: String) {
        guard !active else { return }
        script = TutorialScript.session1(goal: goal)
        index = 0
        withAnimation(.easeOut(duration: 0.25)) { active = true }
    }

    /// Advance from a dialogue tap or a finished spotlight.
    func advance() {
        guard active else { return }
        if index + 1 >= script.count { finish(); return }
        withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
    }

    /// The game performed a spotlighted action — advance only if it matches the current target.
    func complete(_ target: String) {
        guard active, current?.spotlightTarget == target else { return }
        advance()
    }

    func skip() { finish() }

    private func finish() {
        withAnimation(.easeOut(duration: 0.25)) { active = false }
        UserDefaults.standard.set(true, forKey: "mito.tutorialSeen")
    }
}

enum TutorialScript {
    /// Session 1 — battle-first hook. Rides the REAL flow via spotlights on real controls
    /// (advance only when the player performs the action) + dialogue between state changes.
    static func session1(goal: String) -> [TutorialBeat] {
        let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let mito = "hero-mito-hop"
        return [
            // — Hook
            .say(speaker: mito, name: "Mito",
                 text: "oh — you're here. good, 'cause we've got a situation."),
            .say(speaker: mito, name: "Mito",
                 text: "see that? a Mutagem. it feeds on the stuff you forget. and right now it's just you and me against it.",
                 partner: "wild-mutagem-hop", partnerName: "Mutagem"),
            .say(speaker: mito, name: "Mito",
                 text: "the deal is simple — answer a flashcard right, and we hit it. your brain's the weapon. kinda poetic."),
            .say(speaker: mito, name: "Mito",
                 text: g.isEmpty
                    ? "let's get you into a real fight. follow me."
                    : "i loaded you up with some \(g) cards. let's put 'em to work."),
            // — Into the first battle
            .spotlight(target: "tab.battle", caption: "head over to Battle ⚔"),
            .spotlight(target: "battle.endless", caption: "start with Endless Review — no pressure"),
            .spotlight(target: "battle.pickDeck", caption: "pick a deck — tap any one"),
            .spotlight(target: "battle.startEndless", caption: "now hit Start (it's free)"),
            // — The core loop (real combat)
            .say(speaker: mito, name: "Mito",
                 text: "okay. one card, one hit. let's see what you've got."),
            .spotlight(target: "battle.showAnswer", caption: "try to recall it… then reveal the answer"),
            .spotlight(target: "battle.grade", caption: "rate how well you knew it — be honest"),
            .spotlight(target: "battle.ability", caption: "now hit it — pick a move"),
            .say(speaker: mito, name: "Mito",
                 text: "LET'S GO. that's the whole loop — answer, attack, repeat. you've basically got it."),
            // — Bridge to study / ATP
            .say(speaker: mito, name: "Mito",
                 text: "battles train your memory. and studying earns ATP to power the team up."),
            .spotlight(target: "tab.home", caption: "back to your meadow"),
            .spotlight(target: "study", caption: "this is your real focus time — every session earns ATP"),
            // — Point them at the campaign / first recruit
            .say(speaker: mito, name: "Mito",
                 text: "one more thing — we don't have to fight solo forever."),
            .say(speaker: mito, name: "Mito",
                 text: "clear a Campaign stage and its boss joins our team. first up is Chloro — a chloroplast who hits HARD.",
                 partner: "hero-chloroplast-hop", partnerName: "Chloro"),
            .say(speaker: mito, name: "Mito",
                 text: "head to Battle → Campaign when you're ready to go recruit 'em. you got this. 🫡"),
        ]
    }
}

/// Resolves anchor frames and renders whichever overlay the current beat needs.
struct TutorialHost: View {
    @ObservedObject private var manager = TutorialManager.shared
    let anchors: [String: CGRect]
    let size: CGSize

    var body: some View {
        if let beat = manager.current {
            switch beat {
            case let .say(speaker, name, text, partner, partnerName):
                TutorialDialogue(speaker: speaker, name: name, text: text,
                                 partner: partner, partnerName: partnerName,
                                 onAdvance: { manager.advance() }, onSkip: { manager.skip() })
                    .transition(.opacity)
                    .zIndex(60)
            case let .spotlight(target, caption):
                TutorialSpotlight(rect: anchors[target], caption: caption, size: size,
                                  onSkip: { manager.skip() })
                    .zIndex(60)
            }
        }
    }
}

/// Dimmed dialogue: Mito bottom-right, optional partner bottom-left facing in, tap to continue.
/// Shared by the one-shot tutorial and the campaign story (`CampaignStoryHost`).
struct TutorialDialogue: View {
    let speaker: String, name: String, text: String
    let partner: String?, partnerName: String?
    let onAdvance: () -> Void
    let onSkip: () -> Void
    @State private var hintOn = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onAdvance)

            VStack(spacing: 0) {
                Spacer()
                HStack(alignment: .bottom) {
                    if let partner {
                        SpriteView(asset: partner, size: 132, mirrored: true, frame: 2)
                    }
                    Spacer()
                    SpriteView(asset: speaker, size: 170, frame: 2)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, -10)
                .allowsHitTesting(false)
                .zIndex(1)

                VStack(alignment: .leading, spacing: 8) {
                    Text(name).pixelText(size: 12, color: Color(hex: "4A8A3C"))
                    Text(text)
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "3A2A18"))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                    HStack {
                        Spacer()
                        Text("tap to continue ▸")
                            .font(.custom(MitoFont.regular, size: 11))
                            .foregroundStyle(Color(hex: "6B4324"))
                            .opacity(hintOn ? 1 : 0.35)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onSkip) {
                        Text("skip")
                            .font(.custom(MitoFont.regular, size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.top, 8).padding(.trailing, 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { hintOn = true }
        }
    }
}

/// Spotlight coachmark: dims everything except `rect`, pulses a ring on it, and leaves the
/// real control tappable (the four dim panels around the hole block everything else).
/// It advances ONLY when the game performs the matching action (`TutorialManager.complete`),
/// never on a stray tap — so it can't skip a lesson. A persistent "skip" prevents soft-locks
/// (e.g. if a target never renders or the player is on the wrong screen).
private struct TutorialSpotlight: View {
    let rect: CGRect?
    let caption: String?
    let size: CGSize
    let onSkip: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            if let r = rect {
                dim(0, 0, size.width, max(0, r.minY))                                    // top
                dim(0, r.maxY, size.width, max(0, size.height - r.maxY))                 // bottom
                dim(0, r.minY, max(0, r.minX), r.height)                                 // left
                dim(r.maxX, r.minY, max(0, size.width - r.maxX), r.height)               // right

                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "FFD24D"), lineWidth: 4)
                    .frame(width: r.width + 18, height: r.height + 18)
                    .position(x: r.midX, y: r.midY)
                    .scaleEffect(pulse ? 1.05 : 0.97)
                    .opacity(pulse ? 0.35 : 1)
                    .allowsHitTesting(false)

                if let caption {
                    Text(caption)
                        .pixelText(size: 12, color: .white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color(hex: "18100A").opacity(0.85))
                        .overlay(Rectangle().stroke(Color(hex: "FFD24D"), lineWidth: 2))
                        .fixedSize()
                        .position(x: size.width / 2,
                                  y: r.minY > 120 ? r.minY - 34 : r.maxY + 40)
                        .allowsHitTesting(false)
                }
            } else {
                // Target not on-screen yet: dim + caption + wait (advance comes from `complete`).
                Color.black.opacity(0.6)
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { }   // swallow taps; do NOT advance (would skip the lesson)
                if let caption {
                    Text(caption)
                        .pixelText(size: 12, color: .white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color(hex: "18100A").opacity(0.85))
                        .overlay(Rectangle().stroke(Color(hex: "FFD24D"), lineWidth: 2))
                        .position(x: size.width / 2, y: size.height * 0.5)
                        .allowsHitTesting(false)
                }
            }

            // Persistent skip — guarantees no soft-lock.
            VStack {
                HStack {
                    Spacer()
                    Button(action: onSkip) {
                        Text("skip")
                            .font(.custom(MitoFont.regular, size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color(hex: "18100A").opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.top, 50).padding(.trailing, 12)
        }
        .frame(width: size.width, height: size.height)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func dim(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        // NOTE: contentShape + onTapGesture must be applied BEFORE .position. `.position`
        // returns a view that fills the entire parent, so attaching the hit area after it
        // would make the whole screen swallow taps — covering the spotlight hole too.
        Color.black.opacity(0.7)
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .onTapGesture { }   // swallow taps only within this dim panel, not the hole
            .position(x: x + w / 2, y: y + h / 2)
    }
}

// MARK: - Campaign story (inter-character dialogue around campaign stages)

/// Plays short story scenes before/after campaign stages, reusing the tutorial's
/// dialogue UI. Unlike `TutorialManager` (a one-shot guided flow), this fires
/// once per scene as the player reaches each stage, and runs a completion
/// handler when a scene ends (used to chain into the recruit/capture popup).
@MainActor
final class CampaignStoryManager: ObservableObject {
    static let shared = CampaignStoryManager()
    @Published private(set) var script: [TutorialBeat] = []
    @Published private(set) var index = 0
    private var onFinish: (() -> Void)?
    private var currentID: String?
    private let seenKey = "campaign.story.seen"
    private var seen: Set<String>

    private init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
    }

    var active: Bool { !script.isEmpty }
    var current: TutorialBeat? {
        guard active, index >= 0, index < script.count else { return nil }
        return script[index]
    }

    /// Play a scene once (keyed by `id`). If already seen or empty, the optional
    /// completion runs immediately so callers can chain reliably. The scene is
    /// marked seen only once it actually FINISHES (see `finish`), so an app-kill
    /// mid-scene replays it next time rather than silently dropping it (and the
    /// chained recruit/capture callback).
    func playOnce(_ id: String, _ beats: [TutorialBeat], onFinish: (() -> Void)? = nil) {
        guard !seen.contains(id) else { onFinish?(); return }
        guard !beats.isEmpty else { markSeen(id); onFinish?(); return }
        currentID = id
        self.onFinish = onFinish
        index = 0
        withAnimation(.easeOut(duration: 0.25)) { script = beats }
    }

    func advance() {
        guard active else { return }
        if index + 1 >= script.count { finish(); return }
        withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
    }

    /// Skip the rest of the current scene (still marks it seen + fires completion).
    func skip() { finish() }

    private func finish() {
        if let id = currentID { markSeen(id) }
        currentID = nil
        let handler = onFinish
        onFinish = nil
        withAnimation(.easeOut(duration: 0.25)) { script = [] }
        index = 0
        handler?()
    }

    private func markSeen(_ id: String) {
        seen.insert(id)
        UserDefaults.standard.set(Array(seen), forKey: seenKey)
    }

    /// Clear seen scenes (account deletion / privacy).
    func reset() {
        seen = []
        UserDefaults.standard.removeObject(forKey: seenKey)
        script = []
        index = 0
        onFinish = nil
        currentID = nil
    }
}

/// Renders the current campaign-story line using the shared dialogue UI.
struct CampaignStoryHost: View {
    @ObservedObject private var story = CampaignStoryManager.shared

    var body: some View {
        if case let .say(speaker, name, text, partner, partnerName) = story.current {
            TutorialDialogue(speaker: speaker, name: name, text: text,
                             partner: partner, partnerName: partnerName,
                             onAdvance: { story.advance() }, onSkip: { story.skip() })
                .transition(.opacity)
                .zIndex(70)
        }
    }
}

/// The written scenes. Each stage has an `intro` (plays as combat opens, with the
/// boss on screen behind the dim) and an `outro` (plays after the win, before the
/// recruit/capture popup). Only stages 1–3 are scripted so far — the prologue's
/// solo fight, the Spikevyrus scout, and Neuro's rescue.
enum CampaignStoryScript {
    private static let mito = "hero-mito-hop"
    private static let chloro = "hero-chloroplast-hop"
    private static let neuro = "hero-neuron-hop"

    static func intro(stage: Int) -> [TutorialBeat] {
        switch stage {
        case 1:
            return [
                .say(speaker: mito, name: "Mito",
                     text: "there — a chloroplast. or it was one. the Fading's got it; see how the light's gone grey?"),
                .say(speaker: mito, name: "Mito",
                     text: "it won't hear words anymore — only remembering. recall clean and we'll pull it back to itself.")
            ]
        case 2:
            return [
                .say(speaker: mito, name: "Mito",
                     text: "spoke too soon. that spiky thing's a Spikevyrus scout. the Fading isn't just happening — something's spreading it."),
                .say(speaker: chloro, name: "Chloro",
                     text: "so we're not curing a sickness. we're fighting whatever WANTS us sick. cool. love that.",
                     partner: mito, partnerName: "Mito"),
                .say(speaker: mito, name: "Mito",
                     text: "wear it down and you can bind it to the team — even a scout knows where it crawled from. let's catch one.",
                     partner: chloro, partnerName: "Chloro")
            ]
        case 3:
            return [
                .say(speaker: mito, name: "Mito",
                     text: "feel that static? a neuron — Neuro — and its signals are scrambled. the Fading hits memory hardest here."),
                .say(speaker: chloro, name: "Chloro",
                     text: "it's twitching like it forgot how to think.",
                     partner: mito, partnerName: "Mito"),
                .say(speaker: mito, name: "Mito",
                     text: "because it did — same as you were. recall sharp and we'll straighten its wires out.",
                     partner: chloro, partnerName: "Chloro")
            ]
        default:
            return []
        }
    }

    static func outro(stage: Int) -> [TutorialBeat] {
        switch stage {
        case 1:
            return [
                .say(speaker: chloro, name: "Chloro",
                     text: "…oh. OH. the light — it's back. how long was i out?",
                     partner: mito, partnerName: "Mito"),
                .say(speaker: mito, name: "Mito",
                     text: "long enough. welcome back, Chloro.",
                     partner: chloro, partnerName: "Chloro"),
                .say(speaker: chloro, name: "Chloro",
                     text: "i had the weirdest dream where i was a feral lamp. …we don't talk about it. let's move.",
                     partner: mito, partnerName: "Mito")
            ]
        case 2:
            return [
                .say(speaker: mito, name: "Mito",
                     text: "that's the idea. every one we take is one less spreading the Fading.",
                     partner: chloro, partnerName: "Chloro"),
                .say(speaker: chloro, name: "Chloro",
                     text: "and a little extra muscle never hurts. onward, bean.",
                     partner: mito, partnerName: "Mito")
            ]
        case 3:
            return [
                .say(speaker: neuro, name: "Neuro",
                     text: "…signal restored. systems nominal. who pulled me back?",
                     partner: mito, partnerName: "Mito"),
                .say(speaker: mito, name: "Mito",
                     text: "team effort. you're one of us now — if you want in.",
                     partner: neuro, partnerName: "Neuro"),
                .say(speaker: neuro, name: "Neuro",
                     text: "i hold the line. nothing gets past me twice.",
                     partner: mito, partnerName: "Mito"),
                .say(speaker: chloro, name: "Chloro",
                     text: "oh good, a wall with opinions. this'll be fun.",
                     partner: neuro, partnerName: "Neuro"),
                .say(speaker: mito, name: "Mito",
                     text: "play nice, you two. that's three of us — the team's coming together. now let's go free the rest.",
                     partner: chloro, partnerName: "Chloro")
            ]
        default:
            return []
        }
    }
}

