// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share extension: copies shared audio and video into the App Group inbox, says so briefly and
/// closes. No AVFoundation work here (memory limit); the app imports the inbox when it becomes
/// active.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareCard(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task {
            var added = 0
            for provider in providers where await Inbox.copy(provider) { added += 1 }
            model.state = added > 0 ? .added : .failed
            try? await Task.sleep(for: .seconds(added > 0 ? 0.9 : 1.8))
            extensionContext?.completeRequest(returningItems: [])
        }
    }
}

@MainActor @Observable
final class ShareModel {
    enum State { case adding, added, failed }
    var state = State.adding
}

struct ShareCard: View {
    let model: ShareModel

    var body: some View {
        VStack(spacing: 14) {
            switch model.state {
            case .adding:
                ProgressView()
                    .controlSize(.large)
                Text("Adding to Bandje…")
            case .added:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: model.state)
                Text("Added to Bandje")
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Bandje can't open this. Share audio or video.")
                    .multilineTextAlignment(.center)
            }
        }
        .font(.headline)
        .padding(32)
        .frame(minWidth: 220)
        .glassEffect(in: .rect(cornerRadius: 32))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .sensoryFeedback(.success, trigger: model.state == .added)
    }
}

/// The App Group drop folder the app reads (`Importer.inbox` in the app).
enum Inbox {
    static let appGroup = "group.com.neurendal.bandje"

    /// Copies one shared item, if it is audio or video, to `Inbox/<name>.<ext>`. Written to a
    /// hidden folder first and then moved, so the app never sees half a file.
    @MainActor
    static func copy(_ provider: NSItemProvider) async -> Bool {
        guard let type = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .audiovisualContent) == true
        }), let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return false
        }
        let inbox = container.appending(path: "Inbox", directoryHint: .isDirectory)
        let suggested = provider.suggestedName
        return await withCheckedContinuation { continuation in
            // The file only exists until the handler returns: copy it right here.
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { @Sendable url, _ in
                guard let url else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: store(url, suggestedName: suggested, type: type, in: inbox))
            }
        }
    }

    nonisolated private static func store(_ url: URL, suggestedName: String?, type: String, in inbox: URL) -> Bool {
        let fm = FileManager.default
        let ext = url.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "m4a") : url.pathExtension
        var base = suggestedName ?? url.deletingPathExtension().lastPathComponent
        if base.lowercased().hasSuffix(".\(ext.lowercased())") { base = String(base.dropLast(ext.count + 1)) }
        base = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        while base.hasPrefix(".") { base.removeFirst() }
        if base.isEmpty { base = "Audio" }
        let incoming = inbox.appending(path: ".incoming", directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: incoming, withIntermediateDirectories: true)
            let temp = incoming.appending(path: "\(UUID().uuidString).\(ext)")
            try fm.copyItem(at: url, to: temp)
            var name = "\(base).\(ext)", n = 2
            while fm.fileExists(atPath: inbox.appending(path: name).path) {
                name = "\(base) \(n).\(ext)"
                n += 1
            }
            try fm.moveItem(at: temp, to: inbox.appending(path: name))
            return true
        } catch {
            return false
        }
    }
}
