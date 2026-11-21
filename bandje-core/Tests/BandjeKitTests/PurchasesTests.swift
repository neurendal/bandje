// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import BandjeKit

@Suite struct PurchaseRulesTests {
    @Test func existingCustomerByIOSBuild() {
        let d = Date()
        #expect(PurchaseRules.isExistingCustomer(originalAppVersion: "20261108.0231", originalPurchaseDate: d))
        #expect(PurchaseRules.isExistingCustomer(originalAppVersion: "20261111.1639", originalPurchaseDate: d))
        #expect(!PurchaseRules.isExistingCustomer(originalAppVersion: "20261112.0100", originalPurchaseDate: d))
        #expect(!PurchaseRules.isExistingCustomer(originalAppVersion: "20261201", originalPurchaseDate: d))
    }

    @Test func existingCustomerByMacVersion() {
        let d = Date()
        #expect(PurchaseRules.isExistingCustomer(originalAppVersion: "1.0.0", originalPurchaseDate: d))
        #expect(PurchaseRules.isExistingCustomer(originalAppVersion: "1.0", originalPurchaseDate: d))
        #expect(PurchaseRules.isExistingCustomer(originalAppVersion: "1.0.9", originalPurchaseDate: d))
        #expect(!PurchaseRules.isExistingCustomer(originalAppVersion: "1.1.0", originalPurchaseDate: d))
        #expect(!PurchaseRules.isExistingCustomer(originalAppVersion: "1.1", originalPurchaseDate: d))
        #expect(!PurchaseRules.isExistingCustomer(originalAppVersion: "1.2.0", originalPurchaseDate: d))
        #expect(!PurchaseRules.isExistingCustomer(originalAppVersion: "2.0", originalPurchaseDate: d))
    }

    @Test func existingCustomerByDateAndGarbage() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(PurchaseRules.isExistingCustomer(originalAppVersion: "1.1.0", originalPurchaseDate: day.addingTimeInterval(-1), freeSince: day))
        #expect(!PurchaseRules.isExistingCustomer(originalAppVersion: "1.1.0", originalPurchaseDate: day, freeSince: day))
        #expect(!PurchaseRules.isExistingCustomer(originalAppVersion: "", originalPurchaseDate: day))
        #expect(!PurchaseRules.isExistingCustomer(originalAppVersion: "abc", originalPurchaseDate: day))
    }

    @Test func fiveFreeTranscriptionsEachRecordingOnce() {
        #expect(FreeAllowance.transcriptions == 5)
        var u = FreeUsage()
        #expect(PurchaseRules.transcriptionsLeft(u) == 5)
        u = PurchaseRules.counting("a", in: u)
        u = PurchaseRules.counting("a", in: u)
        #expect(PurchaseRules.transcriptionsLeft(u) == 4)
        for key in ["b", "c", "d", "e"] { u = PurchaseRules.counting(key, in: u) }
        #expect(PurchaseRules.transcriptionsLeft(u) == 0)
        #expect(!PurchaseRules.mayTranscribe("f", unlocked: false, usage: u))
        // A counted recording may be transcribed again (another language, after naming speakers).
        #expect(PurchaseRules.mayTranscribe("b", unlocked: false, usage: u))
        #expect(PurchaseRules.mayTranscribe("f", unlocked: true, usage: u))
    }

    @Test func dictationNeverCountsTranscriptions() {
        var u = FreeUsage()
        u.dictationSeconds = FreeAllowance.dictationSeconds
        #expect(PurchaseRules.transcriptionsLeft(u) == FreeAllowance.transcriptions)
        #expect(!PurchaseRules.mayDictate(unlocked: false, usage: u))
        u = PurchaseRules.counting("a", in: u)
        #expect(u.dictationSeconds == FreeAllowance.dictationSeconds)
    }

    @Test func fifteenFreeDictationMinutes() {
        #expect(FreeAllowance.dictationSeconds == 15 * 60)
        var u = FreeUsage()
        #expect(PurchaseRules.mayDictate(unlocked: false, usage: u))
        #expect(PurchaseRules.dictationSecondsLeft(u) == 900)
        u.dictationSeconds = 899
        #expect(PurchaseRules.mayDictate(unlocked: false, usage: u))
        #expect(PurchaseRules.dictationSecondsLeft(u) == 1)
        u.dictationSeconds = 950
        #expect(!PurchaseRules.mayDictate(unlocked: false, usage: u))
        #expect(PurchaseRules.dictationSecondsLeft(u) == 0)
        #expect(PurchaseRules.mayDictate(unlocked: true, usage: u))
    }

    @Test func dictationWarningAtTenMinutes() {
        #expect(FreeAllowance.dictationWarnSeconds == 10 * 60)
        #expect(!PurchaseRules.crossesDictationWarning(before: 0, after: 599))
        #expect(PurchaseRules.crossesDictationWarning(before: 599, after: 600))
        #expect(PurchaseRules.crossesDictationWarning(before: 590, after: 700))
        // Past it in one long dictation, even past the end: still once.
        #expect(PurchaseRules.crossesDictationWarning(before: 0, after: 1000))
        // Already past: never again.
        #expect(!PurchaseRules.crossesDictationWarning(before: 600, after: 700))
        #expect(!PurchaseRules.crossesDictationWarning(before: 700, after: 800))
    }

    @Test func recordingKey() {
        let d = Date(timeIntervalSince1970: 1_794_000_000.4)
        #expect(PurchaseRules.recordingKey(created: d, folderName: "x") == "c1794000000")
        // Rounded down, as RecordingID: .6 past the second is still that second.
        let late = Date(timeIntervalSince1970: 1_794_000_000.6)
        #expect(PurchaseRules.recordingKey(created: late, folderName: "x") == "c1794000000")
        #expect(PurchaseRules.recordingKey(created: late, folderName: "x") == "c\(RecordingID(created: late, duration: 1).created)")
        #expect(PurchaseRules.recordingKey(created: nil, folderName: "Meeting") == "fMeeting")
    }
}

@MainActor @Suite struct PurchasesStateTests {
    @Test func countingIsKeptAndStopsWhenUnlocked() {
        let storage = MemoryUsageStorage()
        // Without start(): no StoreKit, no override.
        let p = Purchases(storage: storage)
        p.setExistingCustomerForTesting(false)
        p.noteTranscribed("a")
        p.noteTranscribed("a")
        p.noteDictated(90)
        #expect(storage.load() == FreeUsage(transcribed: ["a"], dictationSeconds: 90))
        #expect(p.transcriptionsLeft == FreeAllowance.transcriptions - 1)
        #expect(Purchases(storage: storage).usage.transcribed == ["a"])

        let paid = Purchases(storage: MemoryUsageStorage())
        paid.start(override: .unlimited)
        paid.noteTranscribed("a")
        paid.noteDictated(90)
        #expect(paid.usage == FreeUsage())
        #expect(paid.hasDictation)

        // An override (DEBUG builds) never writes the Keychain; .free starts from nothing used.
        let kept = FreeUsage(transcribed: ["x", "y"], dictationSeconds: 100)
        let debugStorage = MemoryUsageStorage(kept)
        let debug = Purchases(storage: debugStorage)
        debug.start(override: .free)
        #expect(debug.transcriptionsLeft == FreeAllowance.transcriptions)
        #expect(debug.dictationSecondsLeft == FreeAllowance.dictationSeconds)
        debug.noteTranscribed("a")
        #expect(debug.transcriptionsLeft == FreeAllowance.transcriptions - 1)
        #expect(debugStorage.load() == kept)
        // Without the override again: the kept usage, untouched.
        debug.start(override: nil)
        #expect(debug.usage == kept)
    }

    @Test func countsWhileExistingCustomerIsUnknown() {
        let storage = MemoryUsageStorage()
        let p = Purchases(storage: storage)
        #expect(p.existingCustomer == nil)
        // Unknown: benefit of the doubt for what may be done...
        #expect(p.hasUnlimited && p.hasDictation)
        #expect(p.mayTranscribe("a"))
        // ...but what was used is counted, in case it turns out to be a new customer.
        p.noteTranscribed("a")
        p.noteDictated(30)
        #expect(storage.load() == FreeUsage(transcribed: ["a"], dictationSeconds: 30))

        // A known existing customer is not counted.
        let existing = MemoryUsageStorage()
        let e = Purchases(storage: existing)
        e.setExistingCustomerForTesting(true)
        e.noteTranscribed("a")
        e.noteDictated(30)
        #expect(existing.load() == nil)
    }

    @Test func noteDictatedSaysOnceWhenTheWarningIsDue() {
        let p = Purchases(storage: MemoryUsageStorage())
        p.setExistingCustomerForTesting(false)
        #expect(!p.noteDictated(500))
        #expect(p.noteDictated(120))
        #expect(!p.noteDictated(60))
        #expect(!p.noteDictated(600))

        // Unlocked: never.
        let paid = Purchases(storage: MemoryUsageStorage())
        paid.start(override: .dictation)
        #expect(!paid.noteDictated(700))
        // Unknown whether this is an existing customer: counted, but no warning (treated as unlocked).
        let unknown = Purchases(storage: MemoryUsageStorage())
        #expect(!unknown.noteDictated(700))
        #expect(unknown.usage.dictationSeconds == 700)
    }

    @Test func dictationOverrideCountsTranscriptionsOnly() {
        let p = Purchases(storage: MemoryUsageStorage())
        p.start(override: .dictation)
        p.noteTranscribed("a")
        p.noteDictated(30)
        #expect(p.usage.transcribed == ["a"])
        #expect(p.usage.dictationSeconds == 0)
    }

    @Test func overrides() {
        let p = Purchases(storage: MemoryUsageStorage())
        p.start(override: .used)
        #expect(!p.mayTranscribe("x"))
        #expect(!p.mayDictate)
        p.start(override: .dictation)
        #expect(p.mayDictate)
        #expect(!p.hasUnlimited)
        p.start(override: .existing)
        #expect(p.hasUnlimited && p.hasDictation)
    }
}

@Suite struct ExistingCustomerCheckTests {
    @Test func onlyProductionDecides() {
        let d = Date()
        #expect(Purchases.existingCustomer(environment: .production, originalAppVersion: "1.0", originalPurchaseDate: d))
        #expect(!Purchases.existingCustomer(environment: .production, originalAppVersion: "1.1.0", originalPurchaseDate: d))
        // Sandbox and Xcode say "1.0" for everyone: never an existing customer there.
        #expect(!Purchases.existingCustomer(environment: .sandbox, originalAppVersion: "1.0", originalPurchaseDate: d))
        #expect(!Purchases.existingCustomer(environment: .xcode, originalAppVersion: "1.0", originalPurchaseDate: d))
    }
}

@MainActor @Suite struct PurchasesPendingTests {
    @Test func declinedAskToBuyIsForgottenOnRefresh() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let p = Purchases(storage: MemoryUsageStorage())
        p.now = { clock }
        p.notePending(.unlimited)
        #expect(p.pending)
        // The app comes back right after the purchase sheet: still pending.
        clock += 5
        p.forgetStalePending()
        #expect(p.pending)
        // Later (declined, or still waiting): forgotten; an approval comes through Transaction.updates.
        clock += Purchases.pendingGrace
        p.forgetStalePending()
        #expect(!p.pending)
    }

    @Test func pendingPerProduct() {
        let p = Purchases(storage: MemoryUsageStorage())
        p.notePending(.unlimited)
        p.notePending(.dictation)
        // Dictation approved: Onbeperkt still waits.
        p.applyEntitlements(unlimited: false, dictation: true, generation: p.beginEntitlements())
        #expect(p.pending)
        #expect(Set(p.pendingPurchases.keys) == [BandjeProduct.unlimited.rawValue])
        // Onbeperkt covers everything.
        p.applyEntitlements(unlimited: true, dictation: true, generation: p.beginEntitlements())
        #expect(!p.pending)
    }

    @Test func staleEntitlementsRunIsDropped() {
        let p = Purchases(storage: MemoryUsageStorage())
        let older = p.beginEntitlements()
        let newer = p.beginEntitlements()
        p.applyEntitlements(unlimited: true, dictation: false, generation: newer)
        p.applyEntitlements(unlimited: false, dictation: false, generation: older)
        #expect(p.ownsUnlimited)
    }
}

/// A fake Keychain for `KeychainUsageStorage`: `swift test` runs without the entitlement the data
/// protection Keychain needs.
final class FakeKeychain: @unchecked Sendable {
    private let lock = NSLock()
    var item: Data?
    var readStatus: OSStatus?
    var writes = 0

    var calls: KeychainUsageStorage.Calls {
        KeychainUsageStorage.Calls(
            copy: { [self] _ in
                lock.withLock {
                    if let readStatus { return (readStatus, nil) }
                    return item.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
                }
            },
            update: { [self] _, attributes in
                lock.withLock {
                    guard item != nil else { return errSecItemNotFound }
                    item = attributes[kSecValueData as String] as? Data
                    writes += 1
                    return errSecSuccess
                }
            },
            add: { [self] attributes in
                lock.withLock {
                    item = attributes[kSecValueData as String] as? Data
                    writes += 1
                    return errSecSuccess
                }
            })
    }
}

@Suite struct KeychainUsageStorageTests {
    @Test func notFoundThenAddThenUpdate() {
        let keychain = FakeKeychain()
        let storage = KeychainUsageStorage(service: "test", calls: keychain.calls)
        #expect(storage.load() == nil)
        storage.save(FreeUsage(transcribed: ["a"]))
        storage.save(FreeUsage(transcribed: ["a", "b"]))
        #expect(keychain.writes == 2)
        #expect(storage.load() == FreeUsage(transcribed: ["a", "b"]))
    }

    @Test func failedReadIsNeverOverwritten() {
        let keychain = FakeKeychain()
        keychain.item = try? JSONEncoder().encode(FreeUsage(transcribed: ["a", "b", "c"]))
        keychain.readStatus = errSecInteractionNotAllowed  // locked before the first unlock
        let storage = KeychainUsageStorage(service: "test", calls: keychain.calls)
        #expect(storage.load() == nil)
        storage.save(FreeUsage(transcribed: ["x"]))
        // Readable again later in the same process: still not written.
        keychain.readStatus = nil
        storage.save(FreeUsage(transcribed: ["x"]))
        #expect(keychain.writes == 0)
        #expect(KeychainUsageStorage(service: "test", calls: keychain.calls).load()?.transcribed == ["a", "b", "c"])
    }

    @Test func undecodableItemIsLeftAlone() {
        let keychain = FakeKeychain()
        keychain.item = Data("garbage".utf8)
        let storage = KeychainUsageStorage(service: "test", calls: keychain.calls)
        #expect(storage.load() == nil)
        storage.save(FreeUsage(transcribed: ["x"]))
        #expect(keychain.writes == 0)
    }

    @Test func saveWithoutLoadReadsFirst() {
        let keychain = FakeKeychain()
        keychain.readStatus = errSecInteractionNotAllowed
        let storage = KeychainUsageStorage(service: "test", calls: keychain.calls)
        storage.save(FreeUsage(transcribed: ["x"]))
        #expect(keychain.writes == 0)
    }
}
