//  FlashcardEditor.swift
//  Flashcard editor screen + flip editor + side tabs/pages.
//  Extracted from FlashcardsView.swift (behavior-preserving refactor).

import SwiftUI

struct FlashcardEditorScreen: View {
    let deckName: String
    let existingCard: Flashcard?
    let onBack: () -> Void
    let onSave: (String, String, [String]) -> Void
    let onDelete: (() -> Void)?
    @State private var front: String
    @State private var back: String
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var confirmingDelete = false
    @State private var activeSide: FlashcardSide = .front

    init(
        deckName: String,
        existingCard: Flashcard?,
        onBack: @escaping () -> Void,
        onSave: @escaping (String, String, [String]) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.deckName = deckName
        self.existingCard = existingCard
        self.onBack = onBack
        self.onSave = onSave
        self.onDelete = onDelete
        _front = State(initialValue: existingCard?.front ?? "")
        _back = State(initialValue: existingCard?.back ?? "")
        // Don't surface the placeholder "new" tag in the editor.
        _tags = State(initialValue: (existingCard?.tags ?? []).filter { $0 != "new" })
    }

    private var canSave: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty, !tags.contains(t) else { newTag = ""; return }
        tags.append(t)
        newTag = ""
    }

    var body: some View {
        ZStack {
            DottedDarkBackground()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: onBack) {
                        Text("< BACK")
                            .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(deckName)
                            .pixelText(size: 17, color: Color(hex: "F4E6C0"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(existingCard == nil ? "NEW FLASHCARD" : "EDIT FLASHCARD")
                            .font(.custom(MitoFont.regular, size: 13))
                            .foregroundStyle(Color(hex: "B89868"))
                    }
                    Spacer()
                    Button {
                        onSave(front, back, tags)
                    } label: {
                        Text(existingCard == nil ? "CREATE" : "SAVE")
                            .pixelText(size: 11, color: canSave ? Color(hex: "F4E6C0") : Color(hex: "3A2A18"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(canSave ? Color(hex: "4A8A3C") : Color(hex: "B89868"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }

                VStack(alignment: .leading, spacing: 12) {
                    FlashcardSideTabs(activeSide: $activeSide)
                    FlippingFlashcardEditor(activeSide: activeSide, front: $front, back: $back)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: activeSide)

                    tagEditor
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                if onDelete != nil {
                    Button {
                        confirmingDelete = true
                    } label: {
                        Text("DELETE CARD")
                            .pixelText(size: 12, color: .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color(hex: "C4452F"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Delete this flashcard?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) { onDelete?() }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .padding(18)
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
                        Text("TAGS")
                            .pixelText(size: 9, color: Color(hex: "6B4324"))
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Button {
                                    tags.removeAll { $0 == tag }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(tag.uppercased())
                                            .pixelText(size: 8, color: .white)
                                        Text("×")
                                            .font(.custom(MitoFont.regular, size: 14))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "6B9C4A"))
                                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("add a tag", text: $newTag)
                                .font(.custom(MitoFont.regular, size: 15))
                                .foregroundStyle(Color(hex: "3A2A18"))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit(addTag)
                                .padding(8)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                            Button(action: addTag) {
                                Text("+ ADD")
                                    .pixelText(size: 9, color: Color(hex: "3A2A18"))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(Color(hex: "F7C943"))
                                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
        }
        .padding(10)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "B89868"), lineWidth: 2))
    }
}

enum FlashcardSide {
    case front
    case back

    var title: String {
        switch self {
        case .front: "FRONT"
        case .back: "BACK"
        }
    }

    var placeholder: String {
        switch self {
        case .front: "Write the question or prompt..."
        case .back: "Write the answer..."
        }
    }
}

struct FlashcardSideTabs: View {
    @Binding var activeSide: FlashcardSide

    var body: some View {
        HStack(spacing: 10) {
            FlashcardSideTab(side: .front, activeSide: $activeSide)
            Spacer(minLength: 0)
            FlashcardSideTab(side: .back, activeSide: $activeSide)
        }
    }
}

struct FlashcardSideTab: View {
    let side: FlashcardSide
    @Binding var activeSide: FlashcardSide

    private var isActive: Bool {
        activeSide == side
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                activeSide = side
            }
        } label: {
            Text(side.title)
                .pixelText(size: 13, color: isActive ? Color(hex: "F4E6C0") : Color(hex: "8A6B42"))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isActive ? Color(hex: "4A8A3C") : Color(hex: "6B4324").opacity(0.42))
                .overlay(Rectangle().stroke(isActive ? Color(hex: "18100A") : Color(hex: "8A6B42"), lineWidth: isActive ? 3 : 2))
                .opacity(isActive ? 1 : 0.72)
        }
        .buttonStyle(.plain)
    }
}

struct FlippingFlashcardEditor: View {
    let activeSide: FlashcardSide
    @Binding var front: String
    @Binding var back: String

    var body: some View {
        ZStack {
            FlashcardSidePage(side: .front, text: $front)
                .opacity(activeSide == .front ? 1 : 0)
                .animation(nil, value: activeSide)

            FlashcardSidePage(side: .back, text: $back)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(activeSide == .back ? 1 : 0)
                .animation(nil, value: activeSide)
        }
        .rotation3DEffect(.degrees(activeSide == .back ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
    }
}

struct FlashcardSidePage: View {
    let side: FlashcardSide
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(side.title)
                    .pixelText(size: 14, color: Color(hex: "3A2A18"))
                Spacer()
                Text(side == .front ? "QUESTION" : "ANSWER")
                    .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(hex: "6B4324"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.custom(MitoFont.regular, size: 23))
                    .foregroundStyle(Color(hex: "3A2A18"))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if text.isEmpty {
                    Text(side.placeholder)
                        .font(.custom(MitoFont.regular, size: 20))
                        .foregroundStyle(Color(hex: "8A6B42"))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color(hex: "B89868"))
                .frame(width: 14, height: 14)
                .padding(10)
        }
    }
}

struct SmallToggle: View {
    let title: String
    let active: Bool

    init(_ title: String, active: Bool) {
        self.title = title
        self.active = active
    }

    var body: some View {
        Text(title)
            .pixelText(size: 10, color: active ? Color(hex: "F4E6C0") : Color(hex: "3A2A18"))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(active ? Color(hex: "4A8A3C") : Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }
}

