import SwiftUI
import ScarfCore
import ScarfDesign

/// Read-only Kanban task detail sheet for iOS. Mirrors the Mac
/// inspector's 3-tab layout (Comments | Events | Runs) but routes
/// through a `NavigationStack` for iOS-native chrome and dismisses
/// to the parent kanban view, not to the board.
///
/// No mutations in v2.7.5 — write actions land on iOS in a later
/// release via a bottom action bar with explicit verb buttons (no
/// drag-drop).
struct ScarfGoKanbanDetailSheet: View {
    let taskId: String
    let context: ServerContext

    @Environment(\.dismiss) private var dismiss

    @State private var detail: HermesKanbanTaskDetail?
    @State private var runs: [HermesKanbanRun] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab: DetailTab = .comments

    enum DetailTab: String, CaseIterable, Identifiable {
        case comments = "Comments"
        case events = "Events"
        case runs = "Runs"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(detail?.task.title ?? "Task")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task(id: taskId) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && detail == nil {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ContentUnavailableView {
                Label("Couldn't load task", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") {
                    Task { await load() }
                }
            }
        } else if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard(detail.task)
                    if let body = detail.task.body, !body.isEmpty {
                        if let attributed = try? AttributedString(markdown: body) {
                            Text(attributed)
                                .font(.body)
                        } else {
                            Text(body)
                                .font(.body)
                        }
                    }
                    Picker("Section", selection: $selectedTab) {
                        ForEach(DetailTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    switch selectedTab {
                    case .comments: commentsSection(detail.comments)
                    case .events:   eventsSection(detail.events)
                    case .runs:     runsSection
                    }
                }
                .padding()
            }
        }
    }

    private func headerCard(_ task: HermesKanbanTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ScarfBadge(task.status.lowercased(), kind: badgeKind(for: task.status))
                if let assignee = task.assignee, !assignee.isEmpty {
                    ScarfBadge(assignee, kind: .neutral)
                }
                if let workspace = task.workspaceKind {
                    ScarfBadge(workspace, kind: .neutral)
                }
                if let tenant = task.tenant, !tenant.isEmpty {
                    ScarfBadge(tenant, kind: .brand)
                }
            }
            if let priority = task.priority {
                Text("Priority \(priority)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func commentsSection(_ comments: [HermesKanbanComment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if comments.isEmpty {
                Text("No comments yet.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(comment.author)
                                .font(.subheadline)
                                .bold()
                            Text(comment.createdAt)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(comment.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(ScarfColor.backgroundSecondary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: ScarfRadius.md, style: .continuous))
                }
            }
        }
    }

    private func eventsSection(_ events: [HermesKanbanEvent]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if events.isEmpty {
                Text("No events yet.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(events) { event in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.kind)
                                .font(.subheadline)
                                .bold()
                            Text(event.createdAt)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var runsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if runs.isEmpty {
                Text("No runs yet.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(runs) { run in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            ScarfBadge(run.outcome ?? run.status, kind: outcomeKind(run.outcome ?? run.status))
                            if let profile = run.profile {
                                Text(profile)
                                    .font(.subheadline)
                            }
                            Spacer()
                            Text(run.startedAt)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let summary = run.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let err = run.error, !err.isEmpty {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(8)
                    .background(ScarfColor.backgroundSecondary.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: ScarfRadius.md, style: .continuous))
                }
            }
        }
    }

    private func badgeKind(for status: String) -> ScarfBadgeKind {
        switch KanbanStatus.from(status) {
        case .running, .ready: return .info
        case .done:            return .success
        case .blocked:         return .warning
        default:               return .neutral
        }
    }

    private func outcomeKind(_ outcome: String) -> ScarfBadgeKind {
        switch outcome.lowercased() {
        case "completed", "done":                              return .success
        case "blocked":                                        return .warning
        case "crashed", "timed_out", "spawn_failed", "failed": return .danger
        case "running":                                        return .info
        default:                                                return .neutral
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let svc = KanbanService(context: context)
        do {
            async let detailLoaded = svc.show(taskId: taskId)
            async let runsLoaded = svc.runs(taskId: taskId)
            self.detail = try await detailLoaded
            self.runs = (try? await runsLoaded) ?? []
            self.error = nil
        } catch let err as KanbanError {
            self.error = err.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}
