//  BattleSetupViews.swift
//  Extracted from BattleView.swift (behavior-preserving refactor).

import SwiftUI

struct CampaignStageSetup: View {
    let stage: Stage
    let decks: [Deck]
    @Binding var selectedDecks: Set<String>
    @Binding var selectedTags: Set<String>
    @Binding var answerMode: AnswerMode
    let onBack: () -> Void
    let onStart: () -> Void

    private var selectedCount: Int {
        decks.filter { selectedDecks.contains($0.id) }.reduce(0) { $0 + $1.cards }
    }

    private var availableTags: [String] {
        var seen = Set<String>()
        var tags: [String] = []
        for deck in decks where selectedDecks.contains(deck.id) {
            for tag in deck.tags where !seen.contains(tag) {
                seen.insert(tag)
                tags.append(tag)
            }
        }
        return tags
    }

    private var canStart: Bool {
        !selectedDecks.isEmpty
    }

    var body: some View {
        ZStack {
            WoodBackground()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button(action: onBack) {
                        Text("< BACK")
                            .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    Text("STAGE \(stage.id) · \(stage.difficulty)")
                        .pixelText(size: 16, color: Color(hex: "FFD24D"))
                    Spacer()
                }

                HStack(spacing: 10) {
                    SpriteView(asset: "wild-spikevyrus-hop", size: 58)
                        .background(Color(hex: "F4E6C0"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stage.name.uppercased())
                            .pixelText(size: 13, color: Color(hex: "3A2A18"))
                        Text("Spikevyrus · \(stage.difficulty == "BOSS" ? "boss fight" : "3 waves")")
                            .font(.custom(MitoFont.regular, size: 15))
                            .foregroundStyle(Color(hex: "6B4324"))
                    }
                    Spacer()
                    Text(stage.difficulty)
                        .pixelText(size: 8, color: .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(hex: "4D6BA5"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .padding(8)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                HStack {
                    Text("PICK YOUR DECKS")
                        .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                    Spacer()
                    Button {
                        let all = Set(decks.map(\.id))
                        selectedDecks = all.isSubset(of: selectedDecks) ? [] : all
                    } label: {
                        Text("SELECT ALL")
                            .pixelText(size: 10, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(hex: "EAD4A4"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }

                // Decks scroll only within this region; the page never shifts.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(decks) { deck in
                            EndlessDeckRow(deck: deck, isSelected: selectedDecks.contains(deck.id), highlightSelected: true) {
                                toggleDeck(deck)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)

                TagFilterSection(availableTags: availableTags, selectedTags: $selectedTags)

                AnswerModePicker(answerMode: $answerMode)

                HStack {
                    Text("\(selectedDecks.count) \(selectedDecks.count == 1 ? "deck" : "decks") · \(selectedCount) cards")
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "3A2A18"))
                    Spacer()
                    Text("FREE ENTRY")
                        .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "4A8A3C"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                Button(action: {
                    if canStart {
                        onStart()
                    }
                }) {
                    Text(canStart ? "⚔ ENTER DUNGEON" : "PICK A DECK")
                        .pixelText(size: 18, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(canStart ? Color(hex: "D84A3A") : Color(hex: "6B4324"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.62)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func toggleDeck(_ deck: Deck) {
        if selectedDecks.contains(deck.id) {
            selectedDecks.remove(deck.id)
        } else {
            selectedDecks.insert(deck.id)
        }
        selectedTags.formIntersection(Set(availableTags))
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

struct EndlessReviewSetup: View {
    let decks: [Deck]
    @Binding var selectedDecks: Set<String>
    @Binding var selectedTags: Set<String>
    @Binding var answerMode: AnswerMode
    let onBack: () -> Void
    let onStart: () -> Void

    private var selectedCount: Int {
        decks.filter { selectedDecks.contains($0.id) }.reduce(0) { $0 + $1.cards }
    }

    private var availableTags: [String] {
        var seen = Set<String>()
        var tags: [String] = []
        for deck in decks where selectedDecks.contains(deck.id) {
            for tag in deck.tags where !seen.contains(tag) {
                seen.insert(tag)
                tags.append(tag)
            }
        }
        return tags
    }

    var body: some View {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button(action: onBack) {
                        Text("< BACK")
                            .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    Text("ENDLESS REVIEW")
                        .pixelText(size: 17, color: Color(hex: "FFD24D"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }

                HStack {
                    Text("PICK YOUR DECKS")
                        .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                    Spacer()
                    Button {
                        let all = Set(decks.map(\.id))
                        selectedDecks = all.isSubset(of: selectedDecks) ? [] : all
                    } label: {
                        Text("SELECT ALL")
                            .pixelText(size: 10, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(hex: "EAD4A4"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }

                // Decks scroll only within this region; the page never shifts.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(decks) { deck in
                            EndlessDeckRow(deck: deck, isSelected: selectedDecks.contains(deck.id)) {
                                toggleDeck(deck)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
                .tutorialAnchor("battle.pickDeck")

                TagFilterSection(availableTags: availableTags, selectedTags: $selectedTags)

                AnswerModePicker(answerMode: $answerMode)

                HStack {
                    Text("\(selectedDecks.count) decks · \(selectedCount) cards")
                        .font(.custom(MitoFont.regular, size: 16))
                        .foregroundStyle(Color(hex: "3A2A18"))
                    Spacer()
                    Text("FREE · NO LIMITS")
                        .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color(hex: "4A8A3C"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                Button(action: onStart) {
                    HStack(spacing: 12) {
                        Text("▣")
                            .pixelText(size: 15, color: selectedDecks.isEmpty ? Color(hex: "D8CBA6") : Color(hex: "F4E6C0"))
                        Text(selectedDecks.isEmpty ? "PICK AT LEAST ONE DECK" : "START ENDLESS REVIEW")
                            .pixelText(size: 15, color: selectedDecks.isEmpty ? Color(hex: "D8CBA6") : Color(hex: "F4E6C0"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedDecks.isEmpty ? Color(hex: "47505A").opacity(0.78) : Color(hex: "4A8A3C"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(selectedDecks.isEmpty)
                .tutorialAnchor("battle.startEndless")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                ZStack {
                    Image("map-bg")
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                    Color(hex: "123D2F").opacity(0.66)
                    LinearGradient(colors: [.clear, Color.black.opacity(0.30)], startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea()
            }
    }

    private func toggleDeck(_ deck: Deck) {
        if selectedDecks.contains(deck.id) {
            selectedDecks.remove(deck.id)
        } else {
            selectedDecks.insert(deck.id)
        }
        selectedTags.formIntersection(Set(availableTags))
        // Advance the tutorial's "pick a deck" beat once the player has a deck selected.
        if !selectedDecks.isEmpty { TutorialManager.shared.complete("battle.pickDeck") }
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

/// Shared, self-contained tag filter for the battle setup screens: a tidy
/// bordered panel whose chips wrap (FlowLayout) and scroll independently when
/// there are many tags, so it never bloats or leaves dead space.
/// Lets the player choose how they answer cards this session: classic
/// self-grade, multiple-choice, or type-in.
struct AnswerModePicker: View {
    @Binding var answerMode: AnswerMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANSWER MODE")
                .pixelText(size: 10, color: Color(hex: "F4E6C0"))
            HStack(spacing: 6) {
                ForEach(AnswerMode.selectable, id: \.self) { mode in
                    let on = mode == answerMode
                    Button {
                        answerMode = mode
                        Haptics.tap()
                    } label: {
                        Text(mode.shortTitle)
                            .pixelText(size: 10, color: on ? Color(hex: "1A130A") : Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(on ? Color(hex: "FFD24D") : Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct TagFilterSection: View {
    let availableTags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("FILTER BY TAG")
                    .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                Text("· OPTIONAL")
                    .pixelText(size: 7, color: Color(hex: "F4E6C0").opacity(0.55))
                Spacer(minLength: 0)
                if !selectedTags.isEmpty {
                    Button { selectedTags.removeAll() } label: {
                        Text("CLEAR")
                            .pixelText(size: 8, color: Color(hex: "3A2A18"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(hex: "EAD4A4"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }

            if availableTags.isEmpty {
                Text("Select a deck to reveal its tags.")
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(Color(hex: "F4E6C0").opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView(showsIndicators: false) {
                    FlowLayout(spacing: 7) {
                        ForEach(availableTags, id: \.self) { tag in
                            Button { toggle(tag) } label: {
                                SmallTag(tag.uppercased(), active: selectedTags.contains(tag))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 56)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.30))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }

    private func toggle(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

struct EndlessDeckRow: View {
    let deck: Deck
    let isSelected: Bool
    var highlightSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle()
                        .fill(isSelected ? Color(hex: "4A8A3C") : Color.white)
                    if isSelected {
                        Text("✓")
                            .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                    }
                }
                .frame(width: 24, height: 24)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                VStack(alignment: .leading, spacing: 5) {
                    Text(deck.name)
                        .pixelText(size: 13, color: Color(hex: "3A2A18"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        ForEach(deck.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .pixelText(size: 7, color: Color(hex: "3A2A18"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "F4E6C0"))
                        }
                        if deck.id == "bio" || deck.id == "orgo" {
                            Text("+1")
                                .font(.custom(MitoFont.regular, size: 12))
                                .foregroundStyle(Color(hex: "6B4324"))
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(deck.cards)")
                        .pixelText(size: 17, color: Color(hex: "3A2A18"))
                    Text("cards")
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "5B442A"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 72)
            .background(isSelected && highlightSelected ? Color(hex: "F4E6C0") : Color(hex: "B99868"))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(deck.color)
                    .frame(width: 8)
            }
            .overlay(Rectangle().stroke(isSelected && highlightSelected ? Color(hex: "FFD24D") : Color(hex: "18100A"), lineWidth: isSelected && highlightSelected ? 4 : 3))
        }
        .buttonStyle(.plain)
    }
}
