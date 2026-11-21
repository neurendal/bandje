// SPDX-License-Identifier: GPL-3.0-only
import BandjeKit
import StoreKit
import SwiftUI

/// Freemium on the iPhone (specs/purchase.md): the paywall sheet, the Settings section and the
/// short lines under the Transcribe button. The rules and StoreKit live in BandjeKit (`Purchases`).
/// The iPhone shows only Band·je Onbeperkt: dictation is a Mac feature (Restore covers both).
enum Store {
    /// What Settings says about the purchase.
    enum Status: Equatable {
        case free(left: Int)
        /// Band·je Onbeperkt bought (or shared by the family).
        case bought
        /// Bought Band·je before it was free.
        case existing
        /// Not known yet (the App Store could not be read): unlocked until it is (benefit of the doubt).
        case unlocked
    }

    @MainActor static func status(_ p: Purchases) -> Status {
        switch p.override {
        case .existing: return .existing
        case .unlimited: return .bought
        case .free, .used, .dictation: return .free(left: p.transcriptionsLeft)
        case nil: break
        }
        if p.ownsUnlimited { return .bought }
        if p.existingCustomer == true { return .existing }
        return p.hasUnlimited ? .unlocked : .free(left: p.transcriptionsLeft)
    }

    /// Runs a buy or restore from a view: `busy` while it runs, a failure in `message`.
    @MainActor static func run(busy: Binding<Bool>, message: Binding<String?>, _ work: @escaping @MainActor () async throws -> Void) {
        busy.wrappedValue = true
        message.wrappedValue = nil
        Task {
            defer { busy.wrappedValue = false }
            do {
                try await work()
            } catch {
                message.wrappedValue = error.localizedDescription
            }
        }
    }

    /// Buys `product` with SwiftUI's purchase action (it knows the window). True when bought.
    @MainActor static func buy(_ product: Product, with purchase: PurchaseAction) async throws -> Bool {
        let result = try await purchase(product)
        return await Purchases.shared.handle(result)
    }
}

/// The paywall: shown only when a transcription would start after the free ones are used.
/// Calm and short; the price only from StoreKit.
struct PaywallView: View {
    /// Called once Band·je Onbeperkt is unlocked (bought, approved or restored), after the sheet closed.
    var onUnlocked: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    private let purchases = Purchases.shared
    @State private var busy = false
    @State private var message: String?

    private var product: Product? { purchases.product(.unlimited) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    CassetteView(state: CassetteState(title: "Band·je"))
                        .frame(width: 170)
                        .accessibilityHidden(true)
                        .padding(.top, 8)
                    // In the app's language, like the lines below (StoreKit's name follows the
                    // storefront, which may be another language).
                    Text("Band·je Unlimited")
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 16) {
                        point("text.quote", "Transcribe as many recordings as you want.")
                        point("checkmark.seal", "One payment, no subscription.")
                        point("lock", "Everything stays on your \(Device.name).")
                        point("mic", "Recording stays free, and what you made stays yours.")
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                    if purchases.pending {
                        Label("Waiting for approval", systemImage: "hourglass")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("paywallPending")
                    }
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Short content sits in the middle, not under the close button with a gap below.
            .defaultScrollAnchor(.center, for: .alignment)
            .safeAreaInset(edge: .bottom) { buttons }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("paywallClose")
                }
            }
        }
        .presentationSizing(.form)
        .onChange(of: purchases.hasUnlimited) { _, unlocked in
            // Bought here, approved (Ask to Buy), restored, or bought on another device meanwhile.
            if unlocked { done() }
        }
        .task { await purchases.loadProducts() }
    }

    private var buttons: some View {
        VStack(spacing: 6) {
            Button {
                guard let product else { return }
                run { _ = try await Store.buy(product, with: purchase) }
            } label: {
                Group {
                    if let product {
                        Text("Buy for \(product.displayPrice)")
                    } else {
                        ProgressView()
                    }
                }
                .font(.headline)
                .frame(maxWidth: 420)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color("ButtonAccent"))
            .controlSize(.large)
            .disabled(product == nil || busy || purchases.pending)
            .accessibilityIdentifier("paywallBuy")
            Button("Restore Purchases") {
                run {
                    try await purchases.restore()
                    if !purchases.hasUnlimited { message = String(localized: "No purchase to restore was found.") }
                }
            }
            .controlSize(.large)
            .disabled(busy)
            .accessibilityIdentifier("paywallRestore")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        Store.run(busy: $busy, message: $message, work)
    }

    private func done() {
        dismiss()
        onUnlocked()
    }

    private func point(_ icon: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color("ButtonAccent"))
                .frame(width: 28)
        }
    }
}

/// Settings › Band·je Onbeperkt: what is unlocked, the product with its price, Restore Purchases
/// (App Review: always reachable) and Redeem Code.
struct PurchaseSection: View {
    @Environment(\.purchase) private var purchase
    private let purchases = Purchases.shared
    @State private var busy = false
    @State private var message: String?
    @State private var redeeming = false

    var body: some View {
        let status = Store.status(purchases)
        Section {
            statusLine(status)
            if status != .existing && status != .unlocked {
                productRow(owned: status == .bought)
            }
            Button("Restore Purchases") {
                run {
                    try await purchases.restore()
                    if !purchases.hasUnlimited { message = String(localized: "No purchase to restore was found.") }
                }
            }
            .disabled(busy)
            .accessibilityIdentifier("settingsRestore")
            Button("Redeem Code…") { redeeming = true }
                .accessibilityIdentifier("settingsRedeem")
            if purchases.pending {
                Label("Waiting for approval", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Band·je Unlimited")
        } footer: {
            Text("One payment, no subscription. For your iPhone, iPad and Mac, and shared with your family. Recording is always free.")
        }
        .offerCodeRedemption(isPresented: $redeeming) { _ in
            Task { await purchases.refresh() }
        }
        .task { await purchases.loadProducts() }
    }

    @ViewBuilder private func statusLine(_ status: Store.Status) -> some View {
        switch status {
        case .free(let left):
            Group {
                if left > 0 { Text(FreeLine.left(left)) } else { Text("Free transcriptions used up.") }
            }
            .accessibilityIdentifier("purchaseStatus")
        case .bought:
            Label("Unlocked. Thank you!", systemImage: "heart.fill")
                .accessibilityIdentifier("purchaseStatus")
        case .existing:
            Label("You bought Band·je before it was free: everything is unlocked.", systemImage: "heart.fill")
                .accessibilityIdentifier("purchaseStatus")
        case .unlocked:
            Label("Everything is unlocked.", systemImage: "checkmark.circle")
                .accessibilityIdentifier("purchaseStatus")
        }
    }

    private func productRow(owned: Bool) -> some View {
        let product = purchases.product(.unlimited)
        return HStack(alignment: .center, spacing: 12) {
            // Our name, in the app's language (StoreKit's follows the storefront's).
            Text(String(localized: "Band·je Unlimited"))
                .font(.body.weight(.medium))
            Spacer(minLength: 8)
            if owned {
                Label("Purchased", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let product {
                Button(product.displayPrice) {
                    run { _ = try await Store.buy(product, with: purchase) }
                }
                .buttonStyle(.glassProminent)
                .tint(Color("ButtonAccent"))
                .disabled(busy || purchases.pending)
                .accessibilityLabel(Text("Buy for \(product.displayPrice)"))
                .accessibilityIdentifier("settingsBuy")
            } else {
                ProgressView()
            }
        }
        .padding(.vertical, 2)
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        Store.run(busy: $busy, message: $message, work)
    }
}

/// The short lines under the Transcribe button while nothing is unlocked: how many free
/// transcriptions are left, or that they are used (with the way to the paywall). Nothing else on
/// screen before the limit (specs/purchase.md).
struct FreeLine: View {
    /// This recording may be transcribed now.
    let mayTranscribe: Bool
    let showPaywall: () -> Void
    private let purchases = Purchases.shared

    static func left(_ left: Int) -> String {
        String(localized: "\(left) of \(FreeAllowance.transcriptions) free transcriptions left")
    }

    var body: some View {
        if !purchases.hasUnlimited {
            if !mayTranscribe {
                VStack(spacing: 4) {
                    Text("Free transcriptions used up.")
                        .foregroundStyle(.secondary)
                    Button("Band·je Unlimited…", action: showPaywall)
                        .accessibilityIdentifier("freeLinePaywall")
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("freeLineUsed")
            } else if purchases.transcriptionsLeft > 0 {
                Text(Self.left(purchases.transcriptionsLeft))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("freeLineLeft")
            }
        }
    }
}
