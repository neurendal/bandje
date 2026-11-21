// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation
import os
import Security
import StoreKit

/// Freemium (specs/purchase.md, owner 2026-11-11): recording is always free; transcribing is free
/// for 5 recordings and dictation (Mac) for 15 minutes; two one-time purchases unlock the rest.
/// Band·je Onbeperkt unlocks both, Band·je Dicteren only dictation. Everyone who bought Band·je
/// before the free version keeps everything. StoreKit 2 only: its traffic is the system's, there
/// is no server of ours.
public enum BandjeProduct: String, CaseIterable, Sendable {
    case unlimited = "com.neurendal.bandje.unlimited"
    case dictation = "com.neurendal.bandje.dictation"
}

/// What the free version allows.
public enum FreeAllowance {
    /// Free transcriptions: one per recording (owner 2026-11-12: 5, was 3).
    public static let transcriptions = 5
    /// Free dictation in total (Mac; owner 2026-11-12: 15 minutes, dictated prompts are short).
    public static let dictationSeconds: Double = 15 * 60
    /// After this much free dictation the Mac says once how much is left (owner 2026-11-12).
    public static let dictationWarnSeconds: Double = 10 * 60
}

/// What this device used of the free allowance. Kept in the Keychain (survives reinstalling),
/// per device, not synced.
public struct FreeUsage: Codable, Equatable, Sendable {
    /// The recordings whose first transcription finished (their `RecordingKey`), each counted once.
    public var transcribed: [String] = []
    /// Seconds of dictated audio.
    public var dictationSeconds: Double = 0

    public init(transcribed: [String] = [], dictationSeconds: Double = 0) {
        self.transcribed = transcribed
        self.dictationSeconds = dictationSeconds
    }
}

/// The rules, without StoreKit (unit tested).
public enum PurchaseRules {
    /// The first build numbers of the free version: iOS uses `CFBundleVersion` (our builds are
    /// `yyyyMMdd.HHmm`; every 1.1.0 upload is made after 2026-11-12 00:00), the Mac
    /// `CFBundleShortVersionString` (`1.1.0`). `AppTransaction.originalAppVersion` is the one or the other.
    public static let firstFreeBuild: Double = 20261112
    public static let firstFreeVersion = [1, 1, 0]
    /// The day the app's price went to free: bought before it is an existing customer, whatever
    /// `originalAppVersion` says. Nil until the owner sets it (the release day, specs/purchase.md).
    public static let freeSince: Date? = nil

    /// Bought Band·je before it was free: `originalAppVersion` older than the free version, or
    /// bought before `freeSince` (the day the price went to free; nil until it is set).
    public static func isExistingCustomer(originalAppVersion: String, originalPurchaseDate: Date,
                                          freeSince: Date? = nil) -> Bool {
        if let freeSince, originalPurchaseDate < freeSince { return true }
        let v = originalAppVersion.trimmingCharacters(in: .whitespaces)
        let parts = v.split(separator: ".").map { Int($0) }
        guard let first = parts.first ?? nil else { return false }
        if first >= 10_000 {
            // A build number (iOS): 20261108.0231.
            guard let build = Double(v) else { return false }
            return build < firstFreeBuild
        }
        // A version (Mac): 1.0.0, 1.0.
        let numbers = parts.map { $0 ?? 0 }
        for i in 0..<3 {
            let a = i < numbers.count ? numbers[i] : 0
            let b = firstFreeVersion[i]
            if a != b { return a < b }
        }
        return false
    }

    public static func transcriptionsLeft(_ usage: FreeUsage) -> Int {
        max(0, FreeAllowance.transcriptions - Set(usage.transcribed).count)
    }

    /// May the recording `key` be transcribed: unlocked, already counted, or free ones left.
    public static func mayTranscribe(_ key: String, unlocked: Bool, usage: FreeUsage) -> Bool {
        unlocked || usage.transcribed.contains(key) || transcriptionsLeft(usage) > 0
    }

    /// The usage after the first transcription of `key` finished (a recording counts once).
    public static func counting(_ key: String, in usage: FreeUsage) -> FreeUsage {
        guard !usage.transcribed.contains(key) else { return usage }
        var u = usage
        u.transcribed.append(key)
        return u
    }

    public static func dictationSecondsLeft(_ usage: FreeUsage) -> Double {
        max(0, FreeAllowance.dictationSeconds - usage.dictationSeconds)
    }

    /// May a dictation start. One that runs when the minutes run out finishes normally.
    public static func mayDictate(unlocked: Bool, usage: FreeUsage) -> Bool {
        unlocked || dictationSecondsLeft(usage) > 0
    }

    /// A dictation took the used seconds from `before` to `after` past the warning point
    /// (`FreeAllowance.dictationWarnSeconds`). Usage only grows, so this is true once per device.
    /// Whether dictation is unlocked is the caller's concern.
    public static func crossesDictationWarning(before: Double, after: Double) -> Bool {
        before < FreeAllowance.dictationWarnSeconds && after >= FreeAllowance.dictationWarnSeconds
    }

    /// The key of a recording: its creation date in `.bandje.json` (the same on every device and
    /// after a rename, specs/icloud-sync.md), else its folder name. Whole seconds rounded down,
    /// as `RecordingID`.
    public static func recordingKey(created: Date?, folderName: String) -> String {
        if let created { return "c" + String(Int(created.timeIntervalSince1970.rounded(.down))) }
        return "f" + folderName
    }
}

/// Where `FreeUsage` is kept.
public protocol FreeUsageStorage: Sendable {
    func load() -> FreeUsage?
    func save(_ usage: FreeUsage)
}

/// The Keychain: a generic password, this device only (not synced), readable after the first
/// unlock (transcription in the background). On the Mac the data protection Keychain (as on iOS;
/// it needs the app's application identifier, so an unsigned or ad-hoc build can't read it).
/// After a read that failed for any reason but "not there", nothing is written for the rest of
/// the process: a usage that could not be read is never overwritten with a fresh one.
public final class KeychainUsageStorage: FreeUsageStorage, @unchecked Sendable {
    /// The Security calls, replaceable in tests (the test runner has no Keychain entitlement).
    struct Calls: Sendable {
        var copy: @Sendable (_ query: [String: Any]) -> (OSStatus, Data?)
        var update: @Sendable (_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
        var add: @Sendable (_ attributes: [String: Any]) -> OSStatus

        static let system = Calls(
            copy: { query in
                var out: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &out)
                return (status, out as? Data)
            },
            update: { query, attributes in SecItemUpdate(query as CFDictionary, attributes as CFDictionary) },
            add: { attributes in SecItemAdd(attributes as CFDictionary, nil) })
    }

    private enum ReadState { case notRead, readable, failed }

    let service: String
    let account = "usage"
    private let calls: Calls
    private let lock = NSLock()
    private var state = ReadState.notRead
    private static let log = Logger(subsystem: "com.neurendal.bandje", category: "purchases")

    public convenience init(service: String = "com.neurendal.bandje.free") {
        self.init(service: service, calls: .system)
    }

    init(service: String, calls: Calls) {
        self.service = service
        self.calls = calls
    }

    private var query: [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecAttrSynchronizable as String: false]
        #if os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }

    public func load() -> FreeUsage? {
        lock.withLock { read() }
    }

    private func read() -> FreeUsage? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = calls.copy(q)
        switch status {
        case errSecSuccess:
            if let data, let usage = try? JSONDecoder().decode(FreeUsage.self, from: data) {
                state = .readable
                return usage
            }
            Self.log.error("Free usage in the Keychain can't be decoded; it is left as it is")
            state = .failed
        case errSecItemNotFound:
            state = .readable
        default:
            Self.log.error("Free usage can't be read from the Keychain (\(status, privacy: .public)); it is left as it is")
            state = .failed
        }
        return nil
    }

    public func save(_ usage: FreeUsage) {
        lock.withLock {
            if state == .notRead { _ = read() }
            guard state == .readable else { return }
            guard let data = try? JSONEncoder().encode(usage) else { return }
            let status = calls.update(query, [kSecValueData as String: data])
            switch status {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                var add = query
                add[kSecValueData as String] = data
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                let added = calls.add(add)
                if added != errSecSuccess {
                    Self.log.error("Free usage can't be added to the Keychain (\(added, privacy: .public))")
                }
            default:
                Self.log.error("Free usage can't be updated in the Keychain (\(status, privacy: .public))")
            }
        }
    }
}

/// In memory (tests, previews).
public final class MemoryUsageStorage: FreeUsageStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var usage: FreeUsage?
    public init(_ usage: FreeUsage? = nil) { self.usage = usage }
    public func load() -> FreeUsage? { lock.withLock { usage } }
    public func save(_ usage: FreeUsage) { lock.withLock { self.usage = usage } }
}

/// The app's purchases: products, what is unlocked, the free usage. One per app (`shared`).
@MainActor @Observable
public final class Purchases {
    public static let shared = Purchases(storage: KeychainUsageStorage())
    private static let log = Logger(subsystem: "com.neurendal.bandje", category: "purchases")

    /// For screenshots and the selftest (DEBUG builds of the apps set it; never in release).
    public enum Override: String, Sendable {
        /// Nothing bought, nothing used: starts from an empty usage (kept in memory only).
        case free
        /// Nothing bought, the free transcriptions and dictation minutes used up.
        case used
        /// Band·je Onbeperkt bought.
        case unlimited
        /// Only Band·je Dicteren bought.
        case dictation
        /// Bought before the free version.
        case existing
    }

    /// The products, Onbeperkt first; empty until loaded (or when the App Store can't be reached).
    public private(set) var products: [Product] = []
    public private(set) var ownsUnlimited = false
    public private(set) var ownsDictation = false
    /// Bought before the free version. Nil: not known yet (or could not be read): then treated as
    /// yes, so a paying customer never sees a paywall by mistake (specs/purchase.md).
    public private(set) var existingCustomer: Bool?
    public private(set) var usage: FreeUsage
    /// A purchase waits for approval (Ask to Buy) or for the bank.
    public var pending: Bool { !pendingPurchases.isEmpty }
    /// Pending purchases by product id (`unknownProduct` when the caller did not say which), with
    /// when they were reported. StoreKit says nothing when Ask to Buy is declined: `refresh()`
    /// forgets one older than `pendingGrace`, `refreshEntitlements()` one that is now owned.
    private(set) var pendingPurchases: [String: Date] = [:]
    static let unknownProduct = "?"
    /// Long enough that the app coming back to the front right after the purchase sheet does not
    /// clear the purchase it just reported as pending.
    static let pendingGrace: TimeInterval = 60
    /// The clock for `pendingPurchases` (tests pass their own).
    @ObservationIgnored var now: () -> Date = { Date() }
    public private(set) var override: Override?

    private let storage: FreeUsageStorage
    private var updates: Task<Void, Never>?
    private var started = false
    /// The latest `refreshEntitlements()`; an older run that finishes later is dropped.
    @ObservationIgnored private var entitlementsGeneration = 0

    public init(storage: FreeUsageStorage) {
        self.storage = storage
        usage = storage.load() ?? FreeUsage()
    }

    // MARK: State

    /// Transcribing without limit.
    public var hasUnlimited: Bool {
        switch override {
        case .unlimited, .existing: return true
        case .free, .used, .dictation: return false
        case nil: return ownsUnlimited || existingCustomer != false
        }
    }

    /// Dictating without limit (Onbeperkt includes dictation, owner 2026-11-11).
    public var hasDictation: Bool {
        if override == .dictation { return true }
        if override != nil { return hasUnlimited }
        return hasUnlimited || ownsDictation
    }

    public var transcriptionsLeft: Int {
        override == .used ? 0 : PurchaseRules.transcriptionsLeft(usage)
    }

    public var dictationSecondsLeft: Double {
        override == .used ? 0 : PurchaseRules.dictationSecondsLeft(usage)
    }

    public func mayTranscribe(_ key: String) -> Bool {
        if override == .used { return hasUnlimited || usage.transcribed.contains(key) }
        return PurchaseRules.mayTranscribe(key, unlocked: hasUnlimited, usage: usage)
    }

    public var mayDictate: Bool {
        hasDictation || dictationSecondsLeft > 0
    }

    /// Tests only.
    func setExistingCustomerForTesting(_ value: Bool) { existingCustomer = value }

    public func product(_ id: BandjeProduct) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    // MARK: Counting

    /// Known to transcribe without limit. Unlike `hasUnlimited`, an unknown `existingCustomer`
    /// counts as no: the free usage is still counted while it is unknown, so a new user's
    /// transcriptions during the first launch (offline) are not lost.
    private var knownUnlimited: Bool {
        switch override {
        case .unlimited, .existing: return true
        case .free, .used, .dictation: return false
        case nil: return ownsUnlimited || existingCustomer == true
        }
    }

    private var knownDictation: Bool {
        switch override {
        case .dictation: return true
        case nil: return knownUnlimited || ownsDictation
        default: return knownUnlimited
        }
    }

    /// A recording's first transcription finished.
    public func noteTranscribed(_ key: String) {
        guard !knownUnlimited else { return }
        let next = PurchaseRules.counting(key, in: usage)
        guard next != usage else { return }
        usage = next
        save()
    }

    /// A dictation of `seconds` finished. Returns true when it just used up the free dictation
    /// up to the warning point (`FreeAllowance.dictationWarnSeconds`) and dictation is not
    /// unlocked: the Mac then says once how many free minutes are left.
    @discardableResult
    public func noteDictated(_ seconds: Double) -> Bool {
        guard !knownDictation, seconds > 0 else { return false }
        let before = usage.dictationSeconds
        usage.dictationSeconds += seconds
        save()
        return !hasDictation && PurchaseRules.crossesDictationWarning(before: before, after: usage.dictationSeconds)
    }

    /// Kept in the Keychain, except with an override (a DEBUG build, differently signed: its
    /// Keychain item would make the App Store build ask for Keychain access later).
    private func save() {
        guard override == nil else { return }
        storage.save(usage)
    }

    // MARK: StoreKit

    /// At launch: listen for transactions (other devices, Ask to Buy, refunds), then look up what
    /// is owned, the products and whether this is an existing customer.
    public func start(override: Override? = nil) {
        let previous = self.override
        self.override = override
        if override == .free {
            usage = FreeUsage()
        } else if override == nil, previous != nil {
            // Back from an override: its usage was never saved; take the kept one again.
            usage = storage.load() ?? FreeUsage()
        }
        guard !started else { return }
        started = true
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task { await refresh() }
    }

    /// Everything again (at launch, when the app comes to the front, after Restore).
    public func refresh() async {
        forgetStalePending()
        await refreshEntitlements()
        // With an override (DEBUG builds, tests) AppTransaction is not asked: on a simulator it
        // can bring up the Apple Account sign-in and hang a test run.
        if override == nil { await checkExistingCustomer() }
        await loadProducts()
    }

    public func loadProducts() async {
        guard products.isEmpty else { return }
        let ids = BandjeProduct.allCases.map(\.rawValue)
        guard let loaded = try? await Product.products(for: ids) else { return }
        products = loaded.sorted { a, b in (ids.firstIndex(of: a.id) ?? 9) < (ids.firstIndex(of: b.id) ?? 9) }
    }

    public func refreshEntitlements() async {
        let generation = beginEntitlements()
        var unlimited = false, dictation = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            switch BandjeProduct(rawValue: t.productID) {
            case .unlimited: unlimited = true
            case .dictation: dictation = true
            case nil: break
            }
        }
        applyEntitlements(unlimited: unlimited, dictation: dictation, generation: generation)
    }

    func beginEntitlements() -> Int {
        entitlementsGeneration += 1
        return entitlementsGeneration
    }

    /// The result of a `refreshEntitlements()` run, unless a newer run started meanwhile.
    func applyEntitlements(unlimited: Bool, dictation: Bool, generation: Int) {
        guard generation == entitlementsGeneration else { return }
        ownsUnlimited = unlimited
        ownsDictation = dictation
        if unlimited {
            pendingPurchases = [:]
        } else if dictation {
            pendingPurchases[BandjeProduct.dictation.rawValue] = nil
            pendingPurchases[Self.unknownProduct] = nil
        }
    }

    func notePending(_ product: BandjeProduct?) {
        pendingPurchases[product?.rawValue ?? Self.unknownProduct] = now()
    }

    /// A declined Ask to Buy is never reported: a pending purchase not re-reported within
    /// `pendingGrace` is forgotten when the app comes back. An approval arrives later through
    /// `Transaction.updates` all the same.
    func forgetStalePending() {
        let limit = now().addingTimeInterval(-Self.pendingGrace)
        pendingPurchases = pendingPurchases.filter { $0.value > limit }
    }

    /// Reads `AppTransaction`: bought before the free version? Only a verified production
    /// transaction decides. The App Store's own sandbox and Xcode's StoreKit testing say "1.0" for
    /// every app: there it is never an existing customer, so the paywall can be tested. An error or
    /// an unverified transaction leaves it unknown (treated as yes) until the next check.
    public func checkExistingCustomer() async {
        if existingCustomer == true { return }
        let result: VerificationResult<AppTransaction>
        do {
            result = try await AppTransaction.shared
        } catch {
            // Unknown stays unknown (treated as unlocked); the reason goes to the log, nothing else.
            Self.log.notice("AppTransaction unreadable: \(String(describing: error), privacy: .public)")
            return
        }
        guard case .verified(let app) = result else {
            Self.log.notice("AppTransaction unverified")
            return
        }
        Self.log.info("AppTransaction: \(String(describing: app.environment), privacy: .public), original \(app.originalAppVersion, privacy: .public)")
        existingCustomer = Self.existingCustomer(environment: app.environment,
                                                 originalAppVersion: app.originalAppVersion,
                                                 originalPurchaseDate: app.originalPurchaseDate)
    }

    /// What a verified `AppTransaction` says (unit tested).
    nonisolated static func existingCustomer(environment: AppStore.Environment, originalAppVersion: String,
                                             originalPurchaseDate: Date) -> Bool {
        guard environment == .production else { return false }
        return PurchaseRules.isExistingCustomer(originalAppVersion: originalAppVersion,
                                                originalPurchaseDate: originalPurchaseDate,
                                                freeSince: PurchaseRules.freeSince)
    }

    /// After `PurchaseAction` (SwiftUI's `\.purchase`, which knows the window): true when bought.
    /// `product`: what was bought, so a pending purchase is tracked per product.
    @discardableResult
    public func handle(_ result: Product.PurchaseResult, product: BandjeProduct? = nil) async -> Bool {
        switch result {
        case .success(let verification):
            guard case .verified(let t) = verification else { return false }
            await t.finish()
            await refreshEntitlements()
            return true
        case .pending:
            notePending(product)
            return false
        case .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    /// Restore Purchases: asks the App Store (may ask to sign in), then looks again.
    public func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }
}
