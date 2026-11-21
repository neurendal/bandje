// SPDX-License-Identifier: GPL-3.0-only
import BandjeKit
import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Bandje

/// Freemium on the iPhone (specs/purchase.md): where transcriptions are gated, the plural line,
/// and a purchase through the StoreKit configuration file.
@Suite(.serialized) @MainActor
struct PurchaseTests {
    private let created = Date(timeIntervalSince1970: 1_794_000_000)

    /// A recording folder with `.bandje.json` and a (fake) audio file.
    private func recording(created: Date) throws -> Recording {
        let folder = FileManager.default.temporaryDirectory.appending(path: "purchase-\(UUID().uuidString)/Opname", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try RecordingMeta(created: created).write(to: folder)
        let audio = folder.appending(path: "Opname.m4a")
        try Data("audio".utf8).write(to: audio)
        return Recording(folder: folder, audio: audio, date: created, duration: 30, markers: [])
    }

    private func purchases(_ override: Purchases.Override, used: [String] = []) -> Purchases {
        let p = Purchases(storage: MemoryUsageStorage(FreeUsage(transcribed: used)))
        p.start(override: override)
        return p
    }

    @Test func keyComesFromTheCreationDate() throws {
        let r = try recording(created: created)
        defer { try? FileManager.default.removeItem(at: r.folder.deletingLastPathComponent()) }
        #expect(Transcriptions.purchaseKey(of: r.folder) == PurchaseRules.recordingKey(created: created, folderName: "Opname"))
        // Without `.bandje.json`: the folder name.
        let bare = FileManager.default.temporaryDirectory.appending(path: "Zonder meta")
        #expect(Transcriptions.purchaseKey(of: bare) == "fZonder meta")
    }

    /// `n` distinct recording keys.
    private func keys(_ n: Int) -> [String] {
        (0..<n).map { "k\($0)" }
    }

    @Test func aRecordingCountsOnce() {
        let free = FreeAllowance.transcriptions
        let p = purchases(.free)
        #expect(p.transcriptionsLeft == free)
        p.noteTranscribed("c1")
        p.noteTranscribed("c1")  // transcribed again: not counted again
        #expect(p.transcriptionsLeft == free - 1)
        for key in keys(free - 1) { p.noteTranscribed(key) }
        #expect(p.transcriptionsLeft == 0)
        #expect(p.mayTranscribe("c1"))  // a counted recording may always be transcribed again
        #expect(!p.mayTranscribe("other"))
    }

    @Test func pastTheLimitNothingStarts() throws {
        let r = try recording(created: created)
        defer { try? FileManager.default.removeItem(at: r.folder.deletingLastPathComponent()) }
        let jobs = Transcriptions()
        // `.used`: the free ones are gone (`.free` now always starts from an empty usage).
        jobs.purchases = purchases(.used, used: keys(FreeAllowance.transcriptions))
        #expect(!jobs.mayTranscribe(r))
        // A tap: not started (the screen shows the paywall).
        #expect(!jobs.start(r, speakers: false))
        #expect(!jobs.isRunning(r.folder))
        // "Transcribe automatically": not started either, and no error.
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: "autoTranscribe")
        defer { defaults.set(before, forKey: "autoTranscribe") }
        defaults.set(true, forKey: "autoTranscribe")
        jobs.startIfAutomatic([r])
        #expect(!jobs.isRunning(r.folder))
        #expect(jobs.errors.isEmpty)
    }

    /// Queued while one was left, but the jobs before it used it: it does not run, and it is no
    /// error (the screen shows "used up").
    @Test func queuedJobChecksAgainWhenItStarts() async throws {
        let r = try recording(created: created)
        defer { try? FileManager.default.removeItem(at: r.folder.deletingLastPathComponent()) }
        let jobs = Transcriptions()
        jobs.purchases = purchases(.free)
        #expect(jobs.start(r, speakers: false))
        #expect(jobs.isRunning(r.folder))
        jobs.purchases = purchases(.used)  // meanwhile used up
        await jobs.wait(r.folder)
        #expect(!jobs.isRunning(r.folder))
        #expect(jobs.errors.isEmpty)
        #expect(Storage.transcriptFile(in: r.folder) == nil)
    }

    /// Cancelling a job that only waits for the one before it: gone at once.
    @Test func cancellingAQueuedJobClearsItAtOnce() throws {
        let r = try recording(created: created)
        defer { try? FileManager.default.removeItem(at: r.folder.deletingLastPathComponent()) }
        let jobs = Transcriptions()
        jobs.purchases = purchases(.unlimited)
        #expect(jobs.start(r, speakers: false))
        jobs.cancel(r.folder)
        #expect(!jobs.isRunning(r.folder))
    }

    @Test func countedOrUnlockedMayTranscribe() throws {
        let r = try recording(created: created)
        defer { try? FileManager.default.removeItem(at: r.folder.deletingLastPathComponent()) }
        let key = Transcriptions.purchaseKey(of: r.folder)
        let jobs = Transcriptions()
        jobs.purchases = purchases(.free, used: keys(FreeAllowance.transcriptions - 1) + [key])  // one left
        #expect(jobs.mayTranscribe(r))
        jobs.purchases = purchases(.used, used: [key])  // none left, but this one was counted
        #expect(jobs.mayTranscribe(r))
        jobs.purchases = purchases(.unlimited, used: keys(FreeAllowance.transcriptions))
        #expect(jobs.mayTranscribe(r))
        jobs.purchases = purchases(.existing, used: keys(FreeAllowance.transcriptions))
        #expect(jobs.mayTranscribe(r))
        jobs.purchases = purchases(.dictation, used: keys(FreeAllowance.transcriptions))  // dictation alone: no transcribing
        #expect(!jobs.mayTranscribe(r))
    }

    @Test func statusInSettings() {
        #expect(Store.status(purchases(.free)) == .free(left: FreeAllowance.transcriptions))
        #expect(Store.status(purchases(.used)) == .free(left: 0))
        #expect(Store.status(purchases(.unlimited)) == .bought)
        #expect(Store.status(purchases(.existing)) == .existing)
    }

    /// The plural line in languages whose words change with the number.
    @Test func pluralLine() throws {
        func line(_ language: String, _ n: Int) throws -> String {
            let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            let format = bundle.localizedString(forKey: "%lld of %lld free transcriptions left", value: nil, table: nil)
            return String(format: format, locale: Locale(identifier: language), n, 3)
        }
        #expect(try line("en", 2) == "2 of 3 free transcriptions left")
        #expect(try line("nl", 1) == "Nog 1 van 3 gratis transcripties over")
        #expect(try line("fr", 1) == "Encore 1 transcription gratuite sur 3")
        #expect(try line("fr", 2) == "Encore 2 transcriptions gratuites sur 3")
        #expect(try line("ru", 1) == "Осталась 1 из 3 бесплатных расшифровок")
        #expect(try line("ru", 2) == "Осталось 2 из 3 бесплатных расшифровок")
        #expect(try line("pl", 2) == "Pozostały 2 z 3 bezpłatnych transkrypcji")
        #expect(try line("es", 1) == "Te queda 1 de 3 transcripciones gratis")
    }

    /// Buying Band·je Onbeperkt with the StoreKit configuration file (no App Store, no network).
    @Test func buyUnlimitedWithTheConfigurationFile() async throws {
        let session = try SKTestSession(configurationFileNamed: "Bandje")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let p = Purchases(storage: MemoryUsageStorage())
        await p.loadProducts()
        #expect(p.products.map(\.id) == BandjeProduct.allCases.map(\.rawValue))
        let product = try #require(p.product(.unlimited))
        #expect(product.type == .nonConsumable)
        #expect(product.isFamilyShareable)
        await p.refreshEntitlements()
        #expect(!p.ownsUnlimited)
        #expect(await p.handle(try await product.purchase()))
        #expect(p.ownsUnlimited)
        #expect(p.hasUnlimited)
        #expect(p.hasDictation)  // Onbeperkt includes dictation
        #expect(Store.status(p) == .bought)
    }
}
