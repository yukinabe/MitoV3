//  Onboarding.swift
//  Extracted from ContentView.swift (behavior-preserving refactor).

import SwiftUI
import Supabase

struct WaitlistGate: View {
    @ObservedObject var backend: MitoBackend
    let onAdmit: () -> Void

    @State private var email = ""
    @State private var referral = ""
    @State private var code = ""
    @State private var joined = false
    @State private var working = false
    @State private var message = ""

    private var emailValid: Bool { email.contains("@") && email.contains(".") }

    var body: some View {
        ZStack {
            Color.mitoWoodDarkest.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    SpriteView(asset: "hero-mito-hop", size: 84)
                        .padding(.top, 40)
                    Text("MITO")
                        .pixelText(size: 30, color: Color(hex: "F7C943"))
                        .shadow(color: .black, radius: 0, x: 2, y: 2)
                    Text("A study RPG · private beta")
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "EAD4A4"))

                    VStack(spacing: 10) {
                        GateField(label: "EMAIL", placeholder: "you@example.com", text: $email, email: true)
                        GateField(label: "HOW DID YOU HEAR? (optional)", placeholder: "TikTok, friend…", text: $referral)
                        GateField(label: "INVITE CODE (optional)", placeholder: "enter code to skip the line", text: $code)
                        if !message.isEmpty {
                            Text(message)
                                .font(.custom(MitoFont.regular, size: 13))
                                .foregroundStyle(Color(hex: "6B4324"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .background(Color(hex: "EAD4A4"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                    Button { Task { await enter() } } label: {
                        Text(working ? "…" : "ENTER WITH CODE")
                            .pixelText(size: 14, color: Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(canEnter ? Color(hex: "4A8A3C") : Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEnter || working)

                    Button { Task { await join() } } label: {
                        Text(joined ? "ON THE LIST ✓" : "JOIN WAITLIST")
                            .pixelText(size: 12, color: joined ? Color(hex: "9FE08C") : Color(hex: "F7C943"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(hex: "2A1B0E"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!emailValid || working || joined)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var canEnter: Bool { emailValid && !code.trimmingCharacters(in: .whitespaces).isEmpty }

    private func enter() async {
        guard canEnter else { return }
        working = true
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        await backend.submitWaitlist(email: email, referral: referral, inviteCode: trimmedCode, cohort: "invited")
        await backend.logEvent("admitted", props: ["code": trimmedCode])
        working = false
        onAdmit()
    }

    private func join() async {
        guard emailValid else { return }
        working = true
        let ok = await backend.submitWaitlist(email: email, referral: referral, inviteCode: "", cohort: "waitlist")
        await backend.logEvent("waitlist_joined")
        working = false
        joined = ok
        message = ok ? "You're on the list. We'll email your invite. Have a code? Enter it above to jump in now."
                     : "Couldn't reach the server. Check your connection and try again."
    }
}

private struct GateField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var email = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .pixelText(size: 8, color: Color(hex: "6B4324"))
            TextField(placeholder, text: $text)
                .font(.custom(MitoFont.regular, size: 16))
                .foregroundStyle(Color(hex: "3A2A18"))
                .textInputAutocapitalization(email ? .never : .sentences)
                .autocorrectionDisabled(email)
                .keyboardType(email ? .emailAddress : .default)
                .padding(9)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @ObservedObject var backend: MitoBackend
    @Binding var goal: String
    let onComplete: () -> Void

    @State private var step = 0
    @State private var creating = false
    @State private var createdDeckName: String?

    private let goals = ["Biology", "Languages", "Test Prep", "Med / Nursing", "History", "Other"]

    var body: some View {
        ZStack {
            Color.mitoWoodDarkest.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle()
                            .fill(i <= step ? Color(hex: "F7C943") : Color(hex: "6B4324"))
                            .frame(height: 5)
                    }
                }
                .padding(.top, 50)

                Spacer(minLength: 0)

                switch step {
                case 0: goalStep
                case 1: deckStep
                default: focusStep
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 30)
        }
        .task { await backend.logEvent("onboarding_started") }
    }

    private var goalStep: some View {
        VStack(spacing: 16) {
            Text(L("WHAT ARE YOU STUDYING?"))
                .pixelText(size: 18, color: Color(hex: "F4E6C0"))
                .multilineTextAlignment(.center)
            Text(L("We'll tune your starter content."))
                .font(.custom(MitoFont.regular, size: 15))
                .foregroundStyle(Color(hex: "EAD4A4"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(goals, id: \.self) { item in
                    Button {
                        goal = item
                        Task { await backend.logEvent("onboarding_goal", props: ["goal": item]) }
                        withAnimation { step = 1 }
                    } label: {
                        Text(L(item).uppercased())
                            .pixelText(size: 10, color: Color(hex: "3A2A18"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(goal == item ? Color(hex: "F7C943") : Color(hex: "EAD4A4"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var deckStep: some View {
        VStack(spacing: 14) {
            Text(L("ADD YOUR FIRST DECK"))
                .pixelText(size: 18, color: Color(hex: "F4E6C0"))
            Text(L("Pick a starter deck to study right away."))
                .font(.custom(MitoFont.regular, size: 15))
                .foregroundStyle(Color(hex: "EAD4A4"))
                .multilineTextAlignment(.center)
            ForEach(DeckTemplate.all) { template in
                Button {
                    Task { await addStarter(template) }
                } label: {
                    HStack {
                        Text(L(template.name).uppercased())
                            .pixelText(size: 12, color: Color(hex: "3A2A18"))
                        Spacer()
                        Text("\(template.cards.count) " + L("CARDS"))
                            .pixelText(size: 8, color: Color(hex: "6B4324"))
                    }
                    .padding(14)
                    .background(createdDeckName == template.name ? Color(hex: "CFE49C") : Color(hex: "EAD4A4"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .disabled(creating)
            }
            Button { withAnimation { step = 2 } } label: {
                Text(L("SKIP FOR NOW"))
                    .pixelText(size: 10, color: Color(hex: "EAD4A4"))
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var focusStep: some View {
        VStack(spacing: 16) {
            SpriteView(asset: "hero-mito-hop", size: 96)
            Text(L("YOU'RE ALL SET"))
                .pixelText(size: 20, color: Color(hex: "F7C943"))
            Text(createdDeckName == nil
                 ? L("Start a focus session to earn ATP, then review your cards in battle.")
                 : "“\(createdDeckName!)” is ready. Start a focus session to earn ATP, then review it in battle.")
                .font(.custom(MitoFont.regular, size: 16))
                .foregroundStyle(Color(hex: "EAD4A4"))
                .multilineTextAlignment(.center)
            Button {
                Task { await backend.logEvent("onboarding_completed", props: ["goal": goal]) }
                onComplete()
            } label: {
                Text(L("START STUDYING"))
                    .pixelText(size: 16, color: Color(hex: "F4E6C0"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "4A8A3C"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
        }
    }

    /// Create the chosen starter deck in the cloud + review session, then advance.
    private func addStarter(_ template: DeckTemplate) async {
        guard !creating else { return }
        creating = true
        if backend.isReady, let record = try? await backend.createDeck(named: template.name) {
            for card in template.cards {
                let tags = card.tags.isEmpty ? ["new"] : card.tags
                if let created = try? await backend.createCard(deckID: record.id, front: card.front, back: card.back, tags: tags) {
                    ReviewSession.shared.upsertContent(ReviewCard(
                        id: created.id, deckID: record.id.uuidString, deckName: template.name,
                        front: card.front, back: card.back, tags: tags
                    ))
                }
            }
            await backend.logEvent("deck_created", props: ["name": template.name, "via": "onboarding"])
        }
        createdDeckName = template.name
        creating = false
        withAnimation { step = 2 }
    }
}

// MARK: - Friends (premium social)

/// Premium social hub: share your friend code, add friends, accept requests, and
/// (after the multiplayer update is deployed) start co-op and versus sessions.
/// Gated behind a premium flag — payments (RevenueCat) are a later step, so a
/// dev unlock is provided for now.
