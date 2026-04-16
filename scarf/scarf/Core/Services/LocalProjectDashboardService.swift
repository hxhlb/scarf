import Foundation

/// Local filesystem implementation of `ProjectDashboardServicing`.
struct LocalProjectDashboardService: ProjectDashboardServicing {
    nonisolated let locator: any HermesLocator

    init(locator: any HermesLocator = LocalHermesLocator()) {
        self.locator = locator
    }

    // MARK: - Registry

    func loadRegistry() -> ProjectRegistry {
        guard let data = FileManager.default.contents(atPath: locator.projectsRegistry) else {
            return ProjectRegistry(projects: [])
        }
        do {
            return try JSONDecoder().decode(ProjectRegistry.self, from: data)
        } catch {
            print("[Scarf] Failed to decode project registry: \(error.localizedDescription)")
            return ProjectRegistry(projects: [])
        }
    }

    func saveRegistry(_ registry: ProjectRegistry) {
        let dir = locator.scarfDir
        if !FileManager.default.fileExists(atPath: dir) {
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            } catch {
                print("[Scarf] Failed to create scarf directory: \(error.localizedDescription)")
                return
            }
        }
        guard let data = try? JSONEncoder().encode(registry) else { return }
        // Pretty-print for readability (agents may read this file)
        if let pretty = try? JSONSerialization.jsonObject(with: data),
           let formatted = try? JSONSerialization.data(withJSONObject: pretty, options: [.prettyPrinted, .sortedKeys]) {
            FileManager.default.createFile(atPath: locator.projectsRegistry, contents: formatted)
        } else {
            FileManager.default.createFile(atPath: locator.projectsRegistry, contents: data)
        }
    }

    // MARK: - Dashboard

    func loadDashboard(for project: ProjectEntry) -> ProjectDashboard? {
        guard let data = FileManager.default.contents(atPath: project.dashboardPath) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(ProjectDashboard.self, from: data)
        } catch {
            print("[Scarf] Failed to decode dashboard for \(project.name): \(error.localizedDescription)")
            return nil
        }
    }

    func dashboardExists(for project: ProjectEntry) -> Bool {
        FileManager.default.fileExists(atPath: project.dashboardPath)
    }

    func dashboardModificationDate(for project: ProjectEntry) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: project.dashboardPath) else {
            return nil
        }
        return attrs[.modificationDate] as? Date
    }
}
