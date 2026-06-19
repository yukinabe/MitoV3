import SwiftUI

struct TeamScreen: View {
    @Binding var atp: Int
    @Binding var gold: Int
    @Binding var biomass: Int
    var selectedTab: AppTab = .team
    @State private var activePartySlots: [String?] = {
        // Seed from the persisted global party, padded to the fixed slot count.
        var slots = BattleRules.activePartyIDs.map { Optional($0) }
        while slots.count < BattleRules.partySize { slots.append(nil) }
        return slots
    }()
    @State private var selectedHeroID: String?
    @State private var infoHero: Hero?
    @State private var characterProgress: [String: CharacterProgress] = [:]
    @State private var collectionShareImage: Image?
    @ObservedObject private var captures = CaptureStore.shared
    @ObservedObject private var roster = RosterStore.shared
    @ObservedObject private var party = PartyStore.shared
    @ObservedObject private var trust = TrustStore.shared
    private let maxPartySize = BattleRules.partySize

    /// Gold cost to level a hero, rising with its current level.
    private func goldCost(for hero: Hero) -> Int { 150 + hero.level * 30 }
    /// Biomass (farmed material) cost — rises with level so you must farm bosses.
    private func bioCost(for hero: Hero) -> Int { 5 + hero.level / 2 }
    private func canUpgrade(_ hero: Hero) -> Bool {
        gold >= goldCost(for: hero) && biomass >= bioCost(for: hero)
    }

    private var heroes: [Hero] {
        (roster.ownedHeroes + captures.capturedHeroes).map { hero in
            if let progress = characterProgress[hero.id] {
                return hero.applying(progress)
            }
            return hero
        }
    }

    private var allBiobuds: [Hero] {
        (DataSet.heroes + DataSet.capturables).map { hero in
            if let progress = characterProgress[hero.id] {
                return hero.applying(progress)
            }
            return hero
        }
    }

    private var ownedIDs: Set<String> {
        roster.owned.union(captures.owned)
    }

    private var collectedCount: Int {
        allBiobuds.filter { ownedIDs.contains($0.id) }.count
    }

    private var collectionShareSignature: String {
        ownedIDs.sorted().joined(separator: ",") + "|" + activePartyIDs.joined(separator: ",")
    }

    private var activePartyIDs: [String] {
        activePartySlots.compactMap { $0 }
    }

    private var partyHeroes: [Hero] {
        activePartyIDs.compactMap { id in
            hero(for: id)
        }
    }

    private var partyHP: Int {
        partyHeroes.reduce(0) { $0 + $1.hp }
    }

    private var partyAttack: Int {
        partyHeroes.reduce(0) { $0 + $1.attack }
    }

    private var partyDefense: Int {
        partyHeroes.reduce(0) { $0 + $1.defense }
    }

    private func hero(for id: String) -> Hero? {
        heroes.first { $0.id == id }
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "263544"), location: 0),
                        .init(color: Color(hex: "9ED1EE"), location: 0.34),
                        .init(color: Color(hex: "70BF4F"), location: 0.48),
                        .init(color: Color(hex: "2A6428"), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 7) {
                        HStack {
                            StatBlock(label: "HP", value: "\(partyHP)", color: Color(hex: "3F8A3D"))
                            Spacer()
                            StatBlock(label: "ATK", value: "\(partyAttack)", color: Color(hex: "D4873A"))
                            Spacer()
                            StatBlock(label: "DEF", value: "\(partyDefense)", color: Color(hex: "4277D9"))
                        }
                        .padding(.horizontal, 34)
                        .padding(.vertical, 7)
                        .background(Color(hex: "EAD4A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        .padding(.horizontal, 12)
                        .padding(.top, 6)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3), alignment: .center, spacing: 8) {
                            ForEach(0..<maxPartySize, id: \.self) { slotIndex in
                                if
                                    slotIndex < activePartySlots.count,
                                    let heroID = activePartySlots[slotIndex],
                                    let hero = hero(for: heroID)
                                {
                                    let isSelected = selectedHeroID == hero.id

                                    Button {
                                        selectedHeroID = isSelected ? nil : hero.id
                                    } label: {
                                        TeamRosterCard(
                                            hero: hero,
                                            isInParty: true,
                                            isSelected: isSelected,
                                            compact: false
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(hero.name), active party slot \(slotIndex + 1)")
                                    .accessibilityIdentifier("team-character-\(hero.id)")
                                    .anchorPreference(key: TeamCardBoundsKey.self, value: .bounds) { [hero.id: $0] }
                                    .zIndex(isSelected ? 10 : 0)
                                } else {
                                    EmptyTeamSlot(slotNumber: slotIndex + 1)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel("Empty party slot \(slotIndex + 1)")
                                        .accessibilityIdentifier("team-empty-slot-\(slotIndex + 1)")
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 0)

                        biodex
                            .padding(.bottom, 104)
                    }
                    .overlayPreferenceValue(TeamCardBoundsKey.self) { anchors in
                        GeometryReader { overlayProxy in
                            if
                                let selectedHeroID,
                                infoHero == nil,
                                let selectedHero = hero(for: selectedHeroID),
                                let selectedAnchor = anchors[selectedHeroID]
                            {
                                let rect = overlayProxy[selectedAnchor]
                                // Only flip the popup above the card when there
                                // genuinely isn't room below it (~70pt needed),
                                // so reserves show their actions below like the
                                // party row does.
                                let showActionsAbove = rect.maxY > overlayProxy.size.height - 72
                                InlineCharacterActions(
                                    inParty: activePartySlots.contains { $0 == selectedHeroID },
                                    canAdd: activePartyIDs.count < maxPartySize,
                                    locked: !trust.isMaxed(selectedHero),
                                    pointerOnTop: !showActionsAbove,
                                    onInfo: { infoHero = selectedHero },
                                    onToggleParty: { togglePartyMembership(for: selectedHero) }
                                )
                                .frame(width: 124)
                                .position(x: rect.midX, y: showActionsAbove ? rect.minY - 36 : rect.maxY + 36)
                                .zIndex(100)
                            }
                        }
                    }
                }

                if let infoHero {
                    Color.black.opacity(0.62)
                        .ignoresSafeArea()
                        .onTapGesture {
                            self.infoHero = nil
                            selectedHeroID = nil
                        }

                    CharacterInfoModal(
                        hero: infoHero,
                        inParty: activePartySlots.contains { $0 == infoHero.id },
                        goldCost: goldCost(for: infoHero),
                        bioCost: bioCost(for: infoHero),
                        ownedBio: biomass,
                        canUpgrade: canUpgrade(infoHero),
                        canAddToParty: activePartyIDs.count < maxPartySize,
                        onClose: {
                            self.infoHero = nil
                            selectedHeroID = nil
                        },
                        onUpgrade: {
                            upgrade(hero: infoHero)
                        },
                        onToggleParty: {
                            togglePartyMembership(for: infoHero)
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 88)
                    .zIndex(20)
                }
            }
            .animation(.spring(response: 0.24, dampingFraction: 0.86), value: selectedHeroID)
            .task {
                await loadCharacterProgress()
            }
            .task(id: collectionShareSignature) {
                collectionShareImage = BiodexShareCard.render(
                    heroes: allBiobuds.filter { ownedIDs.contains($0.id) },
                    party: partyHeroes,
                    collected: collectedCount,
                    total: allBiobuds.count
                )
            }
            .onChange(of: selectedTab) { _, tab in
                // Close the character popup/info when leaving the Team tab.
                if tab != .team {
                    selectedHeroID = nil
                    infoHero = nil
                }
            }
        }
    }

    private var biodex: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("BIODEX"))
                        .pixelText(size: 16, color: Color(hex: "F4E6C0"))
                    Text("\(collectedCount) / \(allBiobuds.count) \(L("COLLECTED"))")
                        .pixelText(size: 9, color: Color(hex: "FFD24D"))
                }
                Spacer()
                if let collectionShareImage {
                    ShareLink(
                        item: collectionShareImage,
                        preview: SharePreview("My Mito BioBud collection", image: collectionShareImage)
                    ) {
                        Text(L("SHARE"))
                            .pixelText(size: 9, color: Color(hex: "18100A"))
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(Color(hex: "FFD24D"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4),
                spacing: 7
            ) {
                ForEach(allBiobuds) { hero in
                    let owned = ownedIDs.contains(hero.id)
                    Button {
                        guard owned else {
                            Haptics.warning()
                            return
                        }
                        selectedHeroID = nil
                        infoHero = hero
                    } label: {
                        BiodexCell(hero: hero, owned: owned, inParty: activePartyIDs.contains(hero.id))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel(owned ? "\(hero.name), collected" : "Locked BioBud")
                }
            }

            if collectedCount < allBiobuds.count {
                Text(L("NEXT DISCOVERY: Keep reviewing and clearing Campaign stages."))
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "E9D8B6"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(11)
        .background(Color(hex: "1A1009").opacity(0.88))
        .overlay(Rectangle().stroke(Color(hex: "FFD24D"), lineWidth: 3))
        .padding(.horizontal, 12)
    }

    private func togglePartyMembership(for hero: Hero) {
        if let index = activePartySlots.firstIndex(where: { $0 == hero.id }) {
            activePartySlots[index] = nil
        } else if trust.isMaxed(hero), let emptyIndex = activePartySlots.firstIndex(where: { $0 == nil }) {
            // Only fully-trusted reserves can take a slot.
            activePartySlots[emptyIndex] = hero.id
        } else {
            Haptics.warning()
            return
        }
        selectedHeroID = nil
        // Persist globally so study + battle + meadow immediately reflect it.
        party.setParty(activePartySlots.compactMap { $0 })
    }

    private func loadCharacterProgress() async {
        guard characterProgress.isEmpty else { return }
        do {
            let records = try await MitoBackend.shared.fetchCharacterProgress()
            characterProgress = Dictionary(
                records.map { ($0.characterID, CharacterProgress(record: $0)) },
                uniquingKeysWith: { _, new in new }
            )
        } catch {
            // The local base roster still works when offline or before the
            // character_progress migration has been applied.
        }
    }

    private func upgrade(hero: Hero) {
        guard canUpgrade(hero) else { return }
        gold -= goldCost(for: hero)
        biomass -= bioCost(for: hero)

        var progress = characterProgress[hero.id] ?? CharacterProgress(hero: hero)
        progress.levelUp()
        characterProgress[hero.id] = progress

        if infoHero?.id == hero.id, let baseHero = DataSet.heroes.first(where: { $0.id == hero.id }) {
            infoHero = baseHero.applying(progress)
        }

        Task {
            try? await MitoBackend.shared.upsertCharacterProgress(
                characterID: hero.id,
                level: progress.level,
                hp: progress.hp,
                attack: progress.attack,
                defense: progress.defense
            )
        }
    }
}

private struct BiodexCell: View {
    let hero: Hero
    let owned: Bool
    var inParty: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: owned
                        ? [hero.rarity.color.opacity(0.46), Color(hex: "2A1B0E")]
                        : [Color(hex: "302B27"), Color(hex: "120E0B")],
                    startPoint: .top,
                    endPoint: .bottom
                )

                SpriteView(asset: hero.asset, size: 57, frame: 0)
                    .colorMultiply(owned ? .white : .black)
                    .opacity(owned ? 1 : 0.62)

                if !owned {
                    Text("?")
                        .pixelText(size: 24, color: Color(hex: "F4E6C0").opacity(0.86))
                }

                if inParty {
                    Text(L("IN PARTY"))
                        .pixelText(size: 6, color: Color(hex: "18100A"))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(hex: "6FD16B"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 68)

            VStack(spacing: 2) {
                Text(owned ? L(hero.name).uppercased() : "???")
                    .pixelText(size: 7, color: owned ? Color(hex: "3A2A18") : Color(hex: "8A6B42"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(owned ? hero.rarity.label : L("LOCKED"))
                    .pixelText(size: 6, color: owned ? hero.rarity.color : Color(hex: "8A6B42"))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .padding(.vertical, 5)
            .background(owned ? Color(hex: "EAD4A4") : Color(hex: "B5A487"))
        }
        .overlay(Rectangle().stroke(inParty ? Color(hex: "6FD16B") : (owned ? hero.rarity.color : Color(hex: "40372F")), lineWidth: 3))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 1).padding(3))
    }
}

private struct BiodexShareCard: View {
    let heroes: [Hero]
    let party: [Hero]
    let collected: Int
    let total: Int

    private var featured: [Hero] {
        let partyIDs = Set(party.map(\.id))
        return Array((party + heroes.filter { !partyIDs.contains($0.id) }).prefix(6))
    }

    var body: some View {
        ZStack {
            Image("team-bg")
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .frame(width: 300, height: 533)
                .clipped()
            Color(hex: "1A1009").opacity(0.64)

            VStack(spacing: 16) {
                Text("MITO")
                    .pixelText(size: 23, color: Color(hex: "FFD24D"))
                    .padding(.top, 30)
                Text(L("MY BIOBUD SQUAD"))
                    .pixelText(size: 16, color: Color(hex: "F4E6C0"))

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(featured) { hero in
                        VStack(spacing: 3) {
                            ZStack {
                                hero.rarity.color.opacity(0.25)
                                SpriteView(asset: hero.asset, size: 67, frame: 0)
                            }
                            .frame(height: 78)
                            .overlay(Rectangle().stroke(hero.rarity.color, lineWidth: 3))
                            Text(L(hero.name).uppercased())
                                .pixelText(size: 7, color: Color(hex: "F4E6C0"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                }
                .padding(.horizontal, 22)

                VStack(spacing: 6) {
                    Text("\(collected) / \(total)")
                        .pixelText(size: 30, color: Color(hex: "FFD24D"))
                    Text(L("BIOBUDS COLLECTED"))
                        .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(hex: "1A1009").opacity(0.88))
                .overlay(Rectangle().stroke(Color(hex: "FFD24D"), lineWidth: 3))

                Spacer()
                Text(L("STUDY · BATTLE · COLLECT"))
                    .pixelText(size: 9, color: Color(hex: "9CD67D"))
                    .padding(.bottom, 26)
            }
        }
        .frame(width: 300, height: 533)
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 6))
    }

    @MainActor
    static func render(
        heroes: [Hero],
        party: [Hero],
        collected: Int,
        total: Int
    ) -> Image? {
        let renderer = ImageRenderer(content: BiodexShareCard(
            heroes: heroes,
            party: party,
            collected: collected,
            total: total
        ))
        renderer.scale = 3
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

struct StatBlock: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.custom(MitoFont.regular, size: 12))
                .foregroundStyle(Color(hex: "8A6B42"))
            Text(value)
                .pixelText(size: 23, color: color)
        }
    }
}

struct TeamRosterCard: View {
    let hero: Hero
    let isInParty: Bool
    var isSelected = false
    var compact = false
    @ObservedObject private var trust = TrustStore.shared

    /// In-party members are trusted by definition; reserves must earn it.
    private var maxed: Bool { isInParty || trust.isMaxed(hero) }

    private var spriteSize: CGFloat {
        compact ? 46 : 70
    }

    private var imageHeight: CGFloat {
        compact ? 66 : 92
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [hero.color.opacity(0.42), Color(hex: "F4E6C0").opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(isInParty ? "IN" : (maxed ? "ADD" : "🔒"))
                            .pixelText(size: 7, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(isInParty ? Color(hex: "6B4324") : (maxed ? Color(hex: "4A8A3C") : Color(hex: "B0492F")))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))

                        Spacer(minLength: 0)

                        Text("LV \(hero.level)")
                            .pixelText(size: 7, color: Color(hex: "18100A"))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .background(Color(hex: "F7C943"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .padding(4)

                    Spacer(minLength: 0)
                    SpriteView(asset: hero.asset, size: spriteSize)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(height: imageHeight)

            VStack(spacing: 3) {
                Text(L(hero.name))
                    .pixelText(size: compact ? 8 : 10, color: Color(hex: "3A2A18"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(L(hero.role))
                    .font(.custom(MitoFont.regular, size: compact ? 10 : 12))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .lineLimit(1)
                if !maxed {
                    ProgressBar(progress: trust.fraction(hero), color: Color(hex: "4A8A3C"))
                        .frame(height: 5)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, compact ? 7 : 8)
            .background(Color(hex: "EAD4A4"))
        }
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .overlay {
            if isSelected {
                Rectangle()
                    .stroke(Color(hex: "FFD24D"), lineWidth: 3)
                Rectangle()
                    .stroke(Color(hex: "2D9CFF"), lineWidth: 2)
                    .padding(3)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyTeamSlot: View {
    let slotNumber: Int

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "6B4324").opacity(0.64), Color(hex: "2A1A0D").opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 8) {
                    Rectangle()
                        .stroke(
                            Color(hex: "EAD4A4").opacity(0.5),
                            style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                        )
                        .frame(width: 54, height: 42)
                        .overlay {
                            Text("+")
                                .pixelText(size: 18, color: Color(hex: "EAD4A4").opacity(0.68))
                        }

                    Text("SLOT \(slotNumber)")
                        .pixelText(size: 8, color: Color(hex: "B89868"))
                }
            }
            .frame(height: 92)

            VStack(spacing: 3) {
                Text("EMPTY")
                    .pixelText(size: 10, color: Color(hex: "8A6B42"))
                Text("Party slot")
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background(Color(hex: "D8BD82"))
        }
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .overlay(Rectangle().stroke(Color(hex: "6B4324"), lineWidth: 2).padding(4))
        .frame(maxWidth: .infinity)
    }
}

struct TeamCardBoundsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct InlineCharacterActions: View {
    let inParty: Bool
    let canAdd: Bool
    var locked = false        // reserve isn't trusted yet → can't be fielded
    var pointerOnTop = true
    let onInfo: () -> Void
    let onToggleParty: () -> Void

    private var toggleTitle: String {
        if inParty { return "REMOVE" }
        if locked { return L("LOCKED") }
        return canAdd ? "ADD" : "FULL"
    }

    private var toggleColor: Color {
        if inParty { return Color(hex: "D84A3A") }
        if locked { return Color(hex: "B0492F") }
        return canAdd ? Color(hex: "4A8A3C") : Color(hex: "8A6B42")
    }

    var body: some View {
        VStack(spacing: 0) {
            if pointerOnTop {
                Triangle()
                    .fill(Color(hex: "6B4324"))
                    .frame(width: 12, height: 8)
            }

            VStack(spacing: 0) {
                Button(action: onInfo) {
                    Text("INFO")
                        .pixelText(size: 8, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 27)
                        .background(Color(hex: "6B4324"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("team-action-info")

                Rectangle()
                    .fill(Color(hex: "18100A"))
                    .frame(height: 3)

                Button(action: onToggleParty) {
                    Text(toggleTitle)
                        .pixelText(size: 8, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 29)
                        .background(toggleColor)
                }
                .buttonStyle(.plain)
                .disabled(!inParty && (locked || !canAdd))
                .accessibilityIdentifier(inParty ? "team-action-remove" : "team-action-add")
            }
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

            if !pointerOnTop {
                Triangle()
                    .fill(toggleColor)
                    .frame(width: 12, height: 8)
                    .rotationEffect(.degrees(180))
            }
        }
    }
}
