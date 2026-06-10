import SwiftUI

struct StudyWanderer: Identifiable {
    let id: String
    let asset: String
    let size: CGFloat
    let start: CGPoint
    let seed: UInt64

    /// Only the three heroes on the active team wander the study screen.
    /// Starting positions are randomized per-appearance (see StudyWanderingCharacter).
    static func forActiveTeam() -> [StudyWanderer] {
        let sizes: [CGFloat] = [60, 54, 56]
        return BattleRules.partyHeroes.enumerated().map { idx, hero in
            StudyWanderer(
                id: hero.id,
                asset: hero.asset,
                size: sizes[idx % sizes.count],
                start: CGPoint(x: 0.30 + 0.20 * Double(idx), y: 0.40),
                seed: stableSeed(hero.id)
            )
        }
    }

    // Distinct-id copies used by the full-screen focus session so they never
    // collide with the home-screen wanderers in StudyCollisionRegistry.
    static func focusTeam() -> [StudyWanderer] {
        forActiveTeam().map {
            StudyWanderer(id: $0.id + "-focus", asset: $0.asset, size: $0.size, start: $0.start, seed: $0.seed ^ 0x00F0_C500)
        }
    }

    /// Co-op: the characters belonging to OTHER lobby members, so a friend's
    /// team wanders your home meadow while you study together.
    static func forLobbyGuests(_ members: [LobbyPresence], myUserID: String) -> [StudyWanderer] {
        var result: [StudyWanderer] = []
        for member in members where member.userId != myUserID {
            for (i, cid) in member.characterIds.prefix(3).enumerated() {
                guard let hero = DataSet.heroes.first(where: { $0.id == cid }) ?? DataSet.capturable(id: cid)
                else { continue }
                result.append(StudyWanderer(
                    id: "guest-\(member.userId)-\(cid)",
                    asset: hero.asset,
                    size: 48,
                    start: CGPoint(x: 0.22 + 0.16 * Double(i), y: 0.58),
                    seed: stableSeed(member.userId + cid)))
            }
        }
        return result
    }

    private static func stableSeed(_ id: String) -> UInt64 {
        id.unicodeScalars.reduce(UInt64(0xC0FFEE)) { ($0 &* 31) &+ UInt64($1.value) }
    }
}

struct StudyWanderingCharacter: View {
    let wanderer: StudyWanderer
    let canvasSize: CGSize

    private let frameCount = 8
    private let secondsPerFrame = 0.14
    private let tick: TimeInterval = 1 / 30

    @State private var position: CGPoint
    @State private var isMoving = false
    @State private var isMovingRight = false
    @State private var frame = 0

    init(wanderer: StudyWanderer, canvasSize: CGSize) {
        self.wanderer = wanderer
        self.canvasSize = canvasSize
        // Randomize the spawn each time the screen opens so characters never
        // start in the same fixed spot.
        var g = SeededGenerator(seed: wanderer.seed ^ UInt64(Date().timeIntervalSince1970 * 1000))
        _position = State(initialValue: StudyWalkMap.randomWalkable(using: &g))
    }

    var body: some View {
        SpriteView(
            asset: wanderer.asset,
            size: wanderer.size,
            mirrored: isMovingRight,
            frame: isMoving ? frame : 0
        )
        .position(x: position.x * canvasSize.width, y: position.y * canvasSize.height)
        .task(id: wanderer.id) {
            await runWanderLoop()
        }
    }

    private func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// Fraction of a single hop's distance covered at a given cycle phase.
    /// The mito sprite is grounded on frames 0-2, airborne on 3-5, and landing
    /// on 6-7 — so it holds still on the ground and surges forward mid-air.
    private func hopGait(_ phase: Double) -> Double {
        let liftStart = 3.0 / Double(frameCount)   // leaves the ground (frame 3)
        let landStart = 6.0 / Double(frameCount)   // back on the ground (frame 6)
        if phase <= liftStart { return 0 }
        if phase >= landStart { return 1 }
        return smoothstep((phase - liftStart) / (landStart - liftStart))
    }

    @MainActor
    private func runWanderLoop() async {
        let launchVariance = UInt64(Date().timeIntervalSinceReferenceDate * 1_000)
        var generator = SeededGenerator(seed: wanderer.seed ^ launchVariance)
        // Keep the randomized spawn from init — no snap back to a fixed start.
        position = StudyWalkMap.clampedWalkable(position)
        isMoving = false
        frame = 0
        StudyCollisionRegistry.update(id: wanderer.id, position: position)

        while !Task.isCancelled {
            let rest = Double.random(in: 1.0...4.0, using: &generator)
            try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000))
            if Task.isCancelled { break }

            let start = position
            let occupied = StudyCollisionRegistry.occupiedPoints(excluding: wanderer.id)
            let target = StudyWalkMap.randomDestination(from: start, avoiding: occupied, using: &generator)
            let distance = start.distance(to: target)
            if distance < 0.015 { continue }
            guard StudyCollisionRegistry.reserve(id: wanderer.id, target: target, minimumDistance: StudyWalkMap.characterSpacing) else {
                continue
            }

            // Snap the trip to a whole number of hop cycles so horizontal travel
            // advances in discrete hops instead of one continuous glide.
            let hopPeriod = Double(frameCount) * secondsPerFrame
            let roughDuration = min(max(distance * 16, 1.15), 3.4)
            let hopCount = max(1, (roughDuration / hopPeriod).rounded())
            let duration = hopCount * hopPeriod
            let startTime = Date().timeIntervalSinceReferenceDate
            isMoving = true
            isMovingRight = target.x > start.x

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSinceReferenceDate - startTime
                if elapsed >= duration { break }

                // Frame + horizontal advance share one phase so movement is
                // locked to the hop: it surges while the sprite is airborne and
                // holds while it is on the ground.
                let cyclePos = elapsed / hopPeriod
                let completedHops = floor(cyclePos)
                let phase = cyclePos - completedHops
                let progress = min(1, (completedHops + hopGait(phase)) / hopCount)
                position = start.interpolated(to: target, progress: progress)
                StudyCollisionRegistry.update(id: wanderer.id, position: position)
                frame = Int(phase * Double(frameCount)) % frameCount
                try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
            }

            position = target
            StudyCollisionRegistry.update(id: wanderer.id, position: position)
            StudyCollisionRegistry.releaseReservation(id: wanderer.id)
            frame = 0
            isMoving = false
        }

        StudyCollisionRegistry.remove(id: wanderer.id)
    }
}

enum StudyWalkMap {
    static let characterSpacing = 0.11

    /// Extra clearance around props so a wanderer's body never clips trees,
    /// rocks, or the house — a "bubble" the character center must stay out of.
    private static let obstacleMargin = 0.045

    private static let walkBounds = CGRect(x: 0.08, y: 0.20, width: 0.78, height: 0.54)

    private static let obstacles: [CGRect] = [
        CGRect(x: 0.00, y: 0.00, width: 0.62, height: 0.18), // top trees and fence
        CGRect(x: 0.00, y: 0.35, width: 0.30, height: 0.25), // water and rocks
        CGRect(x: 0.55, y: 0.10, width: 0.45, height: 0.31), // house, mailbox, and right-side props
        CGRect(x: 0.49, y: 0.25, width: 0.12, height: 0.09), // house-side rocks and flowers
        CGRect(x: 0.75, y: 0.24, width: 0.12, height: 0.11), // mailbox and front props
        CGRect(x: 0.15, y: 0.57, width: 0.17, height: 0.09), // lower-left rocks
        CGRect(x: 0.66, y: 0.63, width: 0.22, height: 0.10), // lower-right fence
        CGRect(x: 0.87, y: 0.38, width: 0.13, height: 0.34), // right fence/tree edge
        CGRect(x: 0.00, y: 0.76, width: 1.00, height: 0.24) // study button and nav
    ]

    static func clampedWalkable(_ point: CGPoint) -> CGPoint {
        if isWalkable(point) { return point }
        // Start sits inside an obstacle bubble — spiral outward to the nearest
        // walkable tile so each wanderer keeps a distinct spot (instead of every
        // blocked character collapsing onto one shared fallback and freezing).
        var radius = 0.03
        while radius <= 0.45 {
            for degrees in stride(from: 0, to: 360, by: 30) {
                let angle = Double(degrees) * .pi / 180
                let candidate = CGPoint(x: point.x + cos(angle) * radius, y: point.y + sin(angle) * radius)
                if isWalkable(candidate) { return candidate }
            }
            radius += 0.03
        }
        return CGPoint(x: 0.45, y: 0.50)
    }

    /// A random walkable point anywhere on the map (used for randomized spawns).
    static func randomWalkable(using generator: inout SeededGenerator) -> CGPoint {
        for _ in 0..<160 {
            let candidate = CGPoint(
                x: Double.random(in: walkBounds.minX...walkBounds.maxX, using: &generator),
                y: Double.random(in: walkBounds.minY...walkBounds.maxY, using: &generator)
            )
            if isWalkable(candidate) { return candidate }
        }
        return CGPoint(x: 0.45, y: 0.50)
    }

    static func randomDestination(from current: CGPoint, avoiding occupied: [CGPoint], using generator: inout SeededGenerator) -> CGPoint {
        for _ in 0..<80 {
            let candidate = CGPoint(
                x: Double.random(in: walkBounds.minX...walkBounds.maxX, using: &generator),
                y: Double.random(in: walkBounds.minY...walkBounds.maxY, using: &generator)
            )
            let distance = current.distance(to: candidate)
            if distance >= 0.06,
               distance <= 0.28,
               isWalkable(candidate),
               clearsCharacters(candidate, avoiding: occupied),
               pathIsWalkable(from: current, to: candidate),
               pathClearsCharacters(from: current, to: candidate, avoiding: occupied) {
                return candidate
            }
        }

        return current
    }

    private static func isWalkable(_ point: CGPoint) -> Bool {
        guard walkBounds.contains(point) else { return false }
        // Inflate each obstacle by the clearance bubble before testing.
        return !obstacles.contains { $0.insetBy(dx: -obstacleMargin, dy: -obstacleMargin).contains(point) }
    }

    private static func clearsCharacters(_ point: CGPoint, avoiding occupied: [CGPoint]) -> Bool {
        !occupied.contains { point.distance(to: $0) < characterSpacing }
    }

    private static func pathClearsCharacters(from start: CGPoint, to end: CGPoint, avoiding occupied: [CGPoint]) -> Bool {
        for step in 0...12 {
            let progress = Double(step) / 12
            if !clearsCharacters(start.interpolated(to: end, progress: progress), avoiding: occupied) {
                return false
            }
        }
        return true
    }

    private static func pathIsWalkable(from start: CGPoint, to end: CGPoint) -> Bool {
        for step in 0...18 {
            let progress = Double(step) / 18
            if !isWalkable(start.interpolated(to: end, progress: progress)) {
                return false
            }
        }
        return true
    }
}

@MainActor
enum StudyCollisionRegistry {
    private static var positions: [String: CGPoint] = [:]
    private static var reservations: [String: CGPoint] = [:]

    static func update(id: String, position: CGPoint) {
        positions[id] = position
    }

    static func reserve(id: String, target: CGPoint, minimumDistance: Double) -> Bool {
        let blocked = occupiedPoints(excluding: id)
        guard !blocked.contains(where: { target.distance(to: $0) < minimumDistance }) else {
            return false
        }

        reservations[id] = target
        return true
    }

    static func releaseReservation(id: String) {
        reservations.removeValue(forKey: id)
    }

    static func remove(id: String) {
        positions.removeValue(forKey: id)
        reservations.removeValue(forKey: id)
    }

    static func occupiedPoints(excluding id: String) -> [CGPoint] {
        let current = positions.filter { $0.key != id }.map(\.value)
        let claimed = reservations.filter { $0.key != id }.map(\.value)
        return current + claimed
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        let dx = other.x - x
        let dy = other.y - y
        return sqrt(dx * dx + dy * dy)
    }

    func interpolated(to other: CGPoint, progress: Double) -> CGPoint {
        CGPoint(
            x: x + (other.x - x) * progress,
            y: y + (other.y - y) * progress
        )
    }
}

struct SpriteView: View {
    let asset: String
    let size: CGFloat
    var mirrored = false
    var frame = 0

    private let frameCount = 8
    private let frameAspectRatio: CGFloat = 200 / 128

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.32))
                .frame(width: size * 0.55, height: size * 0.13)
                .blur(radius: 1)
                .offset(y: 2)
            spriteFrame(frame)
        }
        .frame(width: size, height: size)
    }

    private func spriteFrame(_ frame: Int) -> some View {
        let frameWidth = size * frameAspectRatio
        let normalizedFrame = min(max(frame, 0), frameCount - 1)

        return Image(asset)
            .resizable()
            .interpolation(.none)
            .frame(width: frameWidth * CGFloat(frameCount), height: size)
            .offset(x: -frameWidth * CGFloat(normalizedFrame))
            .frame(width: frameWidth, height: size, alignment: .leading)
            .clipped()
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .frame(width: size, height: size)
    }
}
