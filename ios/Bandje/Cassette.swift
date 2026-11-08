// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UIKit

/// Everything the cassette shows. One value drives both the drawing and the motion, so the
/// animation can never drift from the audio: the reels' sizes are a function of `position`,
/// their spin only of `mode` and `lastSeek`.
/// The colour of the cassette's label, chosen per recording (owner, 6 Nov). Stored as `color` in
/// `.bandje.json` by name, shared with the Mac app; absent or unknown means the default red.
enum TapeColor: String, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, purple, navy

    init(_ name: String?) { self = name.flatMap(TapeColor.init(rawValue:)) ?? .red }

    /// Nil for the default, so existing files stay as they are.
    var stored: String? { self == .red ? nil : rawValue }

    /// Top and bottom of the label's gradient.
    var gradient: (top: UInt32, bottom: UInt32) {
        switch self {
        case .red: (0xEF6B4B, 0xD5452A)
        case .orange: (0xF39A45, 0xDB7524)
        case .yellow: (0xF3C94F, 0xDCA62A)
        case .green: (0x62B27F, 0x3F8C5D)
        case .blue: (0x5A95DA, 0x3470B8)
        case .purple: (0x9473CC, 0x6D4CA9)
        case .navy: (0x454B7E, 0x262B4F)
        }
    }

    var name: LocalizedStringResource {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .navy: "Navy"
        }
    }
}

struct CassetteState: Equatable {
    enum Mode: Equatable { case stopped, recording, recordingPaused, playing }

    var mode: Mode = .stopped
    /// Playback position; while recording, the recorded time.
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    /// Input level 0…1 (recording only).
    var level: Float = 0
    var title: String = ""
    var color: TapeColor = .red
    /// A jump (scrub, ±15 s) at this moment makes the reels spin hard for a moment.
    var lastSeek: Date = .distantPast
    var seekForward = true

    var isRunning: Bool { mode == .recording || mode == .playing }
    var isRecording: Bool { mode == .recording || mode == .recordingPaused }

    /// Share of the tape wound onto the right reel, 0…1.
    var fraction: Double {
        isRecording ? Reels.recordingFraction(elapsed: position) : Reels.fraction(position: position, duration: duration)
    }
}

/// Reel geometry and motion as pure functions (unit-tested). Lengths are in the cassette's own
/// 640 × 420 coordinate space.
enum Reels {
    /// Margin around the shell so its shadow is not clipped.
    static let margin: CGFloat = 40
    /// Radius of an empty reel: the hub plus a few turns of tape.
    static let core = 41.0
    /// Radius of a full reel (the window is 132 high).
    static let full = 64.0
    /// A recording of this length fills the right reel to 63 %; it approaches full, never reaches it.
    static let nominalRecording: TimeInterval = 30 * 60
    /// Tape speed at 1×, in points per second: an empty reel turns half a revolution per second.
    static let tapeSpeed = 2 * Double.pi * core * 0.5
    /// Speed while fast-winding after a seek, and for how long.
    static let seekSpeed = 10.0
    static let seekDuration: TimeInterval = 0.45
    /// Time constant of spin-up and spin-down (≈ 0.4 s to 95 %).
    static let spinTau: TimeInterval = 0.14

    /// Playback position as a share of the duration, clamped; 0 when the duration is unknown.
    static func fraction(position: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0, duration.isFinite, position.isFinite else { return 0 }
        return min(1, max(0, position / duration))
    }

    /// While recording the right reel grows with the recorded time, saturating.
    static func recordingFraction(elapsed: TimeInterval) -> Double {
        guard elapsed > 0, elapsed.isFinite else { return 0 }
        return 1 - exp(-elapsed / nominalRecording)
    }

    /// Reel radii for a share `f` of the tape on the right reel. The tape's area is conserved:
    /// r_left² = core² + (1 − f)(full² − core²), r_right² = core² + f(full² − core²).
    static func radii(fraction f: Double) -> (left: Double, right: Double) {
        let f = f.isFinite ? min(1, max(0, f)) : 0
        let tape = full * full - core * core
        return ((core * core + (1 - f) * tape).squareRoot(), (core * core + f * tape).squareRoot())
    }

    /// Moves `current` toward `target` with time constant `tau` (frame-rate independent).
    static func eased(_ current: Double, toward target: Double, dt: TimeInterval, tau: TimeInterval = spinTau) -> Double {
        guard dt > 0 else { return current }
        return target + (current - target) * exp(-dt / tau)
    }

    /// The tape speed the reels head for, in multiples of normal speed (negative: rewinding).
    static func targetSpeed(_ state: CassetteState, at date: Date, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0 }
        let sinceSeek = date.timeIntervalSince(state.lastSeek)
        if sinceSeek >= 0, sinceSeek < seekDuration { return state.seekForward ? seekSpeed : -seekSpeed }
        return state.isRunning ? 1 : 0
    }

    /// Input level shown on the VU strip: speech RMS sits around 0.01–0.3, a square-root curve
    /// makes that visible.
    static func meter(_ level: Float) -> Double {
        Double(min(1, max(0, level) * 3)).squareRoot()
    }
}

/// Where the title sticker sits: tilted and shifted a little, as if stuck on by hand. Derived from
/// the title (stable across launches, unlike `hashValue`), so a tape keeps its sticker.
enum Sticker {
    static func placement(for title: String) -> (degrees: Double, dx: Double, dy: Double) {
        var h: UInt64 = 0xcbf29ce484222325  // FNV-1a
        for b in title.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        func unit(_ shift: UInt64) -> Double { Double((h >> shift) & 0xFFFF) / 65535 }
        // 0.8…3.5° to either side: never quite straight, never crooked.
        let degrees = (unit(0) < 0.5 ? -1 : 1) * (0.8 + 2.7 * unit(16))
        return (degrees, (unit(32) - 0.5) * 16, (unit(48) - 0.5) * 6)
    }
}

/// Integrates the reels' angles from frame to frame. Not observable: it is advanced inside the
/// `TimelineView` and only read by the frame being drawn.
@MainActor
final class ReelMotion {
    private(set) var leftAngle = 0.0
    private(set) var rightAngle = 0.0
    private(set) var speed = 0.0
    private(set) var meter = 0.0
    private var last: Date?

    func advance(to date: Date, state: CassetteState, reduceMotion: Bool) {
        let dt = last.map { min(max(date.timeIntervalSince($0), 0), 0.1) } ?? 0
        last = date
        let target = Reels.targetSpeed(state, at: date, reduceMotion: reduceMotion)
        speed = reduceMotion ? 0 : Reels.eased(speed, toward: target, dt: dt)
        if target == 0, abs(speed) < 0.002 { speed = 0 }
        // Tape runs left → right under the reels: both turn counter-clockwise, the smaller one faster.
        let radii = Reels.radii(fraction: state.fraction)
        let distance = speed * Reels.tapeSpeed * dt
        leftAngle = (leftAngle - distance / radii.left).truncatingRemainder(dividingBy: 2 * .pi)
        rightAngle = (rightAngle - distance / radii.right).truncatingRemainder(dividingBy: 2 * .pi)
        // VU: fast attack, slower release.
        let level = state.mode == .recording ? Reels.meter(state.level) : 0
        meter = level > meter ? level : Reels.eased(meter, toward: level, dt: dt, tau: 0.2)
    }
}

/// The signature element: a cassette whose reels turn while recording and playing and whose
/// tape moves from the left to the right reel with the position.
struct CassetteView: View {
    let state: CassetteState
    /// Tapping the title sticker (e.g. to rename); nil: the sticker is not tappable.
    var onTapLabel: (() -> Void)?
    /// Shows an empty sticker when there is no title (the empty library).
    var blankSticker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var motion = ReelMotion()
    /// Keeps the timeline running for a moment after the reels' target changes (spin-down).
    @State private var coasting = false

    static let margin = Reels.margin
    static let aspect: CGFloat = (640 + 2 * margin) / (420 + 2 * margin)

    private struct CoastKey: Equatable {
        var running: Bool
        var seek: Date
    }

    var body: some View {
        let animating = !reduceMotion && (state.isRunning || coasting || state.mode == .recordingPaused)
        TimelineView(.animation(paused: !animating)) { timeline in
            let frame = advance(to: timeline.date)
            Canvas { context, size in
                CassetteDrawing(frame: frame, dark: colorScheme == .dark, color: state.color).draw(in: &context, size: size)
            }
        }
        .overlay { label }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .task(id: CoastKey(running: state.isRunning, seek: state.lastSeek)) {
            coasting = true
            try? await Task.sleep(for: .seconds(Reels.seekDuration + 1))
            coasting = false
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Recording"))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("cassette")
    }

    private func advance(to date: Date) -> CassetteDrawing.Frame {
        motion.advance(to: date, state: state, reduceMotion: reduceMotion)
        var lamp = 0.0
        switch state.mode {
        case .recording: lamp = 1
        case .recordingPaused:
            lamp = reduceMotion ? 0.5 : 0.55 + 0.45 * cos(date.timeIntervalSinceReferenceDate * 2 * .pi / 1.4)
        default: break
        }
        return .init(radii: Reels.radii(fraction: state.fraction), leftAngle: motion.leftAngle,
                     rightAngle: motion.rightAngle, meter: state.isRecording ? motion.meter : nil, lamp: lamp)
    }

    /// The title on a paper sticker, in handwriting; once there is a finished recording (not while
    /// recording) its length is written at the right end. No title, no sticker. Scales with the
    /// cassette, not Dynamic Type.
    @ViewBuilder private var label: some View {
        if !state.title.isEmpty || blankSticker { sticker }
    }

    private var sticker: some View {
        GeometryReader { geo in
            let m = Self.margin
            let s = geo.size.width / (640 + 2 * m)
            let ink = Color(hex: 0x1B1D29)
            let place = Sticker.placement(for: state.title)
            let showsLength = !state.isRecording && state.duration > 0 && state.duration.isFinite
            HStack(alignment: .lastTextBaseline, spacing: 14 * s) {
                Text(state.title)
                    .font(.custom("BradleyHandITCTT-Bold", fixedSize: 36 * s))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsLength {
                    Text(clock(state.duration))
                        .font(.custom("BradleyHandITCTT-Bold", fixedSize: 24 * s))
                        .monospacedDigit()
                        .opacity(0.8)
                        .fixedSize()
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 20 * s)
            .padding(.bottom, 4 * s)
            .frame(width: 496 * s, height: 50 * s, alignment: .bottom)
            .background {
                RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                    .fill(Color(hex: colorScheme == .dark ? 0xEFE6D6 : 0xFFF6EC))
                    .overlay(alignment: .bottom) {
                        // A faint ruled line under the writing.
                        Rectangle()
                            .fill(Color(hex: state.color.gradient.bottom).opacity(0.25))
                            .frame(height: 1.5 * s)
                            .padding(.horizontal, 16 * s)
                            .padding(.bottom, 9 * s)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 2 * s, x: 0, y: 1.5 * s)
            }
            .rotationEffect(.degrees(place.degrees))
            .contentShape(Rectangle())
            .onTapGesture { onTapLabel?() }
            .allowsHitTesting(onTapLabel != nil)
            .position(x: (m + 320 + place.dx) * s, y: (m + 68 + place.dy) * s)
        }
        .accessibilityHidden(true)
    }

    private var accessibilityValue: Text {
        let time = state.isRecording ? state.position : state.duration
        let spoken = Duration.seconds(max(0, time.isFinite ? time : 0))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        switch state.mode {
        case .recording: return Text("\(spoken), recording")
        case .recordingPaused: return Text("\(spoken), recording paused")
        case .playing: return Text("\(spoken), playing")
        case .stopped: return Text("\(spoken), stopped")
        }
    }
}

/// The drawing, in the cassette's 640 × 420 space (same shapes and colours as the app icon).
private struct CassetteDrawing {
    struct Frame {
        var radii: (left: Double, right: Double)
        var leftAngle: Double
        var rightAngle: Double
        /// VU level 0…1, nil when not recording.
        var meter: Double?
        /// Recording lamp brightness 0…1.
        var lamp: Double
    }

    let frame: Frame
    let dark: Bool
    var color: TapeColor = .red

    static let leftHub = CGPoint(x: 210, y: 166)
    static let rightHub = CGPoint(x: 430, y: 166)

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let m = Reels.margin
        let s = min(size.width / (640 + 2 * m), size.height / (420 + 2 * m))
        context.translateBy(x: (size.width - 640 * s) / 2, y: (size.height - 420 * s) / 2)
        context.scaleBy(x: s, y: s)

        // Shell with a soft shadow.
        let shell = Path(roundedRect: CGRect(x: 0, y: 0, width: 640, height: 420), cornerRadius: 44, style: .continuous)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(dark ? 0.55 : 0.16), radius: 18, x: 0, y: 10))
            layer.fill(shell, with: .color(Color(hex: dark ? 0xDCD3C2 : 0xE2D7C3)))
        }
        // Light mode: a shade darker and a fine edge, so the cream shell stands out on white (owner,
        // 2026-11-07, the same as the Mac app); dark mode unchanged.
        context.fill(shell, with: vertical(dark ? 0xE9E1D1 : 0xECE3D2, dark ? 0xCBBFA9 : 0xD5C8B0, 0, 420))
        context.stroke(shell, with: .color(dark ? .white.opacity(0.08) : .black.opacity(0.12)), lineWidth: 1.5)

        // Screws.
        for p in [CGPoint(x: 30, y: 30), CGPoint(x: 610, y: 30), CGPoint(x: 30, y: 390), CGPoint(x: 610, y: 390)] {
            context.fill(circle(p, 10), with: .color(Color(hex: 0xC4B8A2)))
        }

        // Label (the title sticker on it is a SwiftUI overlay).
        let label = Path(roundedRect: CGRect(x: 44, y: 36, width: 552, height: 252), cornerRadius: 28, style: .continuous)
        context.fill(label, with: vertical(color.gradient.top, color.gradient.bottom, 36, 288))

        // Window with the reels.
        let window = Path(roundedRect: CGRect(x: 120, y: 100, width: 400, height: 132), cornerRadius: 66, style: .continuous)
        context.fill(window, with: .color(Color(hex: 0x1B1D29)))
        context.drawLayer { inside in
            inside.clip(to: window)
            let tape = GraphicsContext.Shading.color(Color(hex: 0x5A4033))
            inside.fill(circle(Self.leftHub, frame.radii.left), with: tape)
            inside.fill(circle(Self.rightHub, frame.radii.right), with: tape)
            // Faint winding rings so the tape reads as tape, not a disc.
            for (c, r) in [(Self.leftHub, frame.radii.left), (Self.rightHub, frame.radii.right)] where r > 46 {
                inside.stroke(circle(c, (r + 38) / 2), with: .color(.black.opacity(0.12)), lineWidth: 1.5)
            }
            // Glass sheen.
            inside.fill(Path(CGRect(x: 120, y: 100, width: 400, height: 132)),
                        with: .linearGradient(Gradient(colors: [.white.opacity(0.10), .white.opacity(0)]),
                                              startPoint: CGPoint(x: 120, y: 100), endPoint: CGPoint(x: 300, y: 232)))
        }
        hub(at: Self.leftHub, angle: frame.leftAngle, in: &context)
        hub(at: Self.rightHub, angle: frame.rightAngle, in: &context)

        // VU strip on the label under the window (recording only).
        if let meter = frame.meter {
            let count = 12, width = 22.0, gap = 6.0
            let start = 320 - (Double(count) * width + Double(count - 1) * gap) / 2
            let lit = Int((meter * Double(count)).rounded())
            for i in 0..<count {
                let segment = Path(roundedRect: CGRect(x: start + Double(i) * (width + gap), y: 254, width: width, height: 8), cornerRadius: 4)
                context.fill(segment, with: .color(Color(hex: 0xFFF4E8).opacity(i < lit ? 0.95 : 0.25)))
            }
        }

        // Head opening at the bottom edge, with the tape running across it.
        var head = Path()
        head.move(to: CGPoint(x: 150, y: 420))
        head.addLine(to: CGPoint(x: 490, y: 420))
        head.addLine(to: CGPoint(x: 448, y: 328))
        head.addLine(to: CGPoint(x: 192, y: 328))
        head.closeSubpath()
        context.fill(head, with: .color(Color(hex: dark ? 0xC2B6A0 : 0xCBBEA5)))
        for x in [238.0, 402.0] { context.fill(circle(CGPoint(x: x, y: 378), 13), with: .color(Color(hex: 0x2A2C38))) }
        context.fill(Path(roundedRect: CGRect(x: 298, y: 366, width: 44, height: 24), cornerRadius: 6), with: .color(Color(hex: 0x2A2C38)))
        context.fill(Path(CGRect(x: 160, y: 409, width: 320, height: 4)), with: .color(Color(hex: 0x5A4033)))

        // Recording lamp, bottom left of the shell.
        if frame.lamp > 0 {
            let lamp = CGPoint(x: 92, y: 356)
            context.fill(circle(lamp, 22), with: .radialGradient(
                Gradient(colors: [Color(hex: 0xFF3B30).opacity(0.45 * frame.lamp), Color(hex: 0xFF3B30).opacity(0)]),
                center: lamp, startRadius: 6, endRadius: 22))
            context.fill(circle(lamp, 9), with: .color(Color(hex: 0xFF3B30).opacity(0.3 + 0.7 * frame.lamp)))
        }
    }

    /// The hub: a light disc with a dark centre and six teeth that show the rotation.
    private func hub(at c: CGPoint, angle: Double, in context: inout GraphicsContext) {
        let light = GraphicsContext.Shading.color(Color(hex: 0xF4EEE2))
        context.fill(circle(c, 35), with: light)
        context.fill(circle(c, 18), with: .color(Color(hex: 0x1B1D29)))
        for i in 0..<6 {
            let a = angle + Double(i) * .pi / 3
            context.fill(circle(CGPoint(x: c.x + cos(a) * 18, y: c.y + sin(a) * 18), 5.5), with: light)
        }
    }

    private func circle(_ c: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    private func vertical(_ top: UInt32, _ bottom: UInt32, _ y0: Double, _ y1: Double) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [Color(hex: top), Color(hex: bottom)]),
                        startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1))
    }
}

/// The band.je wordmark: "Band", a little record button as the dot, "je" (band.je's header,
/// site/style.css .brand). Used as the library's title.
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "Band")
            RecordDot()
                // Large enough that the reel stays recognisable at small sizes.
                .frame(width: size * 0.6, height: size * 0.6)
                .padding(.horizontal, size * 0.04)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - size * 0.01 }
            Text(verbatim: "je")
        }
        .font(.system(size: size, weight: .bold))
        .tracking(-0.01 * size)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Band·je"))
        .accessibilityAddTraits(.isHeader)
    }
}

/// The dot in "Band●je" and the record button: a red disc with a ring and a centre cut out, so the
/// background shows through where band.je's record button is white.
struct RecordMark: Shape {
    /// Width of the cut-out ring and radius of the centre, as shares of the radius.
    var ringOuter = 0.73, ringInner = 0.59, centre = 0.37

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for f in [1, ringOuter, ringInner, centre] {
            p.addEllipse(in: CGRect(x: c.x - r * f, y: c.y - r * f, width: 2 * r * f, height: 2 * r * f))
        }
        return p
    }
}

struct RecordDot: View {
    /// The record button's own mark (`RecordButton`), on the app's background: white in light,
    /// dark in dark (owner, 6 Nov).
    var body: some View {
        ZStack {
            Circle().fill(Color(uiColor: .systemBackground))
            RecordMark(ringOuter: 0.92, ringInner: 0.84, centre: 0.3)
                .fill(Color("ButtonAccent"), style: FillStyle(eoFill: true))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Square cover art for shared audio: the cassette with its sticker (same tilt as in the app) on
/// band.je's navy, "band.je" under it. Always light, whatever the phone's appearance.
struct CoverArt: View {
    let title: String
    let duration: TimeInterval
    var color: TapeColor = .red
    static let side: CGFloat = 1024

    var body: some View {
        VStack(spacing: 24) {
            CassetteView(state: CassetteState(duration: duration, title: title, color: color))
                .frame(width: 940)
            Text(verbatim: "band.je")
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(hex: 0xF4EEE2))
        }
        .frame(width: Self.side, height: Self.side)
        // band.je's navy (owner, 6 Nov): the cream cassette stands out on it.
        .background(Color(hex: 0x262B4F))
        .environment(\.colorScheme, .light)
    }

    /// JPEG, rendered on the device.
    @MainActor static func jpeg(title: String, duration: TimeInterval, color: TapeColor = .red) -> Data? {
        let renderer = ImageRenderer(content: CoverArt(title: title, duration: duration, color: color))
        renderer.scale = 1
        return renderer.uiImage?.jpegData(compressionQuality: 0.85)
    }

    /// The recording's cover, kept next to it as `.cover-<key>.jpg` (hidden; the key changes with
    /// the title and length, so a renamed recording gets a new one). Made when missing.
    @MainActor static func file(for recording: Recording) -> URL? {
        guard recording.audio != nil else { return nil }
        let name = ".cover-\(key(for: recording)).jpg"
        let url = recording.folder.appending(path: name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let data = jpeg(title: recording.title, duration: recording.duration, color: recording.color) else { return nil }
        let old = (try? FileManager.default.contentsOfDirectory(atPath: recording.folder.path)) ?? []
        for file in old where file.hasPrefix(".cover-") { try? FileManager.default.removeItem(at: recording.folder.appending(path: file)) }
        do {
            try Storage.coordinated(writing: url, options: .forReplacing) { try data.write(to: $0, options: .atomic) }
            return url
        } catch {
            return nil
        }
    }

    nonisolated static func key(title: String, duration: TimeInterval, color: TapeColor = .red) -> String {
        var h: UInt64 = 0xcbf29ce484222325  // FNV-1a, stable across launches
        // "|3": the darker cream shell on navy (older covers are remade); the colour only when not the default.
        let colour = color == .red ? "" : "|\(color.rawValue)"
        for b in "\(title)|\(Int(duration.rounded()))\(colour)|3".utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 36)
    }

    nonisolated static func key(for recording: Recording) -> String {
        key(title: recording.title, duration: recording.duration, color: recording.color)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
