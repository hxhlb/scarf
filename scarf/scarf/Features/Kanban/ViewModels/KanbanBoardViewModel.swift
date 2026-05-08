import Foundation
import Observation
import ScarfCore
import os

/// Drives the drag-and-drop Kanban board. Holds the column-grouped task
/// state, polls Hermes every 5s while foregrounded, and applies
/// optimistic updates around drag-drops so the UI feels instant.
///
/// **Optimistic merge.** When the user drops a card on a new column,
/// the VM records the in-flight task id + intended status, mutates the
/// local array immediately, and fires the corresponding CLI verb. Until
/// the next poll response confirms the new status, polled rows for
/// in-flight tasks are merged with the optimistic state — preventing a
/// stale poll from snapping the card back to its old column. On CLI
/// failure, the optimistic mutation is reverted and an error message
/// is surfaced.
@Observable
@MainActor
final class KanbanBoardViewModel {
    private let logger = Logger(subsystem: "com.scarf", category: "KanbanBoardViewModel")

    let context: ServerContext
    let service: KanbanService
    /// When non-nil, the board filters list/watch calls to this tenant
    /// and `New Task` pre-fills the tenant field. Used by per-project
    /// boards; global board leaves it nil.
    var tenantFilter: String?
    /// When non-nil, `New Task` pre-fills the workspace to
    /// `dir:<projectPath>` and locks it so project-scoped task
    /// creation always lands inside the project tree.
    let projectPath: String?

    init(
        context: ServerContext = .local,
        tenantFilter: String? = nil,
        projectPath: String? = nil
    ) {
        self.context = context
        self.service = KanbanService(context: context)
        self.tenantFilter = tenantFilter
        self.projectPath = projectPath
    }

    // MARK: - State

    var tasks: [HermesKanbanTask] = []
    var stats: HermesKanbanStats = .empty
    var assignees: [HermesKanbanAssignee] = []
    var isLoading = false
    var lastError: String?
    var lastPollAt: Date?

    /// Filters above the board.
    var assigneeFilter: String?       // nil = all assignees
    var showArchived: Bool = false

    /// Optimistic moves keyed by task id; cleared when the polled
    /// response includes the same status the optimistic move set.
    private var optimisticOverrides: [String: String] = [:]
    /// Tasks dropped into invalid columns produce a transient "denied"
    /// banner. Stored as an explicit error to support the Cmd-Z style
    /// undo we don't ship in v2.7.5 but want to leave room for.
    var transientNotice: String?

    // MARK: - Polling

    private var pollTask: Task<Void, Never>?

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Loading

    /// One-shot refresh. Polling drives the auto-refresh; this is
    /// exposed for explicit user-triggered reloads (e.g. the toolbar
    /// refresh button).
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let filter = KanbanListFilter(
                assignee: assigneeFilter,
                tenant: tenantFilter,
                includeArchived: showArchived
            )
            let polled = try await service.list(filter)
            mergePolledTasks(polled)
            lastPollAt = Date()
            lastError = nil

            // Stats refresh is best-effort — failure here doesn't
            // poison the board, just leaves the glance string stale.
            if let stats = try? await service.stats() {
                self.stats = stats
            }
        } catch let err as KanbanError {
            lastError = err.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Refresh the assignee picker. Cheap; called once on appear.
    func refreshAssignees() async {
        if let list = try? await service.assignees() {
            assignees = list
        }
    }

    // MARK: - Column projection

    /// Group tasks into the 5-column board layout. Triage column
    /// hides itself when empty; archived only appears when
    /// `showArchived` is on.
    func tasks(in column: KanbanBoardColumn) -> [HermesKanbanTask] {
        let raw = tasks.filter { effectiveColumn($0) == column }
        return sortColumn(raw)
    }

    /// Visible columns for the current state. Triage hidden when
    /// empty; archived hidden unless toggle is on.
    var visibleColumns: [KanbanBoardColumn] {
        var cols: [KanbanBoardColumn] = []
        if !tasks(in: .triage).isEmpty {
            cols.append(.triage)
        }
        cols.append(contentsOf: [.upNext, .running, .blocked, .done])
        if showArchived {
            cols.append(.archived)
        }
        return cols
    }

    // MARK: - Drag-drop

    /// Apply an optimistic move and fire the matching Hermes verbs.
    /// Returns immediately; the CLI calls run in the background.
    /// Inputs the drag layer must collect upstream:
    /// - `blockReason` when the destination is `.blocked`
    /// - `completeResult` when the destination is `.done`
    func attemptMove(
        taskId: String,
        to destination: KanbanBoardColumn,
        blockReason: String? = nil,
        completeResult: String? = nil
    ) {
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }
        let source = effectiveColumn(task)
        if source == destination { return }

        let plan: KanbanTransitionPlan
        do {
            plan = try KanbanService.plan(
                for: KanbanTransition(from: source, to: destination)
            )
        } catch let err as KanbanError {
            transientNotice = err.errorDescription
            return
        } catch {
            transientNotice = error.localizedDescription
            return
        }

        // Optimistic mutation — flip the local row's status to a
        // value within the destination column's range. We pick a
        // representative status per column.
        let optimisticStatus = optimisticStatus(for: destination)
        optimisticOverrides[taskId] = optimisticStatus

        let svc = service
        Task {
            do {
                for step in plan.steps {
                    try await applyStep(step, taskId: taskId, blockReason: blockReason, completeResult: completeResult, service: svc)
                }
                // Refresh once on success so the polled state catches up
                // without waiting for the 5s tick.
                await refresh()
            } catch let err as KanbanError {
                optimisticOverrides.removeValue(forKey: taskId)
                lastError = err.errorDescription
                logger.warning("kanban move failed: \(err.errorDescription ?? "", privacy: .public)")
            } catch {
                optimisticOverrides.removeValue(forKey: taskId)
                lastError = error.localizedDescription
            }
        }
    }

    /// Archive via context menu (not drag).
    func archive(taskId: String) {
        Task {
            do {
                try await service.archive(taskIds: [taskId])
                await refresh()
            } catch let err as KanbanError {
                lastError = err.errorDescription
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Reassign a task to a different profile (or clear the assignee
    /// when `profile` is nil/empty). Fires a dispatcher pass after a
    /// successful assignment so the task transitions promptly when
    /// the gateway dispatcher's own cycle is slow. Best-effort:
    /// failures surface in `lastError`. Used by the inspector's
    /// inline assignee picker.
    func reassignTask(taskId: String, to profile: String?) {
        Task {
            do {
                let normalized = (profile?.isEmpty ?? true) ? nil : profile
                try await service.assign(taskId: taskId, profile: normalized)
                if normalized != nil {
                    // Best-effort nudge.
                    _ = try? await service.dispatch(maxTasks: nil, dryRun: false)
                }
                await refresh()
            } catch let err as KanbanError {
                lastError = err.errorDescription
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Append a comment from the inspector pane.
    func comment(taskId: String, text: String) {
        Task {
            do {
                try await service.comment(taskId: taskId, text: text, author: nil)
                await refresh()
            } catch let err as KanbanError {
                lastError = err.errorDescription
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Create a new task — wired up to the New Task sheet.
    /// Fires a dispatcher pass immediately after successful creation
    /// so an assigned task transitions from `ready` → `running`
    /// promptly without waiting for whatever cadence the gateway's
    /// internal dispatcher loop runs at.
    func createTask(_ request: KanbanCreateRequest) async throws -> HermesKanbanTask {
        let task = try await service.create(request)
        if let assignee = task.assignee, !assignee.isEmpty {
            // Best-effort: failure here is non-fatal — the task still
            // exists, the user just won't see it transition to running
            // until the next gateway dispatcher tick.
            _ = try? await service.dispatch(maxTasks: nil, dryRun: false)
        }
        await refresh()
        return task
    }

    // MARK: - Private helpers

    private func mergePolledTasks(_ polled: [HermesKanbanTask]) {
        // Filter polled rows to the requested tenant if one is set —
        // belt-and-suspenders against Hermes versions that ignore
        // an empty `--tenant ""` argument.
        let filtered: [HermesKanbanTask]
        if let tenant = tenantFilter, !tenant.isEmpty {
            filtered = polled.filter { $0.tenant == tenant }
        } else {
            filtered = polled
        }
        let presentIds = Set(filtered.map(\.id))
        // Drop optimistic overrides for tasks Hermes confirmed.
        for (id, optimistic) in optimisticOverrides {
            if let row = filtered.first(where: { $0.id == id }) {
                if columnFromStatus(optimistic) == columnFromStatus(row.status) {
                    optimisticOverrides.removeValue(forKey: id)
                }
            } else if !presentIds.contains(id) {
                // Task no longer in the polled set (archived, deleted,
                // or filtered out). Drop the optimistic entry.
                optimisticOverrides.removeValue(forKey: id)
            }
        }
        tasks = filtered
    }

    /// Return the effective board column for a task — the optimistic
    /// override wins if one is in flight; otherwise the polled status.
    private func effectiveColumn(_ task: HermesKanbanTask) -> KanbanBoardColumn {
        if let overrideStatus = optimisticOverrides[task.id] {
            return columnFromStatus(overrideStatus)
        }
        return columnFromStatus(task.status)
    }

    private nonisolated func columnFromStatus(_ status: String) -> KanbanBoardColumn {
        KanbanStatus.from(status).boardColumn
    }

    private nonisolated func optimisticStatus(for column: KanbanBoardColumn) -> String {
        switch column {
        case .triage:   return "triage"
        case .upNext:   return "todo"
        case .running:  return "running"
        case .blocked:  return "blocked"
        case .done:     return "done"
        case .archived: return "archived"
        }
    }

    /// Within-column ordering. Hermes has no `position` field, so we
    /// derive ordering from `priority` (descending) then `created_at`
    /// (descending). This matches the dispatcher's actual run order
    /// — what shows up first is what runs next.
    private nonisolated func sortColumn(_ rows: [HermesKanbanTask]) -> [HermesKanbanTask] {
        rows.sorted { lhs, rhs in
            let lp = lhs.priority ?? 0
            let rp = rhs.priority ?? 0
            if lp != rp { return lp > rp }
            return (lhs.createdAt ?? "") > (rhs.createdAt ?? "")
        }
    }

    private func applyStep(
        _ step: KanbanTransitionStep,
        taskId: String,
        blockReason: String?,
        completeResult: String?,
        service: KanbanService
    ) async throws {
        switch step {
        case .dispatch:
            // The dispatcher silently skips tasks without an assignee.
            // Refusing here, with a user-actionable message, beats
            // letting Hermes lock the task into a 15-minute zombie
            // state until stale_lock reclaim kicks in.
            if let task = tasks.first(where: { $0.id == taskId }),
               (task.assignee?.isEmpty ?? true) {
                throw KanbanError.forbiddenTransition(
                    from: "Up Next",
                    to: "Running",
                    reason: "This task has no assignee. Hermes's dispatcher only spawns workers for assigned tasks. Open the task and assign a profile, or recreate it with an assignee."
                )
            }
            _ = try await service.dispatch(maxTasks: nil, dryRun: false)
        case .unblock:
            try await service.unblock(taskIds: [taskId])
        case .block(let reasonRequired):
            let reason = (blockReason?.isEmpty ?? true) ? nil : blockReason
            if reasonRequired && reason == nil {
                throw KanbanError.forbiddenTransition(
                    from: "—",
                    to: "Blocked",
                    reason: "A reason is required to mark a task blocked."
                )
            }
            try await service.block(taskId: taskId, reason: reason)
        case .complete(let resultRequired):
            let result = (completeResult?.isEmpty ?? true) ? nil : completeResult
            if resultRequired && result == nil {
                throw KanbanError.forbiddenTransition(
                    from: "—",
                    to: "Done",
                    reason: "A result summary is required to complete this task."
                )
            }
            try await service.complete(taskIds: [taskId], result: result, summary: nil, metadataJSON: nil)
        case .archive:
            try await service.archive(taskIds: [taskId])
        }
    }
}
