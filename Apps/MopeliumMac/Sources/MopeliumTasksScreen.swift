#if canImport(SwiftUI)
import SwiftUI

struct MopeliumTasksScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            MopeliumPageHeader(
                title: "Tasks",
                subtitle: "Event and trigger driven search-and-summarize jobs."
            )
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 14) {
                    MopeliumGlassCard {
                        VStack(spacing: 0) {
                            ForEach(MopeliumMockData.tasks) { task in
                                TaskRow(task: task)
                                if task.id != MopeliumMockData.tasks.last?.id {
                                    TaskDivider()
                                }
                            }
                        }
                    }

                    MopeliumEmptyState(
                        title: "No background workers in v0.4",
                        message: "This screen models the task surface only. Scheduling and trigger execution stay outside the chat workflow.",
                        systemName: "clock.badge"
                    )
                    .frame(height: 220)
                }
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TaskRow: View {
    let task: MopeliumTaskItem
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MopeliumIconBadge(systemName: iconName, status: task.status)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(task.title)
                        .font(MopeliumType.headline(15, .semibold))
                        .foregroundStyle(MopeliumTheme.primaryText(scheme))
                    Spacer(minLength: 0)
                    MopeliumStatusBadge(status: task.status, label: statusLabel)
                }

                HStack(spacing: 9) {
                    MetadataPill(text: task.trigger)
                    Text(task.lastRun)
                        .font(MopeliumType.mono(12))
                        .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                }

                Text(task.metadata)
                    .font(MopeliumType.caption(12, .medium))
                    .foregroundStyle(MopeliumTheme.secondaryText(scheme))
            }
        }
        .padding(.vertical, 12)
    }

    private var iconName: String {
        switch task.status {
        case .queued:
            return "tray"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .done:
            return "checkmark"
        case .failed:
            return "exclamationmark"
        case .local, .enabled, .disabled:
            return "circle"
        }
    }

    private var statusLabel: String {
        switch task.status {
        case .queued: return "Queued"
        case .running: return "Running"
        case .done: return "Done"
        case .failed: return "Failed"
        case .local: return "Local"
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        }
    }
}

private struct MetadataPill: View {
    let text: String

    var body: some View {
        MopeliumStatusBadge(status: .local, label: text)
    }
}

private struct TaskDivider: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(MopeliumTheme.stroke(scheme).opacity(0.65))
            .frame(height: 1)
            .padding(.leading, 56)
    }
}

#if DEBUG
struct MopeliumTasksScreen_Previews: PreviewProvider {
    static var previews: some View {
        MopeliumTasksScreen()
            .frame(width: 900, height: 700)
    }
}
#endif
#endif
