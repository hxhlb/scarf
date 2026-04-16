import Foundation

/// Public facade for project-dashboard persistence. Dispatches to a local or
/// remote `ProjectDashboardServicing` conformer based on the connection.
struct ProjectDashboardService: Sendable {
    let impl: any ProjectDashboardServicing

    init(connection: HermesConnection = ConnectionProvider.current) {
        switch connection {
        case .local:
            self.impl = LocalProjectDashboardService()
        case .remote(let r):
            self.impl = RemoteProjectDashboardService(
                remote: r,
                locator: RemoteHermesLocator.forRemote(r)
            )
        }
    }

    nonisolated var locator: any HermesLocator { impl.locator }

    func loadRegistry() -> ProjectRegistry { impl.loadRegistry() }
    func saveRegistry(_ registry: ProjectRegistry) { impl.saveRegistry(registry) }
    func loadDashboard(for project: ProjectEntry) -> ProjectDashboard? { impl.loadDashboard(for: project) }
    func dashboardExists(for project: ProjectEntry) -> Bool { impl.dashboardExists(for: project) }
    func dashboardModificationDate(for project: ProjectEntry) -> Date? { impl.dashboardModificationDate(for: project) }
}
