import SwiftUI

struct ShopScreen: View {
    @Binding var atp: Int
    @Binding var gold: Int
    @Binding var gems: Int
    @Binding var biomass: Int
    @Binding var shards: Int

    @AppStorage("lastDailyClaim") private var lastDailyClaim = ""
    @State private var tab: ShopTabKind = .daily
    @State private var pendingPack: GemPack?
    @State private var watchingAd = false
    @State private var toast: String?

    private var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    private var dailyClaimed: Bool { lastDailyClaim == todayKey }

    var body: some View {
        ZStack {
            WoodBackground()

            VStack(spacing: 8) {
                shopHeader
                walletStrip
                tabBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        switch tab {
                        case .daily: dailyTab
                        case .gems: gemsTab
                        case .coins: coinsTab
                        case .resources: resourcesTab
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 96)
                }
            }
            .padding(.top, 10)

            if let pendingPack {
                purchaseConfirm(pendingPack)
            }
            if watchingAd {
                adOverlay
            }
            if let toast {
                toastView(toast)
            }
        }
    }

    // MARK: - Header & wallet

    private var shopHeader: some View {
        HStack(spacing: 10) {
            SpriteView(asset: "hero-mito-hop", size: 48)
                .frame(width: 52, height: 52)
                .background(Color(hex: "F0D6A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            VStack(alignment: .leading, spacing: 4) {
                Text("RIBO'S SHOP")
                    .pixelText(size: 15, color: Color(hex: "3A2A18"))
                Text("\"Gems for a head start, coins for the grind.\"")
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
    }

    private var walletStrip: some View {
        HStack(spacing: 6) {
            WalletChip(asset: "hud-gem", value: gems, color: Color(hex: "BFF5C2"))
            WalletChip(asset: "hud-coin", value: gold, color: Color(hex: "F9E9B8"))
            WalletChip(symbol: "🧬", value: biomass, color: Color(hex: "CFE49C"))
            WalletChip(symbol: "♦", value: shards, color: Color(hex: "E3B8B8"))
        }
        .padding(.horizontal, 12)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(ShopTabKind.allCases) { kind in
                Button { tab = kind } label: {
                    Text(kind.title)
                        .pixelText(size: 9, color: tab == kind ? Color(hex: "18100A") : Color(hex: "F4E6C0"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(tab == kind ? Color(hex: "F7C943") : Color(hex: "6B4324"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Tabs

    private var dailyTab: some View {
        VStack(spacing: 10) {
            ShopOfferCard(
                icon: "gift.fill",
                accent: Color(hex: "F7C943"),
                title: "Daily Reward",
                detail: dailyClaimed ? "Claimed — come back tomorrow." : "Free every day. +25 💎  +500 ◎",
                actionTitle: dailyClaimed ? "DONE" : "CLAIM",
                actionTint: dailyClaimed ? Color(hex: "8A6B42") : Color(hex: "4A8A3C"),
                enabled: !dailyClaimed,
                action: claimDaily
            )

            ShopOfferCard(
                icon: "play.rectangle.fill",
                accent: Color(hex: "8B6BD9"),
                title: "Watch an Ad",
                detail: "Watch a short video for +15 💎.",
                actionTitle: "WATCH",
                actionTint: Color(hex: "4A8A3C"),
                enabled: !watchingAd,
                action: watchAd
            )

            Text("Spend gems on coins · spend coins on resources")
                .font(.custom(MitoFont.regular, size: 12))
                .foregroundStyle(Color(hex: "B89868"))
                .padding(.top, 4)
        }
    }

    private var gemsTab: some View {
        VStack(spacing: 10) {
            ForEach(GemPack.all) { pack in
                ShopBuyRow(
                    icon: "diamond.fill",
                    accent: Color(hex: "8B6BD9"),
                    title: "\(pack.gems) Gems",
                    detail: pack.bonus,
                    priceTitle: pack.price,
                    priceTint: Color(hex: "4A8A3C"),
                    action: { pendingPack = pack }
                )
            }
            Text("Mock store — purchases grant instantly, no charge.")
                .font(.custom(MitoFont.regular, size: 12))
                .foregroundStyle(Color(hex: "B89868"))
                .padding(.top, 4)
        }
    }

    private var coinsTab: some View {
        VStack(spacing: 10) {
            ForEach(CoinBundle.all) { bundle in
                ShopBuyRow(
                    icon: "circle.fill",
                    accent: Color(hex: "F7C943"),
                    title: "\(bundle.coins.formatted()) Coins",
                    detail: "Exchange gems for coins.",
                    priceTitle: "\(bundle.gemCost) 💎",
                    priceTint: gems >= bundle.gemCost ? Color(hex: "4A8A3C") : Color(hex: "8A6B42"),
                    action: { buyCoins(bundle) }
                )
            }
        }
    }

    private var resourcesTab: some View {
        VStack(spacing: 10) {
            ShopBuyRow(icon: "circle.circle.fill", accent: Color(hex: "CFE49C"),
                       title: "Biomass Pouch", detail: "+12 🧬 — upgrade material.",
                       priceTitle: "60 ◎", priceTint: gold >= 60 ? Color(hex: "4A8A3C") : Color(hex: "8A6B42"),
                       action: { buyResource(cost: 60) { biomass += 12 } })
            ShopBuyRow(icon: "diamond.fill", accent: Color(hex: "E3B8B8"),
                       title: "Cloro Shard", detail: "+3 ♦ — rare material.",
                       priceTitle: "220 ◎", priceTint: gold >= 220 ? Color(hex: "4A8A3C") : Color(hex: "8A6B42"),
                       action: { buyResource(cost: 220) { shards += 3 } })
            ShopBuyRow(icon: "flask.fill", accent: Color(hex: "F7C943"),
                       title: "ATP Flask", detail: "+30 ⚡ — instant focus boost.",
                       priceTitle: "100 ◎", priceTint: gold >= 100 ? Color(hex: "4A8A3C") : Color(hex: "8A6B42"),
                       action: { buyResource(cost: 100) { atp += 30 } })
        }
    }

    // MARK: - Overlays

    private func purchaseConfirm(_ pack: GemPack) -> some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .onTapGesture { pendingPack = nil }
            VStack(spacing: 14) {
                Text("CONFIRM PURCHASE")
                    .pixelText(size: 14, color: Color(hex: "3A2A18"))
                Text("\(pack.gems) gems for \(pack.price)?")
                    .font(.custom(MitoFont.regular, size: 16))
                    .foregroundStyle(Color(hex: "6B4324"))
                HStack(spacing: 10) {
                    Button { pendingPack = nil } label: {
                        Text("CANCEL")
                            .pixelText(size: 12, color: Color(hex: "3A2A18"))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(hex: "EAD4A4"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }.buttonStyle(.plain)
                    Button {
                        gems += pack.gems
                        pendingPack = nil
                        showToast("+\(pack.gems) 💎")
                    } label: {
                        Text("BUY")
                            .pixelText(size: 12, color: Color(hex: "F4E6C0"))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(hex: "4A8A3C"))
                            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                    }.buttonStyle(.plain)
                }
            }
            .padding(18)
            .frame(width: 270)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
        }
        .zIndex(30)
    }

    private var adOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("AD PLAYING…")
                    .pixelText(size: 16, color: Color(hex: "F4E6C0"))
                ProgressView()
                    .tint(Color(hex: "F7C943"))
                Text("Reward unlocks when it finishes.")
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(Color(hex: "B89868"))
            }
        }
        .zIndex(30)
    }

    private func toastView(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .pixelText(size: 13, color: Color(hex: "F4E6C0"))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color(hex: "2A1B0E"))
                .overlay(Rectangle().stroke(Color(hex: "F7C943"), lineWidth: 2))
                .padding(.bottom, 110)
        }
        .zIndex(40)
        .transition(.opacity)
    }

    // MARK: - Actions

    private func claimDaily() {
        guard !dailyClaimed else { return }
        gems += 25
        gold += 500
        lastDailyClaim = todayKey
        showToast("+25 💎  +500 ◎")
    }

    private func watchAd() {
        guard !watchingAd else { return }
        watchingAd = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            watchingAd = false
            gems += 15
            showToast("+15 💎")
        }
    }

    private func buyCoins(_ bundle: CoinBundle) {
        guard gems >= bundle.gemCost else {
            AudioManager.shared.play(.uiBack); Haptics.warning()
            showToast("Not enough gems"); return
        }
        gems -= bundle.gemCost
        gold += bundle.coins
        AudioManager.shared.play(.reward); Haptics.success()
        showToast("+\(bundle.coins.formatted()) ◎")
    }

    private func buyResource(cost: Int, grant: () -> Void) {
        guard gold >= cost else {
            AudioManager.shared.play(.uiBack); Haptics.warning()
            showToast("Not enough coins"); return
        }
        gold -= cost
        grant()
        AudioManager.shared.play(.reward); Haptics.success()
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { toast = nil }
        }
    }
}

enum ShopTabKind: String, CaseIterable, Identifiable {
    case daily, gems, coins, resources
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: "DAILY"
        case .gems: "GEMS"
        case .coins: "COINS"
        case .resources: "RESOURCES"
        }
    }
}

struct GemPack: Identifiable {
    let id = UUID()
    let gems: Int
    let price: String
    let bonus: String

    static let all: [GemPack] = [
        GemPack(gems: 100, price: "$0.99", bonus: "Starter handful."),
        GemPack(gems: 550, price: "$4.99", bonus: "+10% bonus gems."),
        GemPack(gems: 1200, price: "$9.99", bonus: "+20% bonus gems."),
        GemPack(gems: 3000, price: "$19.99", bonus: "+30% — best value.")
    ]
}

struct CoinBundle: Identifiable {
    let id = UUID()
    let coins: Int
    let gemCost: Int

    static let all: [CoinBundle] = [
        CoinBundle(coins: 1000, gemCost: 40),
        CoinBundle(coins: 3000, gemCost: 100),
        CoinBundle(coins: 8000, gemCost: 240)
    ]
}

struct WalletChip: View {
    var asset: String?
    var symbol: String?
    let value: Int
    let color: Color

    init(asset: String, value: Int, color: Color) {
        self.asset = asset; self.symbol = nil; self.value = value; self.color = color
    }
    init(symbol: String, value: Int, color: Color) {
        self.asset = nil; self.symbol = symbol; self.value = value; self.color = color
    }

    var body: some View {
        HStack(spacing: 4) {
            if let asset {
                Image(asset).resizable().interpolation(.none).scaledToFit().frame(width: 18, height: 18)
            } else if let symbol {
                Text(symbol).font(.system(size: 13))
            }
            Text(value.formatted())
                .pixelText(size: 9, color: color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color(hex: "2A1B0E"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
    }
}

/// A daily/ad style offer with a single action button.
struct ShopOfferCard: View {
    let icon: String
    let accent: Color
    let title: String
    let detail: String
    let actionTitle: String
    let actionTint: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(Color(hex: "18100A"))
                .frame(width: 46, height: 46)
                .background(accent)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).pixelText(size: 12, color: Color(hex: "3A2A18"))
                Text(detail)
                    .font(.custom(MitoFont.regular, size: 12))
                    .foregroundStyle(Color(hex: "6B4324"))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: action) {
                Text(actionTitle)
                    .pixelText(size: 10, color: Color(hex: "F4E6C0"))
                    .frame(width: 70, height: 42)
                    .background(actionTint)
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.7)
        }
        .padding(8)
        .background(Color(hex: "EAD4A4"))
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

/// A purchasable row with a price button.
struct ShopBuyRow: View {
    let icon: String
    let accent: Color
    let title: String
    let detail: String
    let priceTitle: String
    let priceTint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(Color(hex: "18100A"))
                    .frame(width: 46, height: 46)
                    .background(accent)
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).pixelText(size: 12, color: Color(hex: "3A2A18"))
                    Text(detail)
                        .font(.custom(MitoFont.regular, size: 12))
                        .foregroundStyle(Color(hex: "6B4324"))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(priceTitle)
                    .pixelText(size: 11, color: Color(hex: "F4E6C0"))
                    .frame(width: 76, height: 42)
                    .background(priceTint)
                    .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            }
            .padding(8)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        }
        .buttonStyle(.plain)
    }
}
