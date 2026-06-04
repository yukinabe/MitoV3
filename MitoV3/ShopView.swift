import SwiftUI

struct ShopScreen: View {
    @Binding var gold: Int
    @Binding var gems: Int
    @Binding var biomass: Int
    @Binding var shards: Int

    var body: some View {
        ZStack {
            WoodBackground()
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    SpriteView(asset: "hero-mito-hop", size: 48)
                        .frame(width: 52, height: 52)
                        .background(Color(hex: "F0D6A4"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RIBO'S SHOP")
                            .pixelText(size: 15, color: Color(hex: "3A2A18"))
                        Text("\"Coins for the journey, gems for flair - but ATP? You earn that.\"")
                            .font(.custom(MitoFont.regular, size: 13))
                            .foregroundStyle(Color(hex: "5B442A"))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color(hex: "EAD4A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                .padding(.horizontal, 12)
                .padding(.top, 10)

                HStack(spacing: 6) {
                    ShopTab("DAILY", active: true)
                    ShopTab("RESOURCES", active: false)
                    ShopTab("COSMETICS", active: false)
                    ShopTab("SEASONAL", active: false)
                }
                .padding(.horizontal, 12)

                VStack(spacing: 12) {
                    ShopItemRow(icon: "treasure chest.fill", title: "Focus Chest", detail: "Free reward - unlocked by finishing a focus session.", price: "FREE\nCLAIM", accent: Color(hex: "F7C943")) {}
                    ShopItemRow(icon: "flask.fill", title: "ATP Flask", detail: "A small bottled boost. Once per day, coins only - studying still rules.", price: "100\nBUY", accent: Color(hex: "F7C943")) {
                        if gold >= 100 {
                            gold -= 100
                        }
                    }
                    ShopItemRow(icon: "circle.circle.fill", title: "Biomass Pouch", detail: "Today's discounted pouch for creature growth.", price: "60\n80", accent: Color(hex: "CFE49C")) {
                        if gold >= 60 {
                            gold -= 60
                            biomass += 12
                        }
                    }
                    ShopItemRow(icon: "diamond.fill", title: "Cloro Shard", detail: "Rotating shard offer - refreshes daily.", price: "220\nBUY", accent: Color(hex: "E3B8B8")) {
                        if gold >= 220 {
                            gold -= 220
                            shards += 3
                        }
                    }
                }
                .padding(.horizontal, 12)

                Text("Coins to progress · Gems to personalize")
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "B89868"))
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
        }
    }
}

struct ShopTab: View {
    let title: String
    let active: Bool

    init(_ title: String, active: Bool) {
        self.title = title
        self.active = active
    }

    var body: some View {
        Text(title)
            .pixelText(size: 9, color: active ? Color(hex: "18100A") : Color(hex: "F4E6C0"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(active ? Color(hex: "F7C943") : Color(hex: "6B4324"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

struct ShopItemRow: View {
    let icon: String
    let title: String
    let detail: String
    let price: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(Color(hex: "18100A"))
                    .frame(width: 44, height: 44)
                    .background(accent)
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .pixelText(size: 12, color: Color(hex: "3A2A18"))
                    Text(detail)
                        .font(.custom(MitoFont.regular, size: 12))
                        .foregroundStyle(Color(hex: "6B4324"))
                        .lineLimit(2)
                    Text(title == "Focus Chest" ? "" : title == "ATP Flask" ? "⚡ + 30" : title == "Biomass Pouch" ? "● + 12" : "♦ + 3")
                        .font(.custom(MitoFont.regular, size: 10))
                        .foregroundStyle(title == "Biomass Pouch" ? Color(hex: "6DB04C") : Color(hex: "8B6BD9"))
                }
                Spacer(minLength: 0)

                Text(price)
                    .pixelText(size: 11, color: price.contains("FREE") ? .white : Color(hex: "18100A"))
                    .multilineTextAlignment(.center)
                    .frame(width: 66, height: 42)
                    .background(price.contains("FREE") ? Color(hex: "4A8A3C") : Color(hex: "F7C943"))
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .padding(8)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        }
        .buttonStyle(.plain)
    }
}

struct ShopCard: View {
    let title: String
    let detail: String
    let cost: String
    let gain: String
    let action: () -> Void

    var body: some View {
        ParchmentBox {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title.uppercased())
                        .pixelText(size: 11, color: Color(hex: "3A2A18"))
                    Text(detail)
                        .font(.custom(MitoFont.regular, size: 15))
                        .foregroundStyle(Color(hex: "6B4324"))
                    HStack {
                        SmallTag(cost, active: false)
                        SmallTag(gain, active: true)
                    }
                }
                Spacer()
                Button(action: action) {
                    Text("BUY")
                        .pixelText(size: 9, color: .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(hex: "4A8A3C"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
