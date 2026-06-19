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
    /// Non-blocking wait: shows only a small top banner (no dim, taps pass through) while the
    /// player fights/navigates freely. Advances when `TutorialManager.complete(target)` fires —
    /// used to wait out a campaign battle or a post-win popup without blocking the screen.
    case wait(target: String, caption: String?)
    /// Point out a real control without forcing the player to use it right now.
    case coach(target: String, caption: String)

    var spotlightTarget: String? {
        if case .spotlight(let t, _) = self { return t }
        return nil
    }

    /// The id that `complete(_:)` must match to advance this beat (spotlight or wait).
    var advanceTarget: String? {
        switch self {
        case .spotlight(let t, _): return t
        case .wait(let t, _): return t
        case .say, .coach: return nil
        }
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

    /// True while a dimmed `.say` dialogue is on screen (so the home UI behind it
    /// can hide and not bleed through). Spotlight beats keep the UI visible.
    var isSaying: Bool { if case .say = current { return true } else { return false } }

    func start(goal: String) {
        guard !active else { return }
        script = TutorialScript.session1(goal: goal)
        #if DEBUG
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-uitestTutorialStep=") }),
           let requested = Int(arg.dropFirst("-uitestTutorialStep=".count)) {
            index = min(max(0, requested), max(0, script.count - 1))
        } else {
            index = 0
        }
        #else
        index = 0
        #endif
        withAnimation(.easeOut(duration: 0.25)) { active = true }
    }

    /// Start the tutorial again from a clean tutorial-only state without
    /// deleting the player's real roster, campaign, decks, or currencies.
    func replay(goal: String) {
        withAnimation(.easeOut(duration: 0.15)) { active = false }
        index = 0
        script = []
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "mito.tutorialSeen")
        defaults.removeObject(forKey: "mito.tutorialFocusBonusClaimed")
        CampaignStoryManager.shared.prepareTutorialReplay()
        start(goal: goal)
    }

    /// Advance from a dialogue tap or a finished spotlight.
    func advance() {
        guard active else { return }
        if index + 1 >= script.count { finish(); return }
        withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
    }

    /// The game performed a spotlighted action — advance only if it matches the current target.
    func complete(_ target: String) {
        guard active, current?.advanceTarget == target else { return }
        advance()
    }

    func isWaiting(for target: String) -> Bool {
        active && current?.advanceTarget == target
    }

    func claimFocusBonus() -> Bool {
        let key = "mito.tutorialFocusBonusClaimed"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)
        return true
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
            .say(speaker: mito, name: L("Mito"),
                 text: L("oh, you're here. good, 'cause we've got a situation.")),
            .say(speaker: mito, name: L("Mito"),
                 text: L("see that? a Mutagem. it eats the stuff you forget. right now it's just you and me against it."),
                 partner: "wild-mutagem-hop", partnerName: L("Mutagem")),
            .say(speaker: mito, name: L("Mito"),
                 text: L("here's the deal. answer a flashcard right and we hit it. your brain is the weapon. kinda poetic, right?")),
            .say(speaker: mito, name: L("Mito"),
                 text: g.isEmpty
                    ? L("let's start with the Campaign. that's where the story moves forward and new BioBuds join you.")
                    : Lf("i loaded you up with some %@ cards. let's use them to rescue our first teammate.", L(g))),
            .spotlight(target: "tab.battle", caption: L("head over to Battle ⚔")),
            .spotlight(target: "battle.campaign", caption: L("open the Campaign map")),
            .spotlight(target: "campaign.stage1", caption: L("tap Stage 1 to meet Chloro")),
            .spotlight(target: "campaign.pickDeck", caption: L("pick the flashcard deck you want to fight with")),
            .spotlight(target: "campaign.start", caption: L("enter the dungeon")),
            .say(speaker: mito, name: L("Mito"),
                 text: L("one card becomes one combat turn. Recall the answer, grade yourself honestly, then choose the BioBud's move.")),
            .spotlight(target: "battle.showAnswer", caption: L("try to recall it… then reveal the answer")),
            .spotlight(target: "battle.grade", caption: L("rate how well you knew it, be honest")),
            .spotlight(target: "battle.ability", caption: L("choose a move to attack")),
            .wait(target: "campaign.cleared.1", caption: L("keep reviewing until Chloro is free")),
            .wait(target: "campaign.return", caption: L("add Chloro to your roster, collect the stage rewards, then continue")),
            .say(speaker: mito, name: L("Mito"),
                 text: L("Chloro joined the roster, but Campaign recruits cannot fight immediately. First you earn their Trust by studying together."),
                 partner: "hero-chloroplast-hop", partnerName: L("Chloro")),
            .spotlight(target: "tab.home", caption: L("back to your meadow")),
            .spotlight(target: "study", caption: L("open the study menu")),
            .wait(target: "study.companion.cloro", caption: L("select Chloro under STUDY WITH")),
            .say(speaker: mito, name: L("Mito"),
                 text: L("Every completed minute fills Chloro's Trust bar. Once it reaches full, Chloro unlocks for your battle team. Leaving early can damage unfinished Trust."),
                 partner: "hero-chloroplast-hop", partnerName: L("Chloro")),
            .spotlight(target: "study.mode.focus", caption: L("start a 25-minute Focus session")),
            .wait(target: "study.tutorialComplete", caption: L("tap the glowing SKIP 25 MINUTES button to continue instantly")),
            .say(speaker: mito, name: L("Mito"),
                 text: L("Study sessions can give you all kinds of rewards, including ATP, Gold, Biomass, upgrade materials, and even eggs. This session gave you your first egg!")),
            .spotlight(target: "home.eggs", caption: L("open your egg inventory")),
            .wait(target: "egg.hatched", caption: L("tap HATCH ×1, draw one continuous crack, then release")),
            .wait(target: "egg.return", caption: L("meet your new BioBud, then tap CONTINUE")),
            .say(speaker: mito, name: L("Mito"),
                 text: L("yay, you got a new BioBud! Eggs can hatch BioBuds of different rarities—the rarer they are, the harder they are to find.")),
            .say(speaker: mito, name: L("Mito"),
                 text: L("If you hatch a BioBud you already own, the duplicate becomes Shards. Use those Shards to upgrade that BioBud and make it stronger.")),
            .spotlight(target: "tab.cards", caption: L("last stop: your flashcard library")),
            .say(speaker: mito, name: L("Mito"),
                 text: L("decks power every review battle. Make a deck, open it, then add cards with a front, back, and optional tags. Saved cards are immediately available in Battle.")),
            .coach(target: "cards.new",
                   caption: L("Use + NEW to create a deck. Open that deck and tap + ADD CARD to write the front, back, and tags.")),
            .coach(target: "cards.import",
                   caption: L("Already use Anki? Tap IMPORT, then IMPORT ANKI DECK and choose the .apkg file exported from Anki.")),
            .say(speaker: mito, name: L("Mito"),
                 text: L("that's the full loop: make or import cards, rescue BioBuds in Campaign, earn their Trust through real focus, hatch study eggs, and grow the team. 🫡")),
        ]
    }
}

/// Resolves anchor frames and renders whichever overlay the current beat needs.
struct TutorialHost: View {
    @ObservedObject private var manager = TutorialManager.shared
    @ObservedObject private var story = CampaignStoryManager.shared
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
            case let .wait(_, caption):
                if !story.isSaying {
                    TutorialWaitBanner(caption: caption, onSkip: { manager.skip() })
                        .transition(.opacity)
                        .zIndex(60)
                }
            case let .coach(target, caption):
                TutorialSpotlight(
                    rect: anchors[target],
                    caption: caption,
                    size: size,
                    onAdvance: { manager.advance() },
                    onSkip: { manager.skip() }
                )
                .zIndex(60)
            }
        }
    }
}

/// Non-blocking tutorial state: a small pulsing banner (and a skip) at the top
/// while the player fights or navigates underneath — taps pass straight through
/// except on the skip button. Used to wait out a campaign battle / post-win popup.
private struct TutorialWaitBanner: View {
    let caption: String?
    let onSkip: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                if let caption {
                    Text(caption)
                        .pixelText(size: 11, color: .white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 250, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(hex: "18100A").opacity(0.85))
                        .overlay(Rectangle().stroke(Color(hex: "FFD24D"), lineWidth: 2))
                        .opacity(pulse ? 1 : 0.72)
                        .allowsHitTesting(false)
                }
                Spacer(minLength: 0)
                Button(action: onSkip) {
                    Text("skip")
                        .font(.custom(MitoFont.regular, size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(hex: "18100A").opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 54)
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
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
                        SpriteView(asset: partner, size: 132, mirrored: true, frame: 0)
                    }
                    Spacer()
                    SpriteView(asset: speaker, size: 170, frame: 0)
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
                .padding(.bottom, 34)   // clearance above the home indicator (inside the card)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
                .padding(.horizontal, 16)
                // No bottom padding: the card reaches the screen edge, so nothing
                // (nav tray, safe-area fill) can peek out beneath it as a second box.
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
    var onAdvance: (() -> Void)? = nil
    let onSkip: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            if let r = rect {
                dim(0, 0, size.width, max(0, r.minY))                                    // top
                dim(0, r.maxY, size.width, max(0, size.height - r.maxY))                 // bottom
                dim(0, r.minY, max(0, r.minX), r.height)                                 // left
                dim(r.maxX, r.minY, max(0, size.width - r.maxX), r.height)               // right

                // Required-action spotlights circle the real control. Coach
                // beats keep that control illuminated for context, but circle
                // the tutorial's Next button instead so it is clear what to tap.
                if onAdvance == nil {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "FFD24D"), lineWidth: 4)
                        .frame(width: r.width + 18, height: r.height + 18)
                        // Scale BEFORE positioning so the ring pulses around its own
                        // center (big → small in place), instead of drifting toward
                        // the screen center the way scaling a positioned view does.
                        .scaleEffect(pulse ? 1.18 : 0.9)
                        .position(x: r.midX, y: r.midY)
                        .opacity(pulse ? 0.6 : 1)
                        .allowsHitTesting(false)
                }

                if let caption {
                    Text(caption)
                        .pixelText(size: 12, color: .white)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color(hex: "18100A").opacity(0.85))
                        .overlay(Rectangle().stroke(Color(hex: "FFD24D"), lineWidth: 2))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: max(180, size.width - 44))
                        .position(x: size.width / 2,
                                  y: captionY(for: r))
                        .allowsHitTesting(false)
                }

                if let onAdvance {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "FFD24D"), lineWidth: 5)
                        .frame(width: 116, height: 62)
                        .scaleEffect(pulse ? 1.14 : 0.94)
                        .position(x: size.width / 2, y: nextButtonY(for: r))
                        .opacity(pulse ? 0.65 : 1)
                        .allowsHitTesting(false)

                    Color.clear
                        .frame(width: r.width, height: r.height)
                        .contentShape(Rectangle())
                        .position(x: r.midX, y: r.midY)
                        .onTapGesture { }

                    Button(action: onAdvance) {
                        Text("NEXT ▸")
                            .pixelText(size: 11, color: Color(hex: "18100A"))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(Color(hex: "FFD24D"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .position(x: size.width / 2, y: nextButtonY(for: r))
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
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: max(180, size.width - 44))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color(hex: "18100A").opacity(0.85))
                        .overlay(Rectangle().stroke(Color(hex: "FFD24D"), lineWidth: 2))
                        .position(x: size.width / 2, y: size.height * 0.5)
                        .allowsHitTesting(false)
                }

                if let onAdvance {
                    Button(action: onAdvance) {
                        Text("NEXT ▸")
                            .pixelText(size: 11, color: Color(hex: "18100A"))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(Color(hex: "FFD24D"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .position(x: size.width / 2, y: size.height - 72)
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

    private func captionY(for rect: CGRect) -> CGFloat {
        let proposed = rect.minY > size.height * 0.34 ? rect.minY - 64 : rect.maxY + 64
        return min(max(proposed, 92), size.height - 132)
    }

    /// Coach beats render both explanatory copy and a Next button. Keep the
    /// button on the opposite side of the caption so wrapped copy can never
    /// be covered by it.
    private func nextButtonY(for rect: CGRect) -> CGFloat {
        let caption = captionY(for: rect)
        let separation: CGFloat = 112
        if caption < size.height / 2 {
            return min(size.height - 72, caption + separation)
        }
        return max(92, caption - separation)
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
    /// Campaign story beats are all dialogue, so any active scene means a dimmed
    /// dialogue is on screen.
    var isSaying: Bool { active }

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

    /// Replay only the Stage 1 story used by onboarding. Other campaign story
    /// progress remains untouched.
    func prepareTutorialReplay() {
        currentID = nil
        onFinish = nil
        script = []
        index = 0
        seen.remove("intro.1")
        seen.remove("outro.1")
        UserDefaults.standard.set(Array(seen), forKey: seenKey)
    }

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
                .say(speaker: mito, name: L("Mito"),
                     text: L("there. a chloroplast. or it was one. the Fading's got it. see how the light's gone grey?")),
                .say(speaker: mito, name: L("Mito"),
                     text: L("it won't hear words anymore, only remembering. recall it clean and we'll pull it back to itself."))
            ]
        case 2:
            return [
                .say(speaker: mito, name: L("Mito"),
                     text: L("spoke too soon. that spiky thing's a Spikevyrus scout. the Fading isn't just happening. something's spreading it.")),
                .say(speaker: chloro, name: L("Chloro"),
                     text: L("so we're not curing a sickness. we're fighting whatever WANTS us sick. cool. love that."),
                     partner: mito, partnerName: L("Mito")),
                .say(speaker: mito, name: L("Mito"),
                     text: L("wear it down and you can bind it to the team. even a scout knows where it crawled from. let's catch one."),
                     partner: chloro, partnerName: L("Chloro"))
            ]
        case 3:
            return [
                .say(speaker: mito, name: L("Mito"),
                     text: L("feel that static? that's a neuron. Neuro. its signals are scrambled. the Fading hits memory hardest here.")),
                .say(speaker: chloro, name: L("Chloro"),
                     text: L("it's twitching like it forgot how to think."),
                     partner: mito, partnerName: L("Mito")),
                .say(speaker: mito, name: L("Mito"),
                     text: L("because it did. same as you were. recall it sharp and we'll straighten its wires out."),
                     partner: chloro, partnerName: L("Chloro"))
            ]
        default:
            return []
        }
    }

    static func outro(stage: Int) -> [TutorialBeat] {
        switch stage {
        case 1:
            return [
                .say(speaker: chloro, name: L("Chloro"),
                     text: L("…oh. OH. the light. it's back. how long was i out?"),
                     partner: mito, partnerName: L("Mito")),
                .say(speaker: mito, name: L("Mito"),
                     text: L("long enough. welcome back, Chloro."),
                     partner: chloro, partnerName: L("Chloro")),
                .say(speaker: chloro, name: L("Chloro"),
                     text: L("i had the weirdest dream where i was a feral lamp. …we don't talk about it. let's move."),
                     partner: mito, partnerName: L("Mito"))
            ]
        case 2:
            return [
                .say(speaker: mito, name: L("Mito"),
                     text: L("that's the idea. every one we take is one less spreading the Fading."),
                     partner: chloro, partnerName: L("Chloro")),
                .say(speaker: chloro, name: L("Chloro"),
                     text: L("and a little extra muscle never hurts. onward, bean."),
                     partner: mito, partnerName: L("Mito"))
            ]
        case 3:
            return [
                .say(speaker: neuro, name: L("Neuro"),
                     text: L("…signal restored. systems nominal. who pulled me back?"),
                     partner: mito, partnerName: L("Mito")),
                .say(speaker: mito, name: L("Mito"),
                     text: L("team effort. you're one of us now, if you want in."),
                     partner: neuro, partnerName: L("Neuro")),
                .say(speaker: neuro, name: L("Neuro"),
                     text: L("i hold the line. nothing gets past me twice."),
                     partner: mito, partnerName: L("Mito")),
                .say(speaker: chloro, name: L("Chloro"),
                     text: L("oh good, a wall with opinions. this'll be fun."),
                     partner: neuro, partnerName: L("Neuro")),
                .say(speaker: mito, name: L("Mito"),
                     text: L("play nice, you two. that's three of us now. the team's coming together. let's go free the rest."),
                     partner: chloro, partnerName: L("Chloro"))
            ]
        default:
            return []
        }
    }
}
