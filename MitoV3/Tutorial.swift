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
    /// game calls `TutorialManager.complete(target)`. If the target can't be found, the dim is
    /// tappable so the flow can never soft-lock.
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
    /// Session 1 — the opening hook. Phase-2 battle/study beats get inserted after the
    /// STUDY spotlight as they're wired into those screens.
    static func session1(goal: String) -> [TutorialBeat] {
        let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            .say(speaker: "hero-mito-hop", name: "Mito",
                 text: "oh — you're here. good, 'cause we've got a situation."),
            .say(speaker: "hero-mito-hop", name: "Mito",
                 text: "see that? a Mutagem. it feeds on the stuff you forget. rude, honestly.",
                 partner: "wild-mutagem-hop", partnerName: "Mutagem"),
            .say(speaker: "hero-mito-hop", name: "Mito",
                 text: "the deal is simple — answer a flashcard right, and we hit it. your brain's the weapon. kinda poetic."),
            .say(speaker: "hero-mito-hop", name: "Mito",
                 text: g.isEmpty
                    ? "let's get a real run going. tap STUDY whenever you're ready."
                    : "i loaded you up with some \(g) cards. let's put 'em to work."),
            .spotlight(target: "study", caption: "tap STUDY to start your first run")
        ]
    }
}

/// Resolves anchor frames and renders whichever overlay the current beat needs.
struct TutorialHost: View {
    @ObservedObject private var manager = TutorialManager.shared
    let anchors: [String: CGRect]

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
                TutorialSpotlight(rect: anchors[target], caption: caption,
                                  onAdvance: { manager.advance() })
                    .zIndex(60)
            }
        }
    }
}

/// Dimmed dialogue: Mito bottom-right, optional partner bottom-left facing in, tap to continue.
private struct TutorialDialogue: View {
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
private struct TutorialSpotlight: View {
    let rect: CGRect?
    let caption: String?
    let onAdvance: () -> Void
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let r = rect {
                    dim(0, 0, geo.size.width, max(0, r.minY))                                    // top
                    dim(0, r.maxY, geo.size.width, max(0, geo.size.height - r.maxY))             // bottom
                    dim(0, r.minY, max(0, r.minX), r.height)                                     // left
                    dim(r.maxX, r.minY, max(0, geo.size.width - r.maxX), r.height)               // right

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
                            .position(x: geo.size.width / 2,
                                      y: r.minY > 120 ? r.minY - 34 : r.maxY + 40)
                            .allowsHitTesting(false)
                    }
                } else {
                    // Target not measured yet — full dim that advances on tap (no soft-lock).
                    Color.black.opacity(0.6).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onAdvance)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
        .ignoresSafeArea()
    }

    private func dim(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        Color.black.opacity(0.7)
            .frame(width: w, height: h)
            .position(x: x + w / 2, y: y + h / 2)
            .contentShape(Rectangle())
            .onTapGesture { }   // swallow taps everywhere except the spotlight hole
    }
}

