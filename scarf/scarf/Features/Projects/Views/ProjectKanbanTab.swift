import SwiftUI
import ScarfCore
import ScarfDesign

/// Per-project Kanban tab. Wraps `KanbanBoardView` with the project's
/// tenant pre-applied + the workspace pre-pinned to the project
/// directory. On first appearance it mints the project's
/// `scarf:<slug>` tenant if one isn't already on disk.
///
/// Capability-gated by `HermesCapabilities.hasKanban` upstream — this
/// view is only added to the project tab list when v0.12+ is detected.
struct ProjectKanbanTab: View {
    @Environment(\.serverContext) private var serverContext
    let project: ProjectEntry

    @State private var resolvedTenant: String?
    @State private var resolveError: String?

    var body: some View {
        Group {
            if let tenant = resolvedTenant {
                KanbanBoardView(
                    context: serverContext,
                    tenantFilter: tenant,
                    projectPath: project.path,
                    projectName: project.name
                )
            } else if let error = resolveError {
                VStack(spacing: ScarfSpace.s3) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(ScarfColor.warning)
                    Text("Couldn't set up the project's Kanban tenant.")
                        .scarfStyle(.headline)
                    Text(error)
                        .scarfStyle(.caption)
                        .foregroundStyle(ScarfColor.foregroundMuted)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        resolveError = nil
                        resolveTenant()
                    }
                    .buttonStyle(ScarfSecondaryButton())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: project.id) {
            resolveTenant()
        }
    }

    private func resolveTenant() {
        let resolver = KanbanTenantResolver(context: serverContext)
        // Always-mint behaviour: even if the project board is empty
        // and the user hasn't created a task yet, the tenant is
        // pre-allocated so AGENTS.md surfaces it on the next chat.
        do {
            resolvedTenant = try resolver.resolveOrMint(for: project)
        } catch {
            resolveError = error.localizedDescription
        }
    }
}
