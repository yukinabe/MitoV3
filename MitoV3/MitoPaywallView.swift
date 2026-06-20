import SwiftUI
import RevenueCat

struct MitoPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @State private var selectedPlan: Plan = .yearly

    private enum Plan {
        case yearly
        case monthly
    }

    private enum Palette {
        static let panel = Color(hex: "EAD4A4")
        static let innerPanel = Color(hex: "F4E6C0")
        static let outline = Color(hex: "18100A")
        static let ink = Color(hex: "3A2A18")
        static let bark = Color(hex: "6B4324")
        static let gold = Color(hex: "B8860B")
        static let brightGold = Color(hex: "F7C943")
        static let green = Color(hex: "4A8A3C")
        static let blue = Color(hex: "4A7BA8")
    }

    private enum Legal {
        static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
        // Replace with Mito's hosted privacy policy before App Store submission.
        static let privacy = URL(string: "https://mito.study/privacy")!
    }

    private var selectedPackage: Package? {
        selectedPlan == .yearly ? subscriptions.yearlyPackage : subscriptions.monthlyPackage
    }

    var body: some View {
        ZStack {
            Palette.panel.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    introPanel
                    benefitsPanel
                    plans
                    purchaseButton
                    restoreButton
                    legalFooter
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .alert(
            "Could not complete purchase",
            isPresented: Binding(
                get: { subscriptions.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        subscriptions.clearError()
                    }
                }
            )
        ) {
            Button("OK") {
                subscriptions.clearError()
            }
        } message: {
            Text(subscriptions.errorMessage ?? "Please try again.")
        }
        .task { await MitoBackend.shared.logEvent("paywall_viewed") }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 7) {
                Text("MITO PRO")
                    .font(.custom(MitoFont.micro, size: 14))
                    .foregroundStyle(Palette.gold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Palette.brightGold)
                    .overlay(pixelBorder)

                Text("STUDY TOGETHER.\nGO UNLIMITED.")
                    .font(.custom(MitoFont.bold, size: 24).weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)

                Text("Friends, your friends list, and the weekly focus league stay free. Pro is for studying together live, plus unlimited decks and classes.")
                    .paywallBody(size: 15, color: Palette.bark)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)

            Button {
                dismiss()
            } label: {
                Text("X")
                    .font(.custom(MitoFont.micro, size: 13))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 38, height: 38)
                    .background(Palette.innerPanel)
                    .overlay(pixelBorder)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var introPanel: some View {
        VStack(spacing: 4) {
            Text(yearlyTrialHeadline)
                .font(.custom(MitoFont.bold, size: 17).weight(.bold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)

            Text("Cancel anytime in App Store settings.")
                .paywallBody(size: 13, color: Palette.bark)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Palette.brightGold)
        .overlay(pixelBorder)
    }

    private var benefitsPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("WHAT PRO ADDS")
                .font(.custom(MitoFont.micro, size: 11))
                .foregroundStyle(Palette.ink)

            benefit("Unlimited decks", detail: "The free plan keeps up to 5 decks at once.")
            benefit("Co-op focus sessions", detail: "Study live with friends in your meadow.")
            benefit("Shared endless runs", detail: "Keep a run going together.")
            benefit("PvP deck duels", detail: "Answer the same deck head-to-head.")
            benefit("Unlimited classes", detail: "Create and join as many study groups as you need.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.innerPanel)
        .overlay(pixelBorder)
    }

    private func benefit(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("+")
                .font(.custom(MitoFont.micro, size: 13))
                .foregroundStyle(Palette.green)
                .frame(width: 18, height: 18)
                .overlay(Rectangle().stroke(Palette.green, lineWidth: 2))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .paywallBody(size: 15, color: Palette.ink, weight: .bold)
                Text(detail)
                    .paywallBody(size: 13, color: Palette.bark)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var plans: some View {
        VStack(spacing: 10) {
            planButton(
                plan: .yearly,
                title: "YEARLY",
                price: yearlyPrice,
                detail: yearlyPlanDetail,
                badge: "BEST VALUE"
            )

            planButton(
                plan: .monthly,
                title: "MONTHLY",
                price: monthlyPrice,
                detail: "Billed monthly.",
                badge: nil
            )
        }
    }

    private func planButton(
        plan: Plan,
        title: String,
        price: String,
        detail: String,
        badge: String?
    ) -> some View {
        let selected = selectedPlan == plan

        return Button {
            selectedPlan = plan
            Haptics.select()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle()
                        .fill(selected ? Palette.green : Palette.innerPanel)
                        .frame(width: 24, height: 24)
                        .overlay(Rectangle().stroke(Palette.outline, lineWidth: 3))

                    if selected {
                        Text("X")
                            .font(.custom(MitoFont.micro, size: 10))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.custom(MitoFont.micro, size: 11))
                            .foregroundStyle(Palette.ink)

                        if let badge {
                            Text(badge)
                                .font(.custom(MitoFont.micro, size: 8))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Palette.brightGold)
                                .overlay(Rectangle().stroke(Palette.outline, lineWidth: 2))
                        }
                    }

                    Text(detail)
                        .paywallBody(size: 13, color: Palette.bark)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)

                Text(price)
                    .paywallBody(size: 16, color: selected ? Palette.green : Palette.ink, weight: .bold)
                    .multilineTextAlignment(.trailing)
            }
            .padding(13)
            .frame(maxWidth: .infinity)
            .background(selected ? Palette.brightGold.opacity(0.32) : Palette.innerPanel)
            .overlay(Rectangle().stroke(selected ? Palette.gold : Palette.outline, lineWidth: selected ? 4 : 3))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var purchaseButton: some View {
        Button {
            guard let selectedPackage else { return }
            Task {
                if await subscriptions.purchase(selectedPackage) {
                    Haptics.success()
                    dismiss()
                }
            }
        } label: {
            ZStack {
                Text(purchaseButtonTitle)
                    .font(.custom(MitoFont.bold, size: 16).weight(.bold))
                    .foregroundStyle(.white)
                    .opacity(subscriptions.isLoading ? 0 : 1)

                if subscriptions.isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(selectedPackage == nil ? Palette.bark : Palette.green)
            .overlay(pixelBorder)
        }
        .buttonStyle(.plain)
        .disabled(selectedPackage == nil || subscriptions.isLoading)
        .accessibilityHint("Purchases the selected Mito Pro plan")
    }

    private var restoreButton: some View {
        Button {
            Task {
                if await subscriptions.restorePurchases() {
                    Haptics.success()
                    dismiss()
                }
            }
        } label: {
            Text("Restore purchases")
                .paywallBody(size: 14, color: Palette.blue, weight: .bold)
                .underline()
        }
        .buttonStyle(.plain)
        .disabled(subscriptions.isLoading)
    }

    private var legalFooter: some View {
        VStack(spacing: 9) {
            Text("Payment is charged to your Apple ID. The subscription renews automatically unless cancelled at least 24 hours before the period ends. Manage or cancel it in App Store settings.")
                .paywallBody(size: 11, color: Palette.bark)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Link("Terms of Use (EULA)", destination: Legal.terms)
                Link("Privacy Policy", destination: Legal.privacy)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.blue)
            .underline()
        }
        .padding(.horizontal, 8)
    }

    private var yearlyPrice: String {
        subscriptions.yearlyPackage?.storeProduct.localizedPriceString ?? "$29.99 / year"
    }

    private var monthlyPrice: String {
        subscriptions.monthlyPackage?.storeProduct.localizedPriceString ?? "$4.99 / month"
    }

    private var yearlyTrialHeadline: String {
        guard let discount = subscriptions.yearlyPackage?.storeProduct.introductoryDiscount,
              discount.paymentMode == .freeTrial else {
            return "7 days free, then \(yearlyPrice)"
        }

        return "\(trialPeriodText(discount.subscriptionPeriod)) free, then \(yearlyPrice)"
    }

    private var yearlyPlanDetail: String {
        "About \(monthlyEquivalentPrice) a month. Roughly 50% less than monthly."
    }

    private var monthlyEquivalentPrice: String {
        guard let package = subscriptions.yearlyPackage else { return "$2.50" }
        let monthlyAmount = package.storeProduct.price / Decimal(12)
        return monthlyAmount.formatted(
            .currency(code: package.storeProduct.currencyCode ?? "USD")
                .precision(.fractionLength(2))
        )
    }

    private var purchaseButtonTitle: String {
        switch selectedPlan {
        case .yearly:
            return "START FREE TRIAL"
        case .monthly:
            return "CHOOSE MONTHLY"
        }
    }

    private func trialPeriodText(_ period: SubscriptionPeriod) -> String {
        let value = period.value
        let unit: String

        switch period.unit {
        case .day:
            unit = value == 1 ? "day" : "days"
        case .week:
            unit = value == 1 ? "week" : "weeks"
        case .month:
            unit = value == 1 ? "month" : "months"
        case .year:
            unit = value == 1 ? "year" : "years"
        @unknown default:
            unit = "days"
        }

        return "\(value) \(unit)"
    }

    private var pixelBorder: some View {
        Rectangle().stroke(Palette.outline, lineWidth: 3)
    }
}

private extension Text {
    func paywallBody(
        size: CGFloat,
        color: Color,
        weight: Font.Weight = .regular
    ) -> some View {
        font(.system(size: size, weight: weight, design: .rounded))
            .foregroundStyle(color)
    }
}
