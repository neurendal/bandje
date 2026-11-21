#if APPSTORE
import BandjeKit
import Foundation
import OSLog
import StoreKit

/// Puts the App Store's signed proof of a Band·je purchase in the App Group container, for other
/// apps of the same team to read (docs/pro-sharing.md). Band·je itself shows nothing about this and
/// says nothing about other apps (App Review).
///
/// `<group container>/pro.jws` holds the `jwsRepresentation` of the verified, unrevoked transaction
/// of Band·je Onbeperkt, or else of Band·je Dicteren (both count, owner 2026-11-20). Nothing
/// bought: the file does not exist. Customers from before the free version (`AppTransaction`) get
/// no file (owner 2026-11-20).
///
/// Written at launch, when Band·je comes to the front, after a purchase and after Restore, and
/// again on every `Transaction.updates` for one of the products (a refund or revocation removes or
/// replaces it). Errors go to the log; nothing here throws, blocks the interface or shows anything.
actor ProStatusExporter {
    /// The App Group from Info.plist (`groupKey`).
    static let shared = ProStatusExporter(groupIdentifier: infoPlistGroup(Bundle.main))

    static let fileName = "pro.jws"
    /// Info.plist key with the App Group identifier. scripts/mas.sh puts `$(BANDJE_APP_GROUP)` there;
    /// Xcode fills it in from mas/project.yml (`$(DEVELOPMENT_TEAM).je.bandje.shared`), the same
    /// setting as the entitlement, so the team id is written down once.
    static let groupKey = "BandjeAppGroup"
    /// Preference order when both are owned.
    static let products: [BandjeProduct] = [.unlimited, .dictation]

    private static let log = Logger(subsystem: "com.neurendal.bandje", category: "prostatus")

    /// The App Group identifier, or nil when the build does not have one.
    let groupIdentifier: String?
    private var listener: Task<Void, Never>?
    /// The latest export run; an older run that finishes later does not write.
    private var generation = 0

    /// The tests pass their own bundle's Info.plist (mas/Tests/Info.plist, same build setting).
    init(groupIdentifier: String?) {
        self.groupIdentifier = groupIdentifier
    }

    /// `BandjeAppGroup` from `bundle`'s Info.plist, when Xcode filled it in.
    static func infoPlistGroup(_ bundle: Bundle) -> String? {
        guard let id = bundle.object(forInfoDictionaryKey: groupKey) as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }

    /// `<group container>/pro.jws`, or nil without an App Group.
    nonisolated var fileURL: URL? {
        guard let id = groupIdentifier,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        return dir.appendingPathComponent(Self.fileName)
    }

    /// At launch: listen for transaction updates, then export once.
    func start() async {
        if listener == nil {
            listener = Task { [weak self] in
                for await result in Transaction.updates {
                    guard case .verified(let t) = result, BandjeProduct(rawValue: t.productID) != nil else { continue }
                    // A revoked transaction may still be listed for a moment: leave it out explicitly.
                    await self?.export(excluding: t.revocationDate == nil ? nil : t.id)
                }
            }
        }
        await export()
    }

    /// Writes or removes pro.jws from `Transaction.currentEntitlements`. Returns the product written,
    /// or nil when there is no file now (or the run was overtaken by a newer one).
    @discardableResult
    func export(excluding revoked: UInt64? = nil) async -> BandjeProduct? {
        generation += 1
        let run = generation
        var best: (product: BandjeProduct, jws: String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil, t.id != revoked,
                  let product = BandjeProduct(rawValue: t.productID),
                  let rank = Self.products.firstIndex(of: product) else { continue }
            if let current = best, Self.products.firstIndex(of: current.product)! <= rank { continue }
            best = (product, result.jwsRepresentation)
        }
        guard run == generation else { return nil }
        guard let url = fileURL else {
            Self.log.error("no App Group container (\(self.groupIdentifier ?? "no identifier", privacy: .public))")
            return nil
        }
        let files = FileManager.default
        do {
            if let best {
                try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(best.jws.utf8).write(to: url, options: .atomic)
                Self.log.notice("written: \(best.product.rawValue, privacy: .public)")
                return best.product
            }
            if files.fileExists(atPath: url.path) {
                try files.removeItem(at: url)
                Self.log.notice("removed: nothing owned")
            }
        } catch {
            Self.log.error("failed: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }
}
#endif
