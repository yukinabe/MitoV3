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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(hero.name.uppercased())
                        .pixelText(size: 17, color: Color(hex: "3A2A18"))
                    Text(hero.role)
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
                        Text(inParty ? "IN PARTY" : "RESERVE")
                            .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(inParty ? Color(hex: "4A8A3C") : Color(hex: "6B4324"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }
                    .padding(10)
                }
                .frame(height: 176)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                HStack(spacing: 8) {
                    ModalStat(label: "HP", value: hero.hp, color: Color(hex: "3F8A3D"))
                    ModalStat(label: "ATK", value: hero.attack, color: Color(hex: "D4873A"))
                    ModalStat(label: "DEF", value: hero.defense, color: Color(hex: "4277D9"))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("LORE")
                        .pixelText(size: 10, color: Color(hex: "8A6B42"))
                    Text(hero.lore)
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "3A2A18"))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "F4E6C0"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

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
                        Text(hero.name.uppercased())
                            .pixelText(size: 12, color: Color(hex: "3A2A18"))
                        SmallTag("LV \(hero.level)", active: true)
                    }
                    Text(hero.role)
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
