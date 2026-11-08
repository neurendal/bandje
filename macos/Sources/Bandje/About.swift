import AppKit
import SwiftUI

/// "Over Bandje": icon, name, version, what goes over the network, the two models in
/// two aligned columns, Neurendal B.V. as maker, and the Desert Ant Labs credit (SDK license,
/// section 9: name in context, linked to desertant.com), and the website band.je. These three links are the only URLs in our
/// code; they open the browser, Bandje itself connects to nothing.
@MainActor
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if let window { NSApp.activate(); window.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        w.title = ""
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { window = nil }
        }
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return tr("about.version", "Versie %1$@ (%2$@)", info["CFBundleShortVersionString"] as? String ?? "?",
                  info["CFBundleVersion"] as? String ?? "?")
    }

    /// Also the "Met liefde gemaakt door Neurendal" link on the welcome.
    static let neurendal = URL(string: "https://neurendal.com")!
    private static let desertAnt = URL(string: "https://desertant.com")!
    private static let website = URL(string: "https://band.je")!

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Bandje")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 6)
            HStack(spacing: 4) {
                Text(version).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Link("band.je", destination: Self.website)
            }
            .font(.callout)
            .padding(.top, 2)

            VStack(spacing: 6) {
                Text(tr("about.intro", "Neemt gesprekken op en transcribeert ze op je Mac."))
                Text(privacyLine)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)

            Divider().padding(.vertical, 16)

            HStack(alignment: .top, spacing: 24) {
                model(tr("about.speech", "Spraakherkenning"), "Voz \(Transcriber.vozVersion)", "NVIDIA Parakeet TDT 0.6B v3")
                model(tr("about.speaker", "Sprekerherkenning"), "Who \(Transcriber.whoVersion)", "pyannote community-1")
            }
            // The models' maker, with the models (SDK license, section 9: name in context, linked).
            HStack(spacing: 4) {
                Link("Powered by Desert Ant Labs", destination: Self.desertAnt)
                Text("· desert-ant-core \(Transcriber.sdkVersion)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .tint(.secondary)
            .padding(.top, 12)

            Divider().padding(.vertical, 16)

            VStack(spacing: 4) {
                Text(tr("about.madeBy", "Gemaakt door Neurendal B.V.")).font(.body.weight(.semibold))
                Link("neurendal.com", destination: Self.neurendal).font(.callout)
                Text(verbatim: "© 2026 Neurendal B.V.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(width: 440)
        .textSelection(.enabled)
    }

    /// One column: heading, model with version and maker, base model and license.
    private func model(_ heading: String, _ name: String, _ basedOn: String) -> some View {
        VStack(spacing: 3) {
            Text(heading.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .padding(.bottom, 2)
            Text(name).font(.callout.weight(.medium))
            Text(tr("about.basedOn", "Gebaseerd op"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Text(basedOn)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("CC BY 4.0").font(.caption).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}
