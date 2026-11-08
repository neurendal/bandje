// SPDX-License-Identifier: GPL-3.0-only
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct BandjeWidgets: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
        RecordControl()
    }
}

// MARK: - Live Activity and Dynamic Island

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            LockScreenView(title: context.attributes.title, state: context.state)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MiniCassette(isPaused: context.state.isPaused)
                        .frame(width: 44)
                        .padding(.leading, 6)
                        .padding(.top, 10)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Clock(state: context.state)
                            .font(.title2.weight(.light))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Controls(isPaused: context.state.isPaused)
                        .padding(.top, 4)
                }
            } compactLeading: {
                MiniCassette(isPaused: context.state.isPaused)
                    .frame(width: 30)
            } compactTrailing: {
                Clock(state: context.state)
                    .frame(maxWidth: 52)
            } minimal: {
                Lamp(isPaused: context.state.isPaused)
            }
            .keylineTint(.red)
        }
    }
}

private struct LockScreenView: View {
    let title: String
    let state: RecordingAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Lamp(isPaused: state.isPaused)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Clock(state: state)
                    .font(.title2.weight(.light))
            }
            Spacer(minLength: 8)
            Controls(isPaused: state.isPaused)
        }
        .padding(16)
    }
}

/// The red recording lamp; hollow while paused.
/// Bandje's cassette in miniature (the app icon's shapes and colours), with the recording lamp:
/// red while recording, dimmed while paused. Live Activities cannot animate, so the reels stand still.
private struct MiniCassette: View {
    let isPaused: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, s = w / 64
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                    .fill(Color(red: 0.96, green: 0.94, blue: 0.89))
                RoundedRectangle(cornerRadius: 3.5 * s, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.94, green: 0.42, blue: 0.29), Color(red: 0.84, green: 0.27, blue: 0.16)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 54 * s, height: 25 * s)
                    .offset(x: 5 * s, y: 4 * s)
                Capsule()
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.16))
                    .frame(width: 38 * s, height: 13 * s)
                    .offset(x: 13 * s, y: 10 * s)
                ForEach([21.0, 43.0], id: \.self) { x in
                    Circle()
                        .fill(Color(red: 0.96, green: 0.93, blue: 0.89))
                        .frame(width: 8 * s, height: 8 * s)
                        .offset(x: (x - 4) * s, y: 12.5 * s)
                }
                Circle()
                    .fill(Color.red.opacity(isPaused ? 0.35 : 1))
                    .frame(width: 6 * s, height: 6 * s)
                    .offset(x: 7 * s, y: 32 * s)
            }
            .frame(width: w, height: 42 * s)
        }
        .aspectRatio(64.0 / 42.0, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(isPaused ? Text("Paused") : Text("Recording"))
    }
}

private struct Lamp: View {
    let isPaused: Bool

    var body: some View {
        Image(systemName: isPaused ? "pause.circle.fill" : "record.circle")
            .font(.title3)
            .foregroundStyle(.red)
            .accessibilityLabel(isPaused ? Text("Paused") : Text("Recording"))
    }
}

/// Recorded time: counts on its own while recording, stands still while paused.
private struct Clock: View {
    let state: RecordingAttributes.ContentState

    var body: some View {
        Group {
            if state.isPaused {
                Text(Duration.seconds(state.elapsed).formatted(.time(pattern: state.elapsed >= 3600 ? .hourMinuteSecond : .minuteSecond)))
            } else {
                Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

private struct Controls: View {
    let isPaused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(intent: PauseRecordingIntent()) {
                Image(systemName: isPaused ? "record.circle" : "pause.fill")
                    .frame(width: 22, height: 22)
            }
            .accessibilityLabel(isPaused ? Text("Resume") : Text("Pause"))
            Button(intent: StopRecordingIntent()) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.red)
                    .frame(width: 22, height: 22)
            }
            .accessibilityLabel(Text("Stop"))
        }
        .font(.title3)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(.secondary)
    }
}

// MARK: - Control (Control Centre, Lock Screen, Action button)

struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: RecordingControl.kind, provider: Provider()) { isRecording in
            ControlWidgetToggle(isOn: isRecording, action: RecordingToggleIntent()) {
                Label(isRecording ? "Recording" : "Record", systemImage: isRecording ? "stop.circle.fill" : "record.circle")
            }
            .tint(.red)
        }
        .displayName("Record")
        .description("Starts or stops a recording in Bandje.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { RecordingControl.isRecording }
    }
}
