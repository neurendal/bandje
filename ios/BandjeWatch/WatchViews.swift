// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import WatchKit

/// Sizes per case (design, pt): 42 mm, 46 mm (reference) and Ultra.
struct WatchMetrics {
    var recordButton: CGFloat
    var time: CGFloat
    var button: CGFloat

    static let current: WatchMetrics = {
        let size = WKInterfaceDevice.current().screenBounds.size
        if size.width >= 205, size.height >= 250 { return WatchMetrics(recordButton: 104, time: 50, button: 58) }
        if size.width >= 196 { return WatchMetrics(recordButton: 100, time: 48, button: 56) }
        return WatchMetrics(recordButton: 88, time: 42, button: 52)
    }()
}

struct RootView: View {
    @Environment(WatchRecorder.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.phase {
            case .idle: StartView()
            case .onboarding: NoticeOnboardingView()
            case .recording: RecordingView()
            case .stopped(let rec): StoppedView(recording: rec)
            case .failed(let failure): FailureView(failure: failure)
            }
        }
        .background(Color.black)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.becameActive()
                model.sendPending()
            }
        }
        .alert("Sent to your iPhone", isPresented: Bindable(model).showsSent) {
            Button("OK") {}
        }
    }
}

// MARK: - S1 Start, S1c Waiting for iPhone

private struct StartView: View {
    @Environment(WatchRecorder.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsQueue = false
    private let metrics = WatchMetrics.current

    var body: some View {
        NavigationStack {
            VStack(spacing: typeSize.isAccessibilitySize ? 10 : 14) {
                Button {
                    Task { await model.record() }
                } label: {
                    RecordGlyph(size: metrics.recordButton)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Record"))

                if !model.pending.isEmpty {
                    Button {
                        showsQueue = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "iphone")
                                .font(.system(size: 12))
                            Text("Waiting for iPhone (\(model.pending.count))")
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: typeSize.isAccessibilitySize ? 19 : 14, weight: .medium))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .frame(minHeight: 34)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(model.pending.count) recordings waiting for iPhone"))
                    .accessibilityHint(Text("Tap to see them"))
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { BrandLabel() }
            }
            .navigationDestination(isPresented: $showsQueue) { QueueView() }
        }
    }
}

/// "Band·je" in red, top left.
private struct BrandLabel: View {
    var body: some View {
        Text(verbatim: "Band·je")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.bandjeRedText)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct QueueView: View {
    @Environment(WatchRecorder.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var lineSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption2) private var footerSize: CGFloat = 12

    var body: some View {
        List {
            ForEach(model.pending.reversed()) { rec in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: QueueFormat.day(rec.created))
                        .font(.system(size: titleSize, weight: .semibold))
                    Text(verbatim: QueueFormat.meta(rec))
                        .font(.system(size: lineSize))
                        .foregroundStyle(.white.opacity(0.62))
                    Label {
                        Text("waiting for iPhone")
                    } icon: {
                        Image(systemName: "iphone")
                    }
                    .labelStyle(TightLabelStyle())
                    .font(.system(size: lineSize))
                    .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: QueueFormat.spoken(rec)))
                .listRowBackground(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.12)))
            }
            Text("Moves to your iPhone automatically when it's nearby.")
                .font(.system(size: footerSize))
                .foregroundStyle(.white.opacity(0.55))
                .listRowBackground(Color.clear)
        }
        .navigationTitle(Text("Waiting for iPhone"))
        .onChange(of: model.pending.isEmpty) { _, empty in
            // Everything arrived: the list has nothing left to say.
            if empty { dismiss() }
        }
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

private enum QueueFormat {
    /// "8 nov 10:30" (the day without dots, as in the iPhone's titles, and the time).
    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMM")
        let day = f.string(from: date).replacingOccurrences(of: ".", with: "")
        return day + " " + date.formatted(date: .omitted, time: .shortened)
    }

    /// "8 november 10:30" for VoiceOver.
    static func spokenDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMMM")
        return f.string(from: date) + ", " + date.formatted(date: .omitted, time: .shortened)
    }

    /// "12 min" (seconds below a minute).
    static func length(_ seconds: Double, width: Duration.UnitsFormatStyle.UnitWidth = .abbreviated) -> String {
        let d = Duration.seconds(max(1, seconds.rounded()))
        if seconds < 60 { return d.formatted(.units(allowed: [.seconds], width: width)) }
        return d.formatted(.units(allowed: [.hours, .minutes], width: width, maximumUnitCount: 2))
    }

    static func markers(_ n: Int) -> String {
        n == 0 ? String(localized: "no markers", comment: "A recording without markers") : WatchFormat.markers(n)
    }

    /// "12 min · 3 markers".
    static func meta(_ rec: WatchRecording) -> String {
        length(rec.duration) + " · " + markers(rec.markers.count)
    }

    /// "8 november 10:30, 12 minuten, 3 markers, wacht op iPhone."
    static func spoken(_ rec: WatchRecording) -> String {
        [spokenDay(rec.created), length(rec.duration, width: .wide), markers(rec.markers.count),
         String(localized: "waiting for iPhone")].joined(separator: ", ")
    }
}

// MARK: - S5 First time

private struct NoticeOnboardingView: View {
    @Environment(WatchRecorder.self) private var model
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14

    var body: some View {
        NavigationStack { content }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                RecordGlyph(size: 26, ring: 2, gap: 2, dot: .bandjeRed)
                    .accessibilityHidden(true)
                Text("Let people know")
                    .font(.system(size: titleSize, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Let others know you're recording. In some countries and at work, this is required.")
                    .font(.system(size: bodySize))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await model.acceptNotice() }
                } label: {
                    Text("Got it")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, 4)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { BrandLabel() }
        }
    }
}

// MARK: - S2 Recording, S2b Marker, S3 Dimmed, G1 Five minutes left

private struct RecordingView: View {
    @Environment(WatchRecorder.self) private var model
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmsStop = false
    private let metrics = WatchMetrics.current

    private var ax: Bool { typeSize.isAccessibilitySize }

    private var timeSize: CGFloat {
        if ax { return (metrics.time * 0.72).rounded() }
        // h:mm:ss (from an hour, and so with the 5 minutes card) is wider.
        return model.spokenElapsed >= 3590 || model.showsLimitWarning ? (metrics.time * 0.78).rounded() : metrics.time
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.showsLimitWarning {
                    LimitCard()
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    if !dimmed, !ax, !model.showsLimitWarning {
                        LevelMeter()
                            .padding(.bottom, 6)
                            .opacity(model.isPaused ? 0.3 : 1)
                    }
                    if typeSize < .accessibility3 {
                        time
                            .font(.system(size: timeSize, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .tracking(-0.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(.white.opacity(dimmed || model.isPaused ? 0.55 : 1))
                    }
                    counter
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.isPaused
                                    ? Text("Recording paused, \(WatchFormat.spoken(model.spokenElapsed))")
                                    : Text("Recording, \(WatchFormat.spoken(model.spokenElapsed))"))
                .accessibilityValue(Text(verbatim: WatchFormat.markers(model.markers.count)))
                .accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 0)
                if !dimmed {
                    buttons
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .ignoresSafeArea(edges: .bottom)
            .animation(.easeOut(duration: 0.2), value: model.showsLimitWarning)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 5) {
                        if model.isPaused {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Paused")
                        } else {
                            Circle()
                                .fill(dimmed ? Color.bandjeDimRed : Color.bandjeRedText)
                                .frame(width: 8, height: 8)
                            Text("Recording")
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.isPaused ? Color.white.opacity(0.7) : dimmed ? Color.bandjeDimLabel : Color.bandjeRedText)
                    .accessibilityHidden(true)
                }
            }
            .confirmationDialog(Text("Stop the recording?"), isPresented: $confirmsStop, titleVisibility: .visible) {
                Button(role: .destructive) {
                    model.stop()
                } label: {
                    Text("Stop recording")
                }
                Button(role: .cancel) {} label: {
                    Text("Keep recording")
                }
            }
            .onChange(of: model.phase) { _, phase in
                // Stopped by a limit or the Action button while the question was open.
                if phase != .recording { confirmsStop = false }
            }
        }
    }

    /// The running clock, or the recorded time standing still while paused. Dimmed (wrist down,
    /// Always On) watchOS draws the timer's seconds as "--" and updates once a minute, so it shows
    /// "● REC" with the whole minutes under it instead (owner, 2026-11-11); no blinking.
    @ViewBuilder private var time: some View {
        if model.isPaused {
            Text(verbatim: WatchFormat.clock(model.elapsed))
        } else if let start = model.timerStart {
            if dimmed {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.bandjeDimRed)
                            .frame(width: (timeSize * 0.26).rounded(), height: (timeSize * 0.26).rounded())
                        Text(verbatim: "REC")
                    }
                    // On the recording's minutes (from its start), not the clock's.
                    TimelineView(.periodic(from: start, by: 60)) { context in
                        Text(verbatim: Self.minutes(context.date.timeIntervalSince(start)))
                            .font(.system(size: (timeSize * 0.42).rounded(), weight: .medium, design: .rounded))
                            .monospacedDigit()
                    }
                }
            } else {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
            }
        }
    }

    /// "10 min", "1 hr 5 min" (whole minutes, in the system's words).
    static func minutes(_ seconds: TimeInterval) -> String {
        let whole = (max(0, seconds) / 60).rounded(.down) * 60
        return Duration.seconds(whole).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    private var counter: some View {
        let flashing = model.markerFlash != nil
        // Dimmed, the red dot is next to REC above (was here before the REC view).
        return HStack(spacing: 5) {
            Text(verbatim: WatchFormat.markers(model.markers.count))
        }
        .font(.system(size: ax ? 17 : 14, weight: flashing ? .semibold : .medium))
        .foregroundStyle(flashing ? Color.bandjeRedText : .white.opacity(dimmed ? 0.45 : 0.62))
        .animation(.easeOut(duration: 0.2), value: flashing)
    }

    /// Mark, Pause and Stop, side by side (three equal capsules fit every case size).
    private var buttons: some View {
        let height = ax ? metrics.button + 4 : metrics.button
        let flash = model.markerFlash
        let icon: CGFloat = ax ? 20 : 17
        return HStack(spacing: 6) {
            Button {
                model.mark()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(flash != nil ? Color.white : Color.bandjeRedText)
                    if let flash {
                        Text(verbatim: "\(flash)")
                            .font(.system(size: ax ? 19 : 16, weight: .semibold))
                            .monospacedDigit()
                    }
                }
                .font(.system(size: icon))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background {
                    if flash != nil { Capsule().fill(Color.bandjeRed) }
                }
                .glassEffect(.regular.interactive(), in: Capsule())
                .overlay {
                    if flash != nil {
                        Capsule().strokeBorder(Color.bandjeRed.opacity(0.35), lineWidth: 3).padding(-3)
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Mark"))
            .accessibilityValue(flash.map { Text("Marker \($0)") } ?? Text(verbatim: ""))
            .animation(.easeOut(duration: 0.2), value: flash)

            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.isPaused ? "record.circle" : "pause.fill")
                    .font(.system(size: model.isPaused ? icon + 3 : icon, weight: .semibold))
                    .foregroundStyle(model.isPaused ? Color.bandjeRedText : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPaused ? Text("Resume") : Text("Pause"))

            Button {
                confirmsStop = true
            } label: {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white)
                    .frame(width: icon + 1, height: icon + 1)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Stop recording"))
        }
    }
}

/// Nine bars, 3 × 22 pt, following the input level. Only while the screen is awake.
private struct LevelMeter: View {
    @Environment(WatchRecorder.self) private var model
    private static let shape: [CGFloat] = [0.35, 0.6, 0.85, 0.5, 1, 0.7, 0.45, 0.8, 0.4]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let level = CGFloat(model.level())
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(Self.shape.indices, id: \.self) { i in
                    // Each bar breathes on its own phase (as the design's animation), scaled by the level.
                    let wobble = 0.65 + 0.35 * sin(t * (5 + Double(i % 3) * 1.7) + Double(i) * 1.3)
                    let fraction = min(1, Self.shape[i] * (0.4 + 0.6 * CGFloat(wobble)) * level * 1.25)
                    Capsule()
                        .fill(Color.bandjeRedText)
                        .frame(width: 3, height: max(3, 22 * fraction))
                }
            }
            .frame(height: 22)
            .animation(.easeOut(duration: 0.1), value: level)
        }
        .accessibilityHidden(true)
    }
}

private struct LimitCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("5 minutes left")
                .font(.system(size: 14, weight: .semibold))
            Text("Recordings can be up to 2 hours.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - S4 Stopped

private struct StoppedView: View {
    @Environment(WatchRecorder.self) private var model
    let recording: WatchRecording

    private var meta: String {
        WatchFormat.clock(recording.duration) + " · " + WatchFormat.markers(recording.markers.count)
    }

    var body: some View {
        VStack(spacing: 1) {
            VStack(spacing: 1) {
                WatchCassette(width: 60)
                Text("Saved")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.top, 6)
                Text(verbatim: QueueFormat.day(recording.created))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                Text(verbatim: meta)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                Label {
                    Text("Sending to your iPhone")
                } icon: {
                    Image(systemName: "iphone")
                }
                .labelStyle(TightLabelStyle())
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.top, 3)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: spoken))
            Spacer(minLength: 4)
            Button {
                model.dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                .frame(height: 40)
                .glassEffect(.regular.interactive(), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .task(id: recording.id) {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled, model.phase == .stopped(recording) { model.dismiss() }
        }
    }

    /// "Opgeslagen. 8 november, 10:30. 12 minuten 34, 3 markers. Gaat naar je iPhone."
    private var spoken: String {
        [String(localized: "Saved"), QueueFormat.spokenDay(recording.created),
         WatchFormat.spoken(recording.duration) + ", " + WatchFormat.markers(recording.markers.count),
         String(localized: "Sending to your iPhone")].joined(separator: ". ") + "."
    }
}

// MARK: - G2, G3, G4 and a recorder that cannot start

private struct FailureView: View {
    @Environment(WatchRecorder.self) private var model
    let failure: WatchRecorder.Failure
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var metaSize: CGFloat = 13

    private var kept: WatchRecording? {
        switch failure {
        case .storage(let rec), .battery(let rec): rec
        default: nil
        }
    }

    private var title: String {
        switch failure {
        case .micDenied: String(localized: "No microphone")
        case .storage(nil), .battery(nil), .cannotRecord: String(localized: "Can't record")
        default: String(localized: "Recording stopped")
        }
    }

    private var message: String {
        let savedLine = kept == nil ? "" : " " + String(localized: "What you recorded has been saved.")
        switch failure {
        case .storage: return String(localized: "Your Watch is almost out of storage.") + savedLine
        case .battery: return String(localized: "Battery is almost empty.") + savedLine
        case .micDenied:
            return String(localized: "Band·je can only record with the microphone. Turn it on in Settings › Privacy & Security › Microphone.")
        case .cannotRecord:
            return String(localized: "The microphone is in use by another app. Try again in a moment.")
        }
    }

    var body: some View {
        NavigationStack { content }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: "!")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(failure == .micDenied ? Color.white : Color.bandjeYellow))
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: message)
                    .font(.system(size: bodySize))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                if let kept {
                    Text(verbatim: QueueFormat.day(kept.created) + " · " + WatchFormat.clock(kept.duration)
                         + " · " + WatchFormat.markers(kept.markers.count))
                        .font(.system(size: metaSize))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Button {
                    model.dismiss()
                } label: {
                    Text("OK")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, 4)
        }
        .toolbar {
            if failure == .micDenied {
                ToolbarItem(placement: .topBarLeading) { BrandLabel() }
            }
        }
        .onAppear {
            AccessibilityNotification.Announcement(title + ". " + message).post()
        }
    }
}
