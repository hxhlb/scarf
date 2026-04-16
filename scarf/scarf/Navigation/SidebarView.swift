import SwiftUI

struct SidebarView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator
        List(selection: $coordinator.selectedSection) {
            Section("Monitor") {
                ForEach([SidebarSection.dashboard, .insights, .sessions, .activity]) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            Section("Projects") {
                ForEach([SidebarSection.projects]) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            Section("Interact") {
                ForEach([SidebarSection.chat, .memory, .skills]) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            Section("Manage") {
                ForEach([SidebarSection.tools, .gateway, .cron, .health, .logs, .settings]) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Scarf")
        .safeAreaInset(edge: .bottom) {
            ConnectionBadge(connection: coordinator.activeConnection) {
                coordinator.selectedSection = .settings
            }
        }
    }
}

/// Small footer in the sidebar showing which Hermes Scarf is currently bound to.
/// Clicking it jumps to Settings where the user can change the selection.
private struct ConnectionBadge: View {
    let connection: HermesConnection
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(connection.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.4))
        .overlay(alignment: .top) {
            Divider()
        }
        .help("Active Hermes connection — click to change")
    }

    private var dotColor: Color {
        switch connection {
        case .local: return .secondary
        case .remote: return .green
        }
    }

    private var iconName: String {
        switch connection {
        case .local: return "laptopcomputer"
        case .remote: return "network"
        }
    }
}
