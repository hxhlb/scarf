import Foundation

/// Signature every local or remote project-dashboard service must implement.
/// Local = reads/writes `~/.hermes/scarf/projects.json` + sibling dashboard JSON
/// via `FileManager`. Remote = `ssh host cat` / `ssh host sh -c 'cat > ...'`
/// piped through `SSHCommandRunner`.
protocol ProjectDashboardServicing: Sendable {
    nonisolated var locator: any HermesLocator { get }

    func loadRegistry() -> ProjectRegistry
    func saveRegistry(_ registry: ProjectRegistry)
    func loadDashboard(for project: ProjectEntry) -> ProjectDashboard?
    func dashboardExists(for project: ProjectEntry) -> Bool
    func dashboardModificationDate(for project: ProjectEntry) -> Date?
}
