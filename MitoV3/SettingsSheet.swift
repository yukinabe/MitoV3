//  SettingsSheet.swift
//  Extracted from ContentView.swift (behavior-preserving refactor).

import SwiftUI
import Supabase

struct GeneralSettingsSheet: View {
    @ObservedObject var backend: MitoBackend
    @Binding var isPresented: Bool
    let showAuth: () -> Void

    @AppStorage("audio.sfx") private var soundEnabled = true
    @AppStorage("audio.music") private var musicEnabled = true
    @AppStorage("settings.animations") private var animationsEnabled = true
    @AppStorage(NotificationManager.cadenceKey) private var dueCadence = NotificationManager.DueCadence.daily.rawValue
    @ObservedObject private var lock = FocusLockManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var showingAppPicker = false
    #if os(iOS)
    @State private var pickerSelection = FocusBlockSelection.load()
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("SETTINGS"))
                    .pixelText(size: 17, color: Color(hex: "3A2A18"))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Text("X")
                        .pixelText(size: 13, color: Color(hex: "3A2A18"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                SettingsActionRow(
                    title: backend.isLoggedIn ? L("ACCOUNT") : L("LOGIN"),
                    detail: backend.isLoggedIn
                        ? "Signed in as \(backend.accountEmail ?? "you") · sign out or delete"
                        : L("Sign in to sync decks and progress."),
                    value: backend.isLoggedIn ? L("MANAGE") : L("SIGN IN"),
                    action: showAuth
                )

                SettingsLanguageRow(language: $loc.language)

                SettingsToggleRow(title: L("SOUND"), detail: L("Menu and battle effects."), isOn: $soundEnabled)
                SettingsToggleRow(title: L("MUSIC"), detail: L("Background music."), isOn: $musicEnabled)
                SettingsToggleRow(title: L("ANIMATION"), detail: L("Idle character movement."), isOn: $animationsEnabled)
                SettingsReminderRow(cadenceRaw: $dueCadence)

                Text(L("FOCUS LOCK"))
                    .pixelText(size: 10, color: Color(hex: "3A2A18"))
                    .padding(.top, 6)
                SettingsToggleRow(
                    title: L("STAY-IN-APP LOCK"),
                    detail: L("Leaving Mito during a timed session voids the run."),
                    isOn: $lock.softLockEnabled)
                #if os(iOS)
                // The OS-level app shield is hidden until the Family Controls
                // entitlement is granted (see BetaConfig.appShieldEnabled).
                if BetaConfig.appShieldEnabled {
                    SettingsToggleRow(
                        title: L("BLOCK APPS"),
                        detail: L("Shield distracting apps with Screen Time during focus. Needs permission."),
                        isOn: $lock.shieldEnabled)
                    if lock.shieldEnabled {
                        SettingsActionRow(
                            title: L("CHOOSE BLOCKED APPS"),
                            detail: "\(FocusBlockSelection.count()) app group(s) blocked during focus.",
                            value: L("PICK"),
                            action: {
                                lock.requestShieldAuthorization()
                                showingAppPicker = true
                            })
                    }
                }
                #endif

                #if DEBUG
                DevToolsSection(isPresented: $isPresented)
                #endif
            }
            }
        }
        #if os(iOS)
        .familyActivityPicker(isPresented: $showingAppPicker, selection: $pickerSelection)
        .onChange(of: pickerSelection) { _, sel in
            FocusBlockSelection.save(sel)
        }
        #endif
        .onChange(of: soundEnabled) { _, on in
            AudioManager.shared.sfxEnabled = on
            if on { AudioManager.shared.play(.uiTap) }
        }
        .onChange(of: musicEnabled) { _, on in
            AudioManager.shared.musicEnabled = on
        }
        .onChange(of: dueCadence) { _, _ in
            NotificationManager.shared.reschedule()
        }
        .padding(16)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

private struct SettingsReminderRow: View {
    @Binding var cadenceRaw: String

    private var cadence: NotificationManager.DueCadence {
        NotificationManager.DueCadence(rawValue: cadenceRaw) ?? .daily
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BIO BUD NUDGES")
                    .pixelText(size: 11, color: Color(hex: "3A2A18"))
                Text("Due-card reminders from your home-screen buddy.")
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Button {
                let all = NotificationManager.DueCadence.allCases
                let index = all.firstIndex(of: cadence) ?? 0
                cadenceRaw = all[(index + 1) % all.count].rawValue
                Haptics.select()
            } label: {
                Text(cadence.label)
                    .pixelText(size: 9, color: cadence == .off ? Color(hex: "3A2A18") : Color(hex: "F4E6C0"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(cadence == .off ? Color(hex: "B89868") : Color(hex: "4A8A3C"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }
}

private struct SettingsActionRow: View {
    let title: String
    let detail: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .pixelText(size: 11, color: Color(hex: "3A2A18"))
                    Text(detail)
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(value)
                    .pixelText(size: 9, color: Color(hex: "F4E6C0"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(Color(hex: "4A8A3C"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }
            .padding(10)
            .background(Color(hex: "F4E6C0"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// Language selector styled like the other settings rows: two pixel chips the
/// player taps. Switching updates `LocalizationManager`, which rebuilds the UI.
private struct SettingsLanguageRow: View {
    @Binding var language: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("LANGUAGE"))
                    .pixelText(size: 11, color: Color(hex: "3A2A18"))
                Text(L("App display language."))
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(Color(hex: "6B4324"))
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(AppLanguage.allCases) { lang in
                    let on = lang == language
                    Button {
                        guard !on else { return }
                        language = lang
                        Haptics.tap()
                    } label: {
                        Text(lang.displayName)
                            .font(.custom(MitoFont.regular, size: 13))
                            .foregroundStyle(on ? Color(hex: "F4E6C0") : Color(hex: "3A2A18"))
                            .padding(.horizontal, 9)
                            .frame(height: 30)
                            .background(on ? Color(hex: "4A8A3C") : Color(hex: "B89868"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .pixelText(size: 11, color: Color(hex: "3A2A18"))
                    Text(detail)
                        .font(.custom(MitoFont.regular, size: 13))
                        .foregroundStyle(Color(hex: "6B4324"))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(isOn ? L("ON") : L("OFF"))
                    .pixelText(size: 9, color: isOn ? Color(hex: "F4E6C0") : Color(hex: "3A2A18"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(isOn ? Color(hex: "4A8A3C") : Color(hex: "B89868"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            }
            .padding(10)
            .background(Color(hex: "F4E6C0"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
/// Developer-only shortcuts (compiled out of release builds). Lives at the bottom
/// of the Settings sheet.
private struct DevToolsSection: View {
    @Binding var isPresented: Bool
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEV TOOLS")
                .pixelText(size: 10, color: Color(hex: "C4452F"))
                .padding(.top, 8)

            FlowLayout(spacing: 6) {
                devButton("UNLOCK + TRUST ALL") {
                    for h in DataSet.heroes {
                        RosterStore.shared.unlock(h.id)
                        TrustStore.shared.devGrantFullTrust(h)
                    }
                    for c in DataSet.capturables {
                        CaptureStore.shared.capture(c.id)
                        TrustStore.shared.devGrantFullTrust(c)
                    }
                    note = "all characters unlocked + trusted"
                }
                devButton("CLEAR CAMPAIGN") {
                    UserDefaults.standard.set(DataSet.stages.count, forKey: "campaign.cleared")
                    note = "all stages cleared"
                }
                devButton("+99999 CURRENCY") {
                    for k in ["wallet.atp", "wallet.gold", "wallet.gems", "wallet.biomass", "wallet.shards"] {
                        UserDefaults.standard.set(99999, forKey: k)
                    }
                    note = "currency maxed"
                }
                devButton("+30 EGGS") {
                    for _ in 0..<3 { EggStore.shared.awardEggs(forMinutes: 250) }
                    note = "+30 eggs"
                }
                devButton("REPLAY TUTORIAL") {
                    let d = UserDefaults.standard
                    d.set(true, forKey: "mito.onboarded")
                    d.set(false, forKey: "mito.tutorialSeen")
                    isPresented = false
                    TutorialManager.shared.start(goal: d.string(forKey: "mito.goal") ?? "")
                }
                devButton("RESET SAVE") {
                    RosterStore.shared.reset()
                    CaptureStore.shared.reset()
                    TrustStore.shared.reset()
                    PartyStore.shared.reset()
                    let d = UserDefaults.standard
                    for k in ["mito.onboarded", "mito.tutorialSeen", "campaign.cleared",
                              "wallet.atp", "wallet.gold", "wallet.gems", "wallet.biomass", "wallet.shards",
                              "migration.trustV1.done", "migration.recruitV1.done",
                              "campaign.story.seen", "study.companion"] {
                        d.removeObject(forKey: k)
                    }
                    note = "save reset — relaunch the app"
                }
            }

            if !note.isEmpty {
                Text("✓ \(note)")
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "4A8A3C"))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "C4452F"), lineWidth: 2))
    }

    private func devButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tap()
        } label: {
            Text(title)
                .font(.custom(MitoFont.regular, size: 12))
                .foregroundStyle(Color(hex: "F4E6C0"))
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(Color(hex: "B0492F"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
#endif
