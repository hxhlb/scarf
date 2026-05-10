import SwiftUI
import ScarfCore
import ScarfDesign

/// Full drag-and-drop Kanban board. Renders the visible columns side
/// by side, supports drag-drop for column transitions, and slides in
/// a side-pane inspector when a card is tapped.
///
/// Two flavors:
/// - **Global**: pass `tenantFilter: nil` and `projectPath: nil`.
/// - **Per-project**: pass the project's `kanbanTenant` slug + the
///   project path so the New Task sheet pre-fills the workspace and
///   tenant.
struct KanbanBoardView: View {
    @State private var viewModel: KanbanBoardViewModel
    @Environment(\.hermesCapabilities) private var capabilitiesStore

    /// When non-nil, a project board hosts this view. Drives header
    /// chrome (subtitle, hidden tenant filter) and create-sheet
    /// defaults.
    let projectName: String?

    init(
        context: ServerContext,
        tenantFilter: String? = nil,
        projectPath: String? = nil,
        projectName: String? = nil,
        sessionStartedAt: Date? = nil
    ) {
        let vm = KanbanBoardViewModel(
            context: context,
            tenantFilter: tenantFilter,
            projectPath: projectPath
        )
        vm.sessionStartedAt = sessionStartedAt
        // Default the toggle on when the handoff seeded a baseline,
        // off otherwise. The pill in the toolbar lets the user flip it.
        vm.filterBySessionStart = sessionStartedAt != nil
        _viewModel = State(initialValue: vm)
        self.projectName = projectName
    }

    /// Convenience read for the v0.13 diagnostics flag — gates the
    /// max_retries field, hallucination banner, diagnostics rendering,
    /// and the auto-blocked reason banner. Pre-v0.13 hosts get the
    /// v2.7.5 surface unchanged. Treats a missing store as "off" so
    /// harness contexts (Previews) don't accidentally surface gated UI.
    private var supportsKanbanDiagnostics: Bool {
        capabilitiesStore?.capabilities.hasKanbanDiagnostics ?? false
    }

    @State private var inspectorTaskId: String?
    @State private var showingCreateSheet = false
    @State private var blockSheetTaskId: String?
    @State private var blockSheetTitle: String = ""
    @State private var blockSheetDestination: KanbanBoardColumn = .blocked
    @State private var completeSheetTaskId: String?
    @State private var completeSheetTitle: String = ""

    /// Cached gating state — refreshed on appear + after a successful
    /// `Enable now` click. `.disabled` triggers the toolset-off hint
    /// above the board so a user staring at an empty board has a
    /// clear next step. `.unknown` and `.enabled` suppress the hint.
    @State private var toolsetState: KanbanToolsetState?
    @State private var isEnablingToolset = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScarfDivider()
            if let err = viewModel.lastError {
                errorBanner(err)
            }
            if let notice = viewModel.transientNotice {
                noticeBanner(notice)
            }
            if shouldShowToolsetDisabledHint {
                toolsetDisabledBanner
            }
            HStack(spacing: 0) {
                boardArea
                if inspectorTaskId != nil {
                    ScarfDivider()
                        .frame(width: 1)
                    inspectorPane
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(ScarfColor.backgroundPrimary)
        .onAppear {
            viewModel.startPolling()
            Task { await viewModel.refreshAssignees() }
            Task { await refreshToolsetState() }
        }
        .onDisappear { viewModel.stopPolling() }
        .sheet(isPresented: $showingCreateSheet) {
            KanbanCreateSheet(
                assignees: viewModel.assignees,
                tenantPrefill: viewModel.tenantFilter,
                projectWorkspacePath: viewModel.projectPath,
                supportsKanbanDiagnostics: supportsKanbanDiagnostics
            ) { request in
                _ = try await viewModel.createTask(request)
            }
        }
        .sheet(isPresented: blockSheetBinding) {
            KanbanBlockReasonSheet(taskTitle: blockSheetTitle) { reason in
                if let taskId = blockSheetTaskId {
                    viewModel.attemptMove(
                        taskId: taskId,
                        to: blockSheetDestination,
                        blockReason: reason
                    )
                }
                blockSheetTaskId = nil
            }
        }
        .sheet(isPresented: completeSheetBinding) {
            KanbanCompleteResultSheet(taskTitle: completeSheetTitle) { result in
                if let taskId = completeSheetTaskId {
                    viewModel.attemptMove(
                        taskId: taskId,
                        to: .done,
                        completeResult: result
                    )
                }
                completeSheetTaskId = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ScarfPageHeader(
            "Kanban",
            subtitle: subtitle
        ) {
            HStack(spacing: ScarfSpace.s2) {
                glanceText
                if viewModel.sessionStartedAt != nil {
                    sessionStartedFilterPill
                }
                if viewModel.tenantFilter == nil {
                    assigneeFilterMenu
                }
                Toggle("Show archived", isOn: $viewModel.showArchived)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Show archived tasks")
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(ScarfGhostButton())
                .help("Refresh now")
                Button {
                    showingCreateSheet = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .buttonStyle(ScarfPrimaryButton())
            }
        }
    }

    /// Toggle pill that appears only when the chat → Kanban hand-off
    /// seeded a baseline timestamp. Tap to flip between "tasks
    /// created since this chat opened" (filtered) and "all tasks for
    /// this tenant" (unfiltered). The lens is approximate — Hermes
    /// doesn't track per-session task linkage in this version, so
    /// the time window is a best-effort proxy.
    private var sessionStartedFilterPill: some View {
        Button {
            viewModel.filterBySessionStart.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.filterBySessionStart
                    ? "clock.fill" : "clock")
                Text(sessionStartedPillLabel)
                    .scarfStyle(.caption)
            }
            .padding(.horizontal, ScarfSpace.s2)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    (viewModel.filterBySessionStart
                        ? ScarfColor.accent
                        : ScarfColor.foregroundFaint).opacity(0.16)
                )
            )
            .foregroundStyle(
                viewModel.filterBySessionStart
                    ? ScarfColor.accent
                    : ScarfColor.foregroundMuted
            )
        }
        .buttonStyle(.plain)
        .help(sessionStartedPillHelp)
    }

    private var sessionStartedPillLabel: String {
        guard let started = viewModel.sessionStartedAt else {
            return "Since chat opened"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return viewModel.filterBySessionStart
            ? "Since \(formatter.string(from: started))"
            : "All tasks"
    }

    private var sessionStartedPillHelp: String {
        viewModel.filterBySessionStart
            ? "Showing tasks created after the chat opened. Tap to show all tenant tasks."
            : "Showing all tasks for this tenant. Tap to filter to tasks created after the chat opened."
    }

    private var subtitle: String {
        if let projectName, let tenant = viewModel.tenantFilter, !tenant.isEmpty {
            return "\(projectName) · tenant \(tenant)"
        }
        return "Hermes task board"
    }

    private var glanceText: some View {
        let text = viewModel.stats.glanceString
        return Text(text.isEmpty ? " " : text)
            .scarfStyle(.caption)
            .foregroundStyle(ScarfColor.foregroundMuted)
            .frame(minWidth: 60)
    }

    private var assigneeFilterMenu: some View {
        Menu {
            Button("All assignees") { viewModel.assigneeFilter = nil }
            if !viewModel.assignees.isEmpty {
                Divider()
                ForEach(viewModel.assignees) { row in
                    Button(row.profile) { viewModel.assigneeFilter = row.profile }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(viewModel.assigneeFilter ?? "All")
                    .scarfStyle(.caption)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    // MARK: - Board area

    private var boardArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ScarfSpace.s4) {
                ForEach(viewModel.visibleColumns, id: \.self) { column in
                    KanbanColumnView(
                        column: column,
                        tasks: viewModel.tasks(in: column),
                        isLive: column == .running && isLive,
                        readyPillCount: column == .upNext ? readyCount : 0,
                        onTaskTap: { task in
                            inspectorTaskId = task.id
                        },
                        onCreate: { showingCreateSheet = true },
                        onDrop: { ref in
                            handleDrop(ref.id, on: column)
                        },
                        canCreate: column == .upNext || column == .triage,
                        supportsKanbanDiagnostics: supportsKanbanDiagnostics,
                        effectiveHallucinationGate: { viewModel.effectiveHallucinationGate($0) }
                    )
                }
                Spacer(minLength: ScarfSpace.s4)
            }
            .padding(ScarfSpace.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorPane: some View {
        if let taskId = inspectorTaskId,
           let task = viewModel.tasks.first(where: { $0.id == taskId }) {
            KanbanInspectorPane(
                service: viewModel.service,
                taskId: taskId,
                availableAssignees: viewModel.assignees,
                supportsKanbanDiagnostics: supportsKanbanDiagnostics,
                effectiveHallucinationGate: { viewModel.effectiveHallucinationGate($0) },
                onClose: { inspectorTaskId = nil },
                onClaim: {
                    viewModel.attemptMove(taskId: taskId, to: .running)
                    inspectorTaskId = nil
                },
                onComplete: {
                    completeSheetTaskId = taskId
                    completeSheetTitle = task.title
                },
                onBlock: {
                    blockSheetTaskId = taskId
                    blockSheetTitle = task.title
                    blockSheetDestination = .blocked
                },
                onUnblock: {
                    viewModel.attemptMove(taskId: taskId, to: .upNext)
                    inspectorTaskId = nil
                },
                onArchive: {
                    viewModel.archive(taskId: taskId)
                    inspectorTaskId = nil
                },
                onReassign: { profile in
                    viewModel.reassignTask(taskId: taskId, to: profile)
                },
                onVerifyHallucination: {
                    viewModel.verifyHallucination(taskId: taskId)
                },
                onRejectHallucination: {
                    viewModel.rejectHallucination(taskId: taskId)
                    // Card vanishes from active board after archive — close
                    // the inspector so it doesn't dangle on a deleted task.
                    inspectorTaskId = nil
                }
            )
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ taskId: String, on destination: KanbanBoardColumn) {
        guard let task = viewModel.tasks.first(where: { $0.id == taskId }) else { return }
        // Sheets first when the transition needs user input.
        switch destination {
        case .blocked:
            blockSheetTaskId = taskId
            blockSheetTitle = task.title
            blockSheetDestination = .blocked
        case .done:
            // Manual checkoffs from running don't strictly need a result,
            // but we offer the sheet anyway so users can record one
            // when relevant. The move fires regardless on submit.
            if KanbanStatus.from(task.status) == .running {
                completeSheetTaskId = taskId
                completeSheetTitle = task.title
            } else {
                viewModel.attemptMove(taskId: taskId, to: destination)
            }
        default:
            viewModel.attemptMove(taskId: taskId, to: destination)
        }
    }

    private var blockSheetBinding: Binding<Bool> {
        Binding(
            get: { blockSheetTaskId != nil },
            set: { if !$0 { blockSheetTaskId = nil } }
        )
    }

    private var completeSheetBinding: Binding<Bool> {
        Binding(
            get: { completeSheetTaskId != nil },
            set: { if !$0 { completeSheetTaskId = nil } }
        )
    }

    // MARK: - Helpers

    private var isLive: Bool {
        guard let lastPoll = viewModel.lastPollAt else { return false }
        return Date().timeIntervalSince(lastPoll) < 6
    }

    /// Tasks currently in `ready` (a Hermes status that the dispatcher
    /// will promote to `running` next tick). Surfaced as a pill on the
    /// To Do column header.
    private var readyCount: Int {
        viewModel.tasks.filter { KanbanStatus.from($0.status) == .ready }.count
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ScarfColor.warning)
            Text(message)
                .scarfStyle(.caption)
                .foregroundStyle(ScarfColor.foregroundPrimary)
            Spacer()
            Button {
                viewModel.lastError = nil
                Task { await viewModel.refresh() }
            } label: {
                Text("Retry")
                    .scarfStyle(.caption)
            }
            .buttonStyle(ScarfGhostButton())
        }
        .padding(.horizontal, ScarfSpace.s3)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScarfColor.warning.opacity(0.12))
    }

    /// Show the toolset-off banner only when the host genuinely lacks
    /// the toolset AND there's reason to surface it (the user is
    /// looking at an empty board, or has an empty per-project board).
    /// We don't surface the banner on a board that already has tasks,
    /// since the user can clearly see kanban activity is happening
    /// somewhere — the gating is a teaching moment for the empty case.
    private var shouldShowToolsetDisabledHint: Bool {
        guard case .disabled = toolsetState else { return false }
        return viewModel.tasks.isEmpty
    }

    private var toolsetDisabledBanner: some View {
        HStack(spacing: ScarfSpace.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ScarfColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agents in chat can't create Kanban tasks")
                    .scarfStyle(.captionStrong)
                    .foregroundStyle(ScarfColor.foregroundPrimary)
                Text("The `kanban` toolset isn't enabled for the chat platform, so the agent has zero kanban tools in its schema.")
                    .scarfStyle(.caption)
                    .foregroundStyle(ScarfColor.foregroundMuted)
            }
            Spacer(minLength: ScarfSpace.s2)
            Button {
                Task { await enableToolsetFromBanner() }
            } label: {
                if isEnablingToolset {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Enable now").scarfStyle(.caption)
                }
            }
            .buttonStyle(ScarfSecondaryButton())
            .disabled(isEnablingToolset)
        }
        .padding(.horizontal, ScarfSpace.s3)
        .padding(.vertical, ScarfSpace.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScarfColor.warning.opacity(0.12))
    }

    private func refreshToolsetState() async {
        let detector = KanbanToolsetDetector(context: viewModel.context)
        let state = await detector.detect()
        await MainActor.run {
            self.toolsetState = state
        }
    }

    private func enableToolsetFromBanner() async {
        await MainActor.run { isEnablingToolset = true }
        let enabler = KanbanToolsetEnabler(context: viewModel.context)
        let result = await enabler.enable()
        await MainActor.run {
            isEnablingToolset = false
            switch result {
            case .enabled:
                viewModel.transientNotice =
                    "Kanban tools enabled. Start a new chat to pick this up."
            case .failed(let message):
                viewModel.transientNotice =
                    "Couldn't enable: \(message)"
            }
        }
        await refreshToolsetState()
    }

    private func noticeBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(ScarfColor.info)
            Text(message)
                .scarfStyle(.caption)
                .foregroundStyle(ScarfColor.foregroundPrimary)
            Spacer()
            Button {
                viewModel.transientNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(ScarfGhostButton())
        }
        .padding(.horizontal, ScarfSpace.s3)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScarfColor.info.opacity(0.12))
    }
}
