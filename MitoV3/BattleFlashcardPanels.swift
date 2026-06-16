//  BattleFlashcardPanels.swift
//  Extracted from BattleView.swift (behavior-preserving refactor).

import SwiftUI

struct BattleStatusChip: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .pixelText(size: 9, color: Color(hex: "F4E6C0"))
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(Color(hex: "182116").opacity(0.86))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

struct BattleFlashcardPanel: View {
    let mode: BattleMode
    let currentCard: Int
    let showingAnswer: Bool
    let questionText: String
    let answerText: String
    let cardTag: String
    var allowManualReveal: Bool = true
    let onReveal: () -> Void

    private var label: String {
        showingAnswer ? "ANSWER" : "QUESTION"
    }

    private var tag: String { cardTag }

    private var text: String {
        showingAnswer ? answerText : questionText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BattlePanelTag(label)
                Spacer()
                BattlePanelTag(tag)
            }

            Text(text)
                // The card's own question/answer uses a clean system font (the
                // pixel font is hard to read for dense study content).
                .font(.system(size: showingAnswer ? 19 : 20, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: "3A2A18"))
                .multilineTextAlignment(.leading)
                .lineSpacing(5)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 4)

            if !showingAnswer && allowManualReveal {
                Button(action: onReveal) {
                    Text("SHOW ANSWER")
                        .pixelText(size: 16, color: Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 39)
                        .background(Color(hex: "6B4324"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .tutorialAnchor("battle.showAnswer")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 224)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color(hex: "B89868"))
                .frame(width: 11, height: 11)
                .padding(9)
        }
    }
}

struct BattlePanelTag: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .pixelText(size: 8, color: Color(hex: "F4E6C0"))
            .padding(.horizontal, 8)
            .frame(height: 21)
            .background(Color(hex: "8A6B42"))
            .overlay(Rectangle().stroke(Color(hex: "F4E6C0"), lineWidth: 1))
    }
}

struct BattleGradeButton: View {
    let rating: BattleRating
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(rating.title)
                .pixelText(size: 17, color: Color(hex: "F4E6C0"))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(rating.color)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 0, x: 2, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Multiple-choice answer panel

/// Multiple-choice answering: tap an option, see correct/wrong, and a grade is
/// derived from correctness + speed (no AI needed at review time). Re-created per
/// card via `.id(cardID)`, so its timer and selection reset each card.
struct MultipleChoicePanel: View {
    let options: [String]
    let correctAnswer: String
    let onReveal: () -> Void
    let onResolved: (BattleRating) -> Void

    @State private var start = Date()
    @State private var selected: String?
    @State private var resolved = false

    private func isCorrect(_ option: String) -> Bool {
        AnswerGrading.normalize(option) == AnswerGrading.normalize(correctAnswer)
    }

    private func background(for option: String) -> Color {
        guard resolved else { return Color(hex: "6B4324") }
        if isCorrect(option) { return Color(hex: "4A9B3F") }            // always reveal the right one
        if option == selected { return Color(hex: "C84535") }           // your wrong pick
        return Color(hex: "6B4324").opacity(0.5)
    }

    private func tap(_ option: String) {
        guard !resolved else { return }
        selected = option
        resolved = true
        let correct = isCorrect(option)
        onReveal()
        AudioManager.shared.play(correct ? .gradeGood : .gradeAgain)
        Haptics.select()
        let rating = BattleRating(AnswerGrading.multipleChoiceRating(
            correct: correct, elapsed: Date().timeIntervalSince(start)))
        // Hold the correct/wrong reveal briefly before handing off to the ability row.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { onResolved(rating) }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button { tap(option) } label: {
                    Text(option)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "F4E6C0"))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 8)
                        .background(background(for: option))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(resolved)
            }
        }
    }
}

// MARK: - Type-in answer panel

/// Type-in answering: the player types a free answer; the AI grader (with a
/// local-similarity fallback) turns it into a battle grade. Tracks timing and
/// hesitation signals to feed the grader. Re-created per card via `.id(cardID)`.
struct TypeInPanel: View {
    let correctAnswer: String
    let onReveal: () -> Void
    let grade: (String, TypingSignals) async -> (BattleRating, String?)
    let onResolved: (BattleRating) -> Void

    @State private var text = ""
    @State private var start = Date()
    @State private var firstKeystroke: Date?
    @State private var deletions = 0
    @State private var keystrokes = 0
    @State private var lastLength = 0
    @State private var grading = false
    @State private var feedback: String?
    @FocusState private var focused: Bool

    private func track(_ newValue: String) {
        if firstKeystroke == nil && !newValue.isEmpty { firstKeystroke = Date() }
        let delta = newValue.count - lastLength
        if delta > 0 { keystrokes += delta } else if delta < 0 { deletions += -delta }
        lastLength = newValue.count
    }

    private func submit() {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, !grading else { return }
        grading = true
        focused = false
        onReveal()
        let now = Date()
        let signals = TypingSignals(
            elapsedMs: Int(now.timeIntervalSince(start) * 1000),
            timeToFirstKeystrokeMs: Int((firstKeystroke ?? now).timeIntervalSince(start) * 1000),
            deletions: deletions,
            keystrokes: keystrokes)
        Task {
            let (rating, fb) = await grade(answer, signals)
            await MainActor.run {
                feedback = fb
                grading = false
                AudioManager.shared.play(rating.gradeSound)
                Haptics.select()
            }
            // Let the player read the AI feedback before the ability row takes over.
            try? await Task.sleep(nanoseconds: fb == nil ? 600_000_000 : 1_400_000_000)
            await MainActor.run { onResolved(rating) }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let feedback {
                Text(feedback)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: "F4E6C0"))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(hex: "2A1A0D").opacity(0.85))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }

            TextField("", text: $text, prompt: Text("Type your answer…").foregroundColor(Color(hex: "8A6B42")))
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Color(hex: "3A2A18"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .disabled(grading)
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                .onChange(of: text) { _, newValue in track(newValue) }
                .onSubmit(submit)

            Button(action: submit) {
                Text(grading ? "CHECKING…" : "SUBMIT")
                    .pixelText(size: 16, color: Color(hex: "F4E6C0"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(hex: "4A9B3F"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
            .disabled(grading || text.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(grading || text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
        }
        .onAppear { focused = true }
    }
}
