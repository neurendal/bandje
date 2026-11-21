// SPDX-License-Identifier: GPL-3.0-only
import AppIntents
import Foundation
import SwiftUI

// Compiled into the Watch app and its widget extension (WIDGET_EXTENSION): the recording state the
// complications read, the intents (Action button, Siri, the Control), colours and the cassette.

/// What the complications, the Smart Stack and the Control show. Written by the Watch app into the
/// App Group on the Watch; the widget extension only reads it.
struct WatchStatus: Codable, Equatable, Sendable {
    /// The start of a timer that shows the recorded time (now minus recorded seconds); nil when idle.
    var recordingSince: Date?
    /// Recorded seconds while the recording is paused (the time stands still); nil otherwise.
    var pausedAt: Double?
    var markers = 0
    /// Recordings waiting for the iPhone.
    var pending = 0

    /// True while a recording is open, also when it is paused.
    var isRecording: Bool { recordingSince != nil }
    var isPaused: Bool { isRecording && pausedAt != nil }

    static let appGroup = "group.com.neurendal.bandje"
    static let widgetKind = "com.neurendal.bandje.watch.status"
    static let controlKind = "com.neurendal.bandje.watch.record"
    private static let key = "watchStatus"

    static var current: WatchStatus {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let status = try? JSONDecoder().decode(WatchStatus.self, from: data) else { return WatchStatus() }
        return status
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }
}

// MARK: - Intents

// The system runs these in the Watch app (foreground): the Action button opens the app straight
// into Recording (design A2) and stops into Stopped (A3). In the widget extension they do nothing.

/// "Opname starten/stoppen": the action for the Action button (via the Control below, or as a
/// shortcut) and for Shortcuts.
struct ToggleRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start/Stop Recording"
    static let description = IntentDescription("Starts or stops a recording in Bandje.")
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await WatchRecorder.shared.toggle()
        #endif
        return .result()
    }
}

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Starts a new recording in Bandje.")
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await WatchRecorder.shared.record()
        #endif
        return .result()
    }
}

struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stops the recording in Bandje and sends it to your phone.")
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        WatchRecorder.shared.stop()
        #endif
        return .result()
    }
}

/// The Control (Control Centre, Smart Stack, Action button on Apple Watch Ultra): on starts a
/// recording, off stops it.
struct RecordingControlIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Start/Stop Recording"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Recording")
    var value: Bool

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        if value {
            await WatchRecorder.shared.record()
        } else {
            WatchRecorder.shared.stop()
        }
        #endif
        return .result()
    }
}

// MARK: - Look

extension Color {
    /// Recording, markers (design token #D5452A).
    static let bandjeRed = Color(hex: 0xD5452A)
    /// Red as text on black (#EF6B4B).
    static let bandjeRedText = Color(hex: 0xEF6B4B)
    /// The still dot while dimmed (#7A2A1A).
    static let bandjeDimRed = Color(hex: 0x7A2A1A)
    /// The "Opnemen" label while dimmed (#8A3A28).
    static let bandjeDimLabel = Color(hex: 0x8A3A28)
    /// Warning icon (#FFD60A).
    static let bandjeYellow = Color(hex: 0xFFD60A)

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// The record button's shape: a red ring, a gap, a red disc and a dot in the background colour.
/// `dot: nil` punches the gap and the dot out (transparent): complications are tinted to one
/// colour, which would paint a black dot over too.
struct RecordGlyph: View {
    var size: CGFloat
    var ring: CGFloat = 3
    var gap: CGFloat = 3
    var dot: Color? = .black
    var dotFraction: CGFloat = 0.32

    var body: some View {
        let inner = size - 2 * (ring + gap)
        ZStack {
            if let dot {
                Circle().strokeBorder(Color.bandjeRed, lineWidth: ring)
                Circle().fill(Color.bandjeRed).frame(width: inner, height: inner)
                Circle().fill(dot).frame(width: inner * dotFraction, height: inner * dotFraction)
            } else {
                RecordShape(ring: ring, gap: gap, dotFraction: dotFraction)
                    .fill(Color.bandjeRed, style: FillStyle(eoFill: true))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Four nested circles filled even-odd: ring, gap (hole), disc, dot (hole).
struct RecordShape: Shape {
    var ring: CGFloat
    var gap: CGFloat
    var dotFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let disc = r - ring - gap
        var path = Path()
        for radius in [r, r - ring, disc, disc * dotFraction] where radius > 0 {
            path.addEllipse(in: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: 2 * radius, height: 2 * radius))
        }
        return path
    }
}

/// Band·je's cassette (the app's artwork), drawn after the design's 120 × 78 mock.
struct WatchCassette: View {
    var width: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 120
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
            }
            func rounded(_ r: CGRect, _ radius: Double) -> Path { Path(roundedRect: r, cornerRadius: radius * s) }
            func fill(_ p: Path, _ hex: UInt32) { ctx.fill(p, with: .color(Color(hex: hex))) }
            func vertical(_ r: CGRect, _ top: UInt32, _ bottom: UInt32) -> GraphicsContext.Shading {
                .linearGradient(Gradient(colors: [Color(hex: top), Color(hex: bottom)]),
                                startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY))
            }

            let shell = rect(0, 0, 120, 78)
            ctx.fill(rounded(shell, 9), with: vertical(shell, 0xEDE5D4, 0xD6CBB3))
            for (x, y) in [(3.5, 3.5), (113, 3.5), (3.5, 71), (113, 71)] {
                fill(Path(ellipseIn: rect(x, y, 3.5, 3.5)), 0xBDB29B)
            }
            let label = rect(9, 7, 102, 44)
            ctx.fill(rounded(label, 6), with: vertical(label, 0xEF6B4B, 0xD5452A))
            fill(rounded(rect(14, 10, 92, 10), 1.5), 0xFBF4E8)
            let window = rect(24, 24, 72, 23)
            ctx.fill(rounded(window, 11.5), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x33364C), Color(hex: 0x1B1D2B)]),
                startPoint: CGPoint(x: window.minX, y: window.midY), endPoint: CGPoint(x: window.maxX, y: window.midY)))
            fill(Path(ellipseIn: rect(28, 24.5, 22, 22)), 0x5E4436)
            fill(Path(ellipseIn: rect(33, 29.5, 12, 12)), 0xF3EBDD)
            fill(Path(ellipseIn: rect(37, 33.5, 4, 4)), 0x1B1D2B)
            fill(Path(ellipseIn: rect(73, 27.5, 16, 16)), 0x5E4436)
            fill(Path(ellipseIn: rect(76, 30.5, 10, 10)), 0xF3EBDD)
            fill(Path(ellipseIn: rect(79.5, 34, 3, 3)), 0x1B1D2B)
            var head = Path()
            head.move(to: CGPoint(x: 37.2 * s, y: 56 * s))
            head.addLine(to: CGPoint(x: 82.8 * s, y: 56 * s))
            head.addLine(to: CGPoint(x: 90 * s, y: 78 * s))
            head.addLine(to: CGPoint(x: 30 * s, y: 78 * s))
            head.closeSubpath()
            fill(head, 0xC9BDA3)
            fill(Path(ellipseIn: rect(44, 63, 5, 5)), 0x23263A)
            fill(rounded(rect(55.5, 63.5, 9, 4), 1), 0x23263A)
            fill(Path(ellipseIn: rect(71, 63, 5, 5)), 0x23263A)
            fill(Path(rect(34, 74.5, 52, 1)), 0x6B4A3A)
        }
        .frame(width: width, height: (width * 0.65).rounded())
        .shadow(color: .black.opacity(0.22), radius: 2, y: 1.5)
        .accessibilityHidden(true)
    }
}

enum WatchFormat {
    /// Recorded time as on the screen: 12:34, or 1:02:03 from an hour.
    static func clock(_ seconds: Double) -> String {
        let t = max(0, Int(seconds.rounded(.down)))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }

    /// "12 minuten 34 seconden" for VoiceOver.
    static func spoken(_ seconds: Double) -> String {
        let d = Duration.seconds(max(0, seconds.rounded(.down)))
        return d.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// "3 markers", "1 marker".
    static func markers(_ n: Int) -> String {
        String(localized: "\(n) markers", comment: "Number of markers in a recording")
    }
}
