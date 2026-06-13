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
    @ObservedObject private var lock = FocusLockManager.shared
    @State private var showingAppPicker = false
    #if os(iOS)
    @State private var pickerSelection = FocusBlockSelection.load()
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SETTINGS")
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

            VStack(spacing: 8) {
                SettingsActionRow(
                    title: backend.isLoggedIn ? "ACCOUNT" : "LOGIN",
                    detail: backend.isLoggedIn
                        ? "Signed in as \(backend.accountEmail ?? "you") · sign out or delete"
                        : "Sign in to sync decks and progress.",
                    value: backend.isLoggedIn ? "MANAGE" : "SIGN IN",
                    action: showAuth
                )

                SettingsToggleRow(title: "SOUND", detail: "Menu and battle effects.", isOn: $soundEnabled)
                SettingsToggleRow(title: "MUSIC", detail: "Background music.", isOn: $musicEnabled)
                SettingsToggleRow(title: "ANIMATION", detail: "Idle character movement.", isOn: $animationsEnabled)

                Text("FOCUS LOCK")
                    .pixelText(size: 10, color: Color(hex: "3A2A18"))
                    .padding(.top, 6)
                SettingsToggleRow(
                    title: "STAY-IN-APP LOCK",
                    detail: "Leaving Mito during a timed session voids the run.",
                    isOn: $lock.softLockEnabled)
                #if os(iOS)
                // The OS-level app shield is hidden until the Family Controls
                // entitlement is granted (see BetaConfig.appShieldEnabled).
                if BetaConfig.appShieldEnabled {
                    SettingsToggleRow(
                        title: "BLOCK APPS",
                        detail: "Shield distracting apps with Screen Time during focus. Needs permission.",
                        isOn: $lock.shieldEnabled)
                    if lock.shieldEnabled {
                        SettingsActionRow(
                            title: "CHOOSE BLOCKED APPS",
                            detail: "\(FocusBlockSelection.count()) app group(s) blocked during focus.",
                            value: "PICK",
                            action: {
                                lock.requestShieldAuthorization()
                                showingAppPicker = true
                            })
                    }
                }
                #endif
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
        .padding(16)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
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
                Text(isOn ? "ON" : "OFF")
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

