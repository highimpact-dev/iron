import ActivityKit
import SwiftUI
import WidgetKit

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(context: context)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: "dumbbell.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Resting")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(context.attributes.exerciseName)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(
                        timerInterval: context.state.startedAt...context.state.endsAt,
                        pauseTime: context.state.endsAt,
                        countsDown: true,
                        showsHours: false
                    )
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(
                        timerInterval: context.state.startedAt...context.state.endsAt,
                        countsDown: false,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text(
                    timerInterval: context.state.startedAt...context.state.endsAt,
                    pauseTime: context.state.endsAt,
                    countsDown: true,
                    showsHours: false
                )
                .monospacedDigit()
                .foregroundStyle(.tint)
                .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.tint)
            }
            .keylineTint(.accentColor)
        }
    }
}

private struct RestLockScreenView: View {
    let context: ActivityViewContext<RestActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.tint.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resting")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(context.attributes.exerciseName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
                Text(
                    timerInterval: context.state.startedAt...context.state.endsAt,
                    pauseTime: context.state.endsAt,
                    countsDown: true,
                    showsHours: false
                )
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            }

            ProgressView(
                timerInterval: context.state.startedAt...context.state.endsAt,
                countsDown: false,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.linear)
            .tint(.accentColor)
        }
    }
}
