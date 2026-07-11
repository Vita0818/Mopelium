#if canImport(SwiftUI)
import SwiftUI

enum MopeliumSection: String, CaseIterable, Identifiable {
    case chat
    case tasks
    case sources
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .tasks: return "Tasks"
        case .sources: return "Sources"
        case .settings: return "Settings"
        }
    }

    var gloss: String {
        switch self {
        case .chat: return "对话"
        case .tasks: return "任务"
        case .sources: return "来源"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .tasks: return "checklist"
        case .sources: return "square.stack.3d.up"
        case .settings: return "gearshape"
        }
    }
}

struct MopeliumMacRootView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var selection: MopeliumSection = .chat

    var body: some View {
        NavigationSplitView {
            MopeliumSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 280)
        } detail: {
            ZStack {
                MopeliumTheme.pageGradient(scheme).ignoresSafeArea()
                detail
            }
        }
        .navigationTitle("")
        .frame(minWidth: 1040, minHeight: 680)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .chat:
            MopeliumChatScreen()
        case .tasks:
            MopeliumTasksScreen()
        case .sources:
            MopeliumSourcesScreen()
        case .settings:
            MopeliumSettingsScreen()
        }
    }
}

#if DEBUG
struct MopeliumMacRootView_Previews: PreviewProvider {
    static var previews: some View {
        MopeliumMacRootView()
            .frame(width: 1100, height: 720)
    }
}
#endif
#endif
