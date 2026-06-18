//  CharacterInfoModal.swift
//  Character detail modal + its sub-rows (cost chip, ability row, stats, hero row).
//  Extracted from CollectionView.swift (behavior-preserving refactor).

import SwiftUI

struct CharacterInfoModal: View {
    let hero: Hero
    let inParty: Bool
    let goldCost: Int
    let bioCost: Int
    let ownedBio: Int
    let canUpgrade: Bool
    let onClose: () -> Void
    let onUpgrade: () -> Void

    @ObservedObject private var trust = TrustStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L(hero.name).uppercased())
                        .pixelText(size: 17, color: Color(hex: "3A2A18"))
                    Text(L(hero.role))
                        .font(.custom(MitoFont.regular, size: 16))
                        .foregroundStyle(Color(hex: "6B4324"))
                    Spacer()
                    Button(action: onClose) {
                        Text("×")
                            .font(.custom(MitoFont.regular, size: 22))
                            .foregroundStyle(Color(hex: "3A2A18"))
                    }
                    .buttonStyle(.plain)
                }

                ZStack(alignment: .top) {
                    LinearGradient(colors: [hero.color.opacity(0.38), Color(hex: "E8D0B0")], startPoint: .top, endPoint: .bottom)
                    SpriteView(asset: hero.asset, size: 142)
                        .padding(.top, 28)

                    HStack {
                        Text("LV \(hero.level)")
                            .pixelText(size: 12, color: Color(hex: "18100A"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: "F7C943"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        Spacer()
                        Text(partyBadge)
                            .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(partyBadgeColor)
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .padding(10)
                }
                .frame(height: 176)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("PERSONALITY"))
                        .pixelText(size: 10, color: hero.rarity.color)
                    Text(L(hero.lore))
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "3A2A18"))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "F4E6C0"))
                .overlay(Rectangle().stroke(hero.rarity.color, lineWidth: 3))

                trustSection

                HStack(spacing: 8) {
                    ModalStat(label: "HP", value: hero.hp, color: Color(hex: "3F8A3D"))
                    ModalStat(label: "ATK", value: hero.attack, color: Color(hex: "D4873A"))
                    ModalStat(label: "DEF", value: hero.defense, color: Color(hex: "4277D9"))
                }

                if trust.isMaxed(hero) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LEVEL UP")
                                .pixelText(size: 11, color: Color(hex: "3A2A18"))
                            Text("+5 HP · +3 ATK · +2 DEF")
                                .font(.custom(MitoFont.regular, size: 13))
                                .foregroundStyle(Color(hex: "6B4324"))
                            HStack(spacing: 6) {
                                CurrencyCostChip(asset: "currency-coin", value: goldCost, color: Color(hex: "8A6B42"))
                                CurrencyCostChip(asset: "currency-biomass", value: bioCost, color: ownedBio >= bioCost ? Color(hex: "4A8A3C") : Color(hex: "C4452F"))
                                Text("(have \(ownedBio))")
                                    .font(.custom(MitoFont.regular, size: 12))
                                    .foregroundStyle(Color(hex: "8A6B42"))
                            }
                        }
                        Spacer()
                        Button(action: onUpgrade) {
                            VStack(spacing: 1) {
                                Text("UPGRADE")
                                    .pixelText(size: 10, color: Color(hex: "18100A"))
                                Text(canUpgrade ? "LEVEL UP" : "NEED MATS")
                                    .pixelText(size: 7, color: Color(hex: "3A2A18"))
                            }
                            .frame(width: 84, height: 39)
                            .background(canUpgrade ? Color(hex: "F7C943") : Color(hex: "8A6B42"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canUpgrade)
                    }
                    .padding(10)
                    .background(Color(hex: "F4E6C0"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                } else {
                    // Upgrades are locked until the character trusts you.
                    HStack(spacing: 8) {
                        Text("🔒")
                            .font(.system(size: 20))
                        Text(L("Study with them to build Trust."))
                            .font(.custom(MitoFont.regular, size: 13))
                            .foregroundStyle(Color(hex: "6B4324"))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "EADAC0"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("MOVES")
                        .pixelText(size: 10, color: Color(hex: "8A6B42"))
                    ForEach(hero.abilities) { ability in
                        AbilityInfoRow(ability: ability)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "F4E6C0"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .padding(13)
        }
        .frame(maxHeight: 690)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }

    private var partyBadge: String {
        if inParty { return "IN PARTY" }
        return trust.isMaxed(hero) ? "RESERVE" : L("LOCKED")
    }

    private var partyBadgeColor: Color {
        if inParty { return Color(hex: "4A8A3C") }
        return trust.isMaxed(hero) ? Color(hex: "6B4324") : Color(hex: "B0492F")
    }

    /// Trust meter (pre-max) that flips to a Bond meter once the character is
    /// fully trusted. Bond accrues forever (1 "level" per 60 study minutes).
    @ViewBuilder
    private var trustSection: some View {
        let maxed = trust.isMaxed(hero)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(maxed ? L("BOND") : L("TRUST"))
                    .pixelText(size: 10, color: maxed ? Color(hex: "9A5BB8") : Color(hex: "8A6B42"))
                Spacer()
                Text(trustValueText)
                    .pixelText(size: 8, color: Color(hex: "6B4324"))
            }
            ProgressBar(
                progress: maxed ? bondFraction : trust.fraction(hero),
                color: maxed ? Color(hex: "C98AE0") : Color(hex: "4A8A3C"))
            if !maxed {
                Text(L("Earn full Trust to use them in battle."))
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "B0492F"))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }

    private var trustValueText: String {
        if trust.isMaxed(hero) {
            return "LV \(bondLevel)"
        }
        return "\(Int(trust.trust(hero)))/\(Int(trust.required(hero))) MIN"
    }

    private var bondLevel: Int { Int(trust.bondValue(hero) / 60) + 1 }
    private var bondFraction: Double {
        (trust.bondValue(hero).truncatingRemainder(dividingBy: 60)) / 60
    }
}

struct CurrencyCostChip: View {
    let asset: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(asset)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 15, height: 15)
            Text("\(value)")
                .pixelText(size: 10, color: color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct AbilityInfoRow: View {
    let ability: BattleAbility

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(ability.kind.rawValue.uppercased())
                    .pixelText(size: 7, color: Color(hex: "F4E6C0"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(ability.color.opacity(0.9))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))

                Text(ability.name.uppercased())
                    .pixelText(size: 9, color: Color(hex: "3A2A18"))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(ability.dealsDamage ? "DMG \(ability.damage)" : "SUPPORT")
                    .pixelText(size: 7, color: ability.dealsDamage ? Color(hex: "8A6B42") : Color(hex: "3E7BB0"))
            }

            Text(ability.detail)
                .font(.custom(MitoFont.regular, size: 12))
                .foregroundStyle(Color(hex: "4A2F1C"))
                .fixedSize(horizontal: false, vertical: true)

            Text(ability.theme.uppercased())
                .pixelText(size: 6, color: Color(hex: "6B4324"))
                .opacity(0.82)
        }
        .padding(8)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }
}

struct ModalStat: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.custom(MitoFont.regular, size: 12))
                .foregroundStyle(Color(hex: "8A6B42"))
            Text("\(value)")
                .pixelText(size: 20, color: color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color(hex: "F4E6C0"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

struct HeroRow: View {
    let hero: Hero
    let upgrade: () -> Void

    var body: some View {
        ParchmentBox {
            HStack(spacing: 12) {
                SpriteView(asset: hero.asset, size: 58)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(L(hero.name).uppercased())
                            .pixelText(size: 12, color: Color(hex: "3A2A18"))
                        SmallTag("LV \(hero.level)", active: true)
                    }
                    Text(L(hero.role))
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "6B4324"))
                    HPBar(value: hero.hp, max: 60, tint: hero.color)
                    HStack(spacing: 7) {
                        StatPill("ATK \(hero.attack)")
                        StatPill("DEF \(hero.defense)")
                    }
                }
                Button(action: upgrade) {
                    Text("UP")
                        .pixelText(size: 9, color: .white)
                        .padding(10)
                        .background(Color(hex: "4A8A3C"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
