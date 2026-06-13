import SwiftUI

struct ShopScreen: View {
    @Binding var atp: Int
    @Binding var gold: Int
    @Binding var gems: Int
    @Binding var biomass: Int
    @Binding var shards: Int

    @AppStorage("lastDailyClaim") private var lastDailyClaim = ""
    @State private var pendingPack: GemPack?
    @State private var watchingAd = false
    @State private var toast: String?
    @ObservedObject private var streak = StreakStore.shared

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

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        storeFeed
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
            SpriteView(asset: "hero-b-cell-hop", size: 50)
                .frame(width: 52, height: 52)
                .background(Color(hex: "F0D6A4"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
            VStack(alignment: .leading, spacing: 4) {
                Text("RIBO'S SHOP")
                    .pixelText(size: 15, color: Color(hex: "3A2A18"))
                Text("\"Coins for the journey, gems for flair — but ATP? You earn that.\"")
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

    // MARK: - Store feed

    private var storeFeed: some View {
        VStack(spacing: 12) {
            ShopSectionTitle("TODAY")
            ShopOfferCard(
                art: .asset("btn-pot"),
                title: "Daily Reward",
                detail: dailyClaimed ? "Claimed — come back tomorrow." : "Free every day. +25 gems and +500 coins.",
                actionTitle: dailyClaimed ? "DONE" : "CLAIM",
                actionTint: dailyClaimed ? Color(hex: "8A6B42") : Color(hex: "4A8A3C"),
                enabled: !dailyClaimed,
                action: claimDaily
            )

            ShopOfferCard(
                art: .badge("PLAY", Color(hex: "7AA35A")),
                title: "Watch an Ad",
                detail: "Watch a short video for +15 gems.",
                actionTitle: "WATCH",
                actionTint: Color(hex: "4A8A3C"),
                enabled: !watchingAd,
                action: watchAd
            )

            ShopSectionTitle("GEMS")
            ForEach(GemPack.all) { pack in
                ShopBuyRow(
                    art: .asset("currency-gem"),
                    title: "\(pack.gems) Gems",
                    detail: pack.bonus,
                    priceTitle: pack.price,
                    priceTint: Color(hex: "4A8A3C"),
                    action: { pendingPack = pack }
                )
            }

            ShopSectionTitle("COINS")
            ForEach(CoinBundle.all) { bundle in
                ShopBuyRow(
                    art: .asset("currency-coin"),
                    title: "\(bundle.coins.formatted()) Coins",
                    detail: "Exchange gems for coins.",
                    priceTitle: "\(bundle.gemCost) GEM",
                    priceTint: gems >= bundle.gemCost ? Color(hex: "4A8A3C") : Color(hex: "8A6B42"),
                    action: { buyCoins(bundle) }
                )
            }

            ShopSectionTitle("RESOURCES")
            ShopBuyRow(art: .asset("currency-biomass"),
                       title: "Biomass Pouch", detail: "+12 biomass for creature growth.",
                       priceTitle: "60 COIN", priceTint: gold >= 60 ? Color(hex: "4A8A3C") : Color(hex: "8A6B42"),
                       action: { buyResource(cost: 60, toast: "+12 BIOMASS") { biomass += 12 } })
            ShopBuyRow(art: .asset("currency-shard"),
                       title: "Cloro Shard", detail: "+3 shards for rare upgrades.",
                       priceTitle: "220 COIN", priceTint: gold >= 220 ? Color(hex: "4A8A3C") : Color(hex: "8A6B42"),
                       action: { buyResource(cost: 220, toast: "+3 SHARDS") { shards += 3 } })
            ShopBuyRow(art: .asset("currency-atp"),
                       title: "ATP Flask", detail: "+30 ATP. Once per day, studying still rules.",
                       priceTitle: "100 COIN", priceTint: gold >= 100 ? Color(hex: "4A8A3C") : Color(hex: "8A6B42"),
                       action: { buyResource(cost: 100, toast: "+30 ATP") { atp += 30 } })
            ShopBuyRow(art: .asset("currency-freeze"),
                       title: "Streak Freeze", detail: "Protects one missed day. Owned \(streak.freezes)/\(StreakStore.maxFreezes).",
                       priceTitle: streak.freezes >= StreakStore.maxFreezes ? "FULL" : "\(StreakStore.freezeCostGold) COIN",
                       priceTint: canBuyFreeze ? Color(hex: "4A8A3C") : Color(hex: "8A6B42"),
                       action: buyFreeze)
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
                        showToast("+\(pack.gems) GEMS")
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
        showToast("+25 GEMS  +500 COINS")
    }

    private func watchAd() {
        guard !watchingAd else { return }
        watchingAd = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            watchingAd = false
            gems += 15
            showToast("+15 GEMS")
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
        showToast("+\(bundle.coins.formatted()) COINS")
    }

    private func buyResource(cost: Int, toast: String, grant: () -> Void) {
        guard gold >= cost else {
            AudioManager.shared.play(.uiBack); Haptics.warning()
            showToast("Not enough coins"); return
        }
        gold -= cost
        grant()
        AudioManager.shared.play(.reward); Haptics.success()
        showToast(toast)
    }

    private var canBuyFreeze: Bool {
        streak.freezes < StreakStore.maxFreezes && gold >= StreakStore.freezeCostGold
    }

    private func buyFreeze() {
        guard streak.freezes < StreakStore.maxFreezes else {
            AudioManager.shared.play(.uiBack); Haptics.warning()
            showToast("Freezes full")
            return
        }
        guard gold >= StreakStore.freezeCostGold else {
            AudioManager.shared.play(.uiBack); Haptics.warning()
            showToast("Not enough coins")
            return
        }
        if streak.addFreeze() {
            gold -= StreakStore.freezeCostGold
            AudioManager.shared.play(.reward); Haptics.success()
            showToast("+1 FREEZE")
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { toast = nil }
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

enum ShopArt {
    case asset(String)
    case badge(String, Color)
}

struct ShopSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color(hex: "F7C943"))
                .frame(width: 8, height: 18)
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
            Text(title)
                .pixelText(size: 12, color: Color(hex: "F4E6C0"))
            Spacer()
        }
        .padding(.top, 2)
    }
}

struct ShopArtTile: View {
    let art: ShopArt

    var body: some View {
        ZStack {
            Color(hex: "F4E6C0")
            switch art {
            case .asset(let name):
                Image(name)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(name.hasPrefix("hud-") ? 8 : 5)
            case .badge(let text, let color):
                color
                Text(text)
                    .pixelText(size: text.count > 1 ? 8 : 13, color: Color(hex: "18100A"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 3)
            }
        }
        .frame(width: 50, height: 50)
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

/// A daily/ad style offer with a single action button.
struct ShopOfferCard: View {
    let art: ShopArt
    let title: String
    let detail: String
    let actionTitle: String
    let actionTint: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ShopArtTile(art: art)
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
    let art: ShopArt
    let title: String
    let detail: String
    let priceTitle: String
    let priceTint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ShopArtTile(art: art)
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
