import SwiftUI
import RevenueCat
import RevenueCatUI

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    static let entitlementID = "Mito Pro"
    static let yearlyProductID = "yearly"
    static let monthlyProductID = "monthly"

    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private static var apiKey: String {
        #if DEBUG
        return "test_PggeodRFUlqMaWqfShppOiuuFXI"
        #else
        return Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""
        #endif
    }

    private var customerInfoTask: Task<Void, Never>?
    private var hasConfigured = false

    var isConfigured: Bool { hasConfigured }

    var isPro: Bool {
        customerInfo?.entitlements[Self.entitlementID]?.isActive == true
    }

    var yearlyPackage: Package? {
        currentOffering?.availablePackages.first {
            $0.identifier == "$rc_annual"
                || $0.storeProduct.productIdentifier == Self.yearlyProductID
        }
    }

    var monthlyPackage: Package? {
        currentOffering?.availablePackages.first {
            $0.identifier == "$rc_monthly"
                || $0.storeProduct.productIdentifier == Self.monthlyProductID
        }
    }

    private init() {}

    func configure() {
        guard !hasConfigured else { return }
        let key = Self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "Add the production RevenueCat iOS API key to REVENUECAT_API_KEY before releasing."
            return
        }
        hasConfigured = true

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif

        Purchases.configure(withAPIKey: key)
        observeCustomerInfo()

        Task {
            await refresh()
        }
    }

    func refresh() async {
        guard requireConfiguration() else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let infoRequest = Purchases.shared.customerInfo()
            async let offeringsRequest = Purchases.shared.offerings()
            customerInfo = try await infoRequest
            currentOffering = try await offeringsRequest.current
            #if DEBUG
            if let currentOffering {
                let products = currentOffering.availablePackages
                    .map(\.storeProduct.productIdentifier)
                    .joined(separator: ", ")
                print("RevenueCat offering \(currentOffering.identifier): \(products)")
            } else {
                print("RevenueCat has no current offering. Configure and publish one in the dashboard.")
            }
            #endif
        } catch {
            handle(error)
        }
    }

    @discardableResult
    func purchase(_ package: Package) async -> Bool {
        guard requireConfiguration() else { return false }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            customerInfo = result.customerInfo
            return isPro
        } catch {
            if (error as NSError).asErrorCode == .purchaseCancelledError {
                return false
            }
            handle(error)
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        guard requireConfiguration() else { return false }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            customerInfo = try await Purchases.shared.restorePurchases()
            return isPro
        } catch {
            handle(error)
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func updateCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
        errorMessage = nil
    }

    func logIn(appUserID: String) async {
        guard requireConfiguration(), !appUserID.isEmpty else { return }
        do {
            let result = try await Purchases.shared.logIn(appUserID)
            customerInfo = result.customerInfo
        } catch {
            handle(error)
        }
    }

    private func observeCustomerInfo() {
        customerInfoTask?.cancel()
        customerInfoTask = Task { [weak self] in
            guard let self else { return }
            for await info in Purchases.shared.customerInfoStream {
                guard !Task.isCancelled else { return }
                self.customerInfo = info
            }
        }
    }

    private func handle(_ error: Error) {
        errorMessage = error.localizedDescription
        #if DEBUG
        print("RevenueCat error: \(error)")
        #endif
    }

    private func requireConfiguration() -> Bool {
        guard hasConfigured else {
            errorMessage = "RevenueCat is not configured for this build."
            return false
        }
        return true
    }
}

struct MitoPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptions = SubscriptionManager.shared

    var body: some View {
        Group {
            if subscriptions.isConfigured {
                PaywallView(displayCloseButton: true)
                    .onPurchaseCompleted { info in
                        subscriptions.updateCustomerInfo(info)
                        if subscriptions.isPro {
                            Haptics.success()
                            dismiss()
                        }
                    }
                    .onRestoreCompleted { info in
                        subscriptions.updateCustomerInfo(info)
                        if subscriptions.isPro {
                            Haptics.success()
                            dismiss()
                        }
                    }
                    .onPurchaseFailure { error in
                        subscriptions.report(error)
                    }
                    .onRestoreFailure { error in
                        subscriptions.report(error)
                    }
            } else {
                ContentUnavailableView(
                    "Subscriptions unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(subscriptions.errorMessage ?? "RevenueCat is not configured.")
                )
                .padding()
            }
        }
    }
}

struct MitoCustomerCenterView: View {
    @ObservedObject private var subscriptions = SubscriptionManager.shared

    var body: some View {
        CustomerCenterView()
            .onCustomerCenterRestoreCompleted { info in
                subscriptions.updateCustomerInfo(info)
            }
            .onCustomerCenterRestoreFailed { error in
                subscriptions.report(error)
            }
    }
}

extension SubscriptionManager {
    func report(_ error: Error) {
        handle(error)
    }
}
