// SPDX-License-Identifier: GPL-3.0-only
import AppIntents
import SwiftUI
import WidgetKit

@main
struct BandjeWatchWidgets: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        RecordControl()
    }
}

// MARK: - Complications and Smart Stack

struct StatusEntry: TimelineEntry {
    var date: Date
    var status: WatchStatus

    /// High while recording, so the Smart Stack puts Band·je on top.
    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: status.isRecording ? 100 : (status.pending > 0 ? 5 : 1))
    }
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { StatusEntry(date: .now, status: WatchStatus()) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now, status: context.isPreview ? WatchStatus() : .current))
    }

    /// One entry: the app reloads after start, stop, a marker and a delivery. The time counts by
    /// itself (`Text(timerInterval:)`).
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StatusEntry>) -> Void) {
        completion(Timeline(entries: [StatusEntry(date: .now, status: .current)], policy: .never))
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchStatus.widgetKind, provider: StatusProvider()) { entry in
            StatusView(status: entry.status)
                .containerBackground(for: .widget) {}
        }
        .configurationDisplayName(Text(verbatim: "Band·je"))
        .description(Text("Record from your wrist."))
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct StatusView: View {
    let status: WatchStatus
    @Environment(\.widgetFamily) private var family
    /// True in the Smart Stack, false on a watch face.
    @Environment(\.showsWidgetContainerBackground) private var inSmartStack

    var body: some View {
        switch family {
        case .accessoryCircular: Circular(status: status)
        case .accessoryCorner: Corner(status: status)
        case .accessoryInline: Inline(status: status)
        default:
            if inSmartStack { SmartStack(status: status) } else { Rectangular(status: status) }
        }
    }
}

/// The recorded time, counting by itself; standing still while paused.
private func timer(_ status: WatchStatus) -> Text {
    if let paused = status.pausedAt { return Text(verbatim: WatchFormat.clock(paused)) }
    return Text(timerInterval: (status.recordingSince ?? .now)...Date.distantFuture, countsDown: false)
}

private func recordingLabel(_ status: WatchStatus) -> String {
    if let paused = status.pausedAt {
        return String(localized: "Band·je, recording paused, \(WatchFormat.spoken(paused))")
    }
    return String(localized: "Band·je, recording, \(WatchFormat.spoken(Date.now.timeIntervalSince(status.recordingSince ?? .now)))")
}

/// "Recording" or "Paused", after the state mark.
private func stateLine(_ status: WatchStatus) -> Text {
    status.isPaused ? Text("Paused") : Text("Recording")
}

private func waitingLine(_ n: Int) -> String {
    String(localized: "\(n) waiting for iPhone", comment: "Complication: recordings waiting for the iPhone")
}

/// The red recording dot, or two bars (pause) while paused.
private struct RedDot: View {
    var size: CGFloat
    var paused = false
    var body: some View {
        Group {
            if paused {
                HStack(spacing: size * 0.3) {
                    Capsule().frame(width: size * 0.38, height: size * 1.2)
                    Capsule().frame(width: size * 0.38, height: size * 1.2)
                }
                .frame(height: size * 1.2)
            } else {
                Circle().frame(width: size, height: size)
            }
        }
        .foregroundStyle(Color.bandjeRedText)
        .widgetAccentable()
    }
}

private struct Circular: View {
    let status: WatchStatus

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if status.isRecording {
                VStack(spacing: 1) {
                    RedDot(size: 6, paused: status.isPaused)
                    timer(status)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 4)
            } else {
                // The app's record button, with its dot punched out so it shows when tinted (owner, 9 Nov).
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    RecordGlyph(size: side * 0.76, ring: max(2, side * 0.05), gap: max(1.5, side * 0.05), dot: nil)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .widgetAccentable()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: status.isRecording ? recordingLabel(status) : String(localized: "Band·je, record")))
    }
}

private struct Corner: View {
    let status: WatchStatus

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                RecordGlyph(size: side * 0.72, ring: max(1.5, side * 0.05), gap: max(1.5, side * 0.05), dot: nil)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .widgetAccentable()
        }
        .widgetLabel {
            if status.isRecording {
                Text("\(timer(status)) · \(WatchFormat.markers(status.markers))")
                    .foregroundStyle(Color.bandjeRedText)
            } else {
                Text("Record")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: status.isRecording ? recordingLabel(status) : String(localized: "Band·je, record")))
    }
}

private struct Rectangular: View {
    let status: WatchStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                RedDot(size: 5, paused: status.isPaused)
                if status.isRecording { stateLine(status) } else { Text(verbatim: "Band·je") }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.bandjeRedText)
            .widgetAccentable()
            if status.isRecording {
                timer(status)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(verbatim: WatchFormat.markers(status.markers))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap to record")
                    .font(.system(size: 15, weight: .semibold))
                if status.pending > 0 {
                    Text(verbatim: waitingLine(status.pending))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    private var spoken: String {
        if status.isRecording {
            return recordingLabel(status) + ", " + WatchFormat.markers(status.markers) + "."
        }
        var parts = ["Band·je", String(localized: "Tap to record")]
        if status.pending > 0 { parts.append(String(localized: "\(status.pending) recordings waiting for iPhone")) }
        return parts.joined(separator: ". ") + "."
    }
}

private struct Inline: View {
    let status: WatchStatus

    var body: some View {
        if status.isRecording {
            Label {
                if status.isPaused { Text("\(timer(status)) · paused") } else { Text("\(timer(status)) · recording") }
            } icon: {
                Image(systemName: status.isPaused ? "pause.circle" : "record.circle")
            }
        } else if status.pending > 0 {
            Text("Band·je · \(status.pending) waiting")
        } else {
            Text(verbatim: "Band·je")
        }
    }
}

/// Smart Stack (design at 1.5×: button 64, time 38, cassette 74).
private struct SmartStack: View {
    let status: WatchStatus

    var body: some View {
        HStack(spacing: 10) {
            if status.isRecording {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        RedDot(size: 5, paused: status.isPaused)
                        stateLine(status)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.bandjeRedText)
                    .widgetAccentable()
                    timer(status)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(verbatim: WatchFormat.markers(status.markers))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                WatchCassette(width: 49)
            } else {
                RecordGlyph(size: 43, ring: 2, gap: 2, dot: nil)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Record")
                        .font(.system(size: 15, weight: .semibold))
                    if status.pending > 0 {
                        Text(verbatim: waitingLine(status.pending))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: status.isRecording
            ? recordingLabel(status) + ", " + WatchFormat.markers(status.markers) + "."
            : String(localized: "Band·je, record")))
    }
}

// MARK: - Control (Control Centre, Smart Stack, Action button on Apple Watch Ultra)

struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WatchStatus.controlKind, provider: Provider()) { isRecording in
            ControlWidgetToggle(isOn: isRecording, action: RecordingControlIntent()) {
                Label(isRecording ? "Recording" : "Record", systemImage: isRecording ? "stop.circle.fill" : "record.circle")
                    .controlWidgetActionHint(isRecording ? "Stop Recording" : "Start Recording")
            }
            .tint(.bandjeRed)
        }
        .displayName("Start/Stop Recording")
        .description("Starts or stops a recording in Bandje.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { WatchStatus.current.isRecording }
    }
}
