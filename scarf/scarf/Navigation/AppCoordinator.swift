import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case insights = "Insights"
    case sessions = "Sessions"
    case activity = "Activity"
    case projects = "Projects"
    case chat = "Chat"
    case memory = "Memory"
    case skills = "Skills"
    case tools = "Tools"
    case mcpServers = "MCP Servers"
    case gateway = "Gateway"
    case cron = "Cron"
    case health = "Health"
    case logs = "Logs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .insights: return "chart.bar"
        case .sessions: return "bubble.left.and.bubble.right"
        case .activity: return "bolt.horizontal"
        case .projects: return "square.grid.2x2"
        case .chat: return "text.bubble"
        case .memory: return "brain"
        case .skills: return "lightbulb"
        case .tools: return "wrench.and.screwdriver"
        case .mcpServers: return "puzzlepiece.extension"
        case .gateway: return "antenna.radiowaves.left.and.right"
        case .cron: return "clock.arrow.2.circlepath"
        case .health: return "stethoscope"
        case .logs: return "doc.text"
        case .settings: return "gearshape"
        }
    }
}

@Observable
final class AppCoordinator {
    var selectedSection: SidebarSection = .dashboard
    var selectedSessionId: String?
    var selectedProjectName: String?

    /// Identifies which Hermes instance the app is currently bound to.
    /// Bootstrapped at app launch from `ConnectionStore.shared.activeConnection()`.
    ///
    /// `didSet` mirrors the value into `ConnectionProvider` so service facades
    /// constructed after the switch (fresh ViewModels produced by the
    /// `.id(activeConnection)` rebuild in the view tree) target the new Hermes.
    /// In-session switching "just works" — no per-VM env plumbing required.
    var activeConnection: HermesConnection = .local {
        didSet {
            ConnectionProvider.set(activeConnection)
        }
    }

    /// Load the persisted active connection from disk. Call this once at app
    /// startup before any service construction fires. Returns the restored
    /// connection so the caller can log / surface to telemetry.
    ///
    /// Synchronizes `ConnectionProvider` FIRST, then the observable property.
    /// Otherwise any service whose default init reads the provider during the
    /// brief window between `activeConnection =` and `didSet` would see stale state.
    ///
    /// For remote connections, warms the locator cache on a detached task before
    /// updating the observable property. Facade inits in the view tree run
    /// synchronously on the main actor; a cold `$HOME` SSH probe during view
    /// construction would freeze the UI up to 15 s. Warming here pushes that
    /// wait into the bootstrap phase where the UI already shows a spinner.
    @discardableResult
    func bootstrapActiveConnection() async -> HermesConnection {
        let restored = await ConnectionStore.shared.activeConnection()
        ConnectionProvider.set(restored)
        if case .remote(let r) = restored {
            await Task.detached { _ = RemoteHermesLocator.forRemote(r) }.value
        }
        activeConnection = restored
        return restored
    }
}
