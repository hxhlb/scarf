import SwiftUI

struct ContentView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var didBootstrap = false

    var body: some View {
        // Gate the real UI on bootstrap completion. Without this, `.id()` would
        // first evaluate against `activeConnection = .local` (the default), then
        // again after `bootstrapActiveConnection` restores the persisted remote —
        // causing a full VM teardown/rebuild cycle + wasted queries against a
        // `~/.hermes/` that may not even exist for remote-only users.
        if didBootstrap {
            ConnectionScopedRoot()
                .id(coordinator.activeConnection)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    await coordinator.bootstrapActiveConnection()
                    didBootstrap = true
                }
        }
    }
}

/// All long-lived, connection-bound state lives here so the `.id()` rebuild in
/// `ContentView` can tear it down and reinstantiate it. `fileWatcher` and
/// `chatViewModel` used to live at `scarfApp` scope, where `.id()` couldn't
/// reach them — moving them down means their `deinit` / observable teardown
/// fires when the active connection changes.
private struct ConnectionScopedRoot: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var fileWatcher = HermesFileWatcher()
    @State private var chatViewModel = ChatViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailView
        }
        .environment(fileWatcher)
        .environment(chatViewModel)
        .onAppear {
            fileWatcher.startWatching()
        }
        .onDisappear {
            fileWatcher.stopWatching()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch coordinator.selectedSection {
        case .dashboard:
            DashboardView()
        case .insights:
            InsightsView()
        case .sessions:
            SessionsView()
        case .activity:
            ActivityView()
        case .projects:
            ProjectsView()
        case .chat:
            ChatView()
        case .memory:
            MemoryView()
        case .skills:
            SkillsView()
        case .tools:
            ToolsView()
        case .gateway:
            GatewayView()
        case .cron:
            CronView()
        case .health:
            HealthView()
        case .logs:
            LogsView()
        case .settings:
            SettingsView()
        }
    }
}
