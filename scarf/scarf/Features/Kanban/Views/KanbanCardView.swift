import SwiftUI
import ScarfCore
import ScarfDesign
import CoreTransferable

/// Transferable wrapper for a kanban task id. We tunnel the payload
/// through `String` via `ProxyRepresentation` (no custom UTI needed)
/// because SwiftUI's drag-drop with custom-UTI `CodableRepresentation`
/// requires a registered exported type in Info.plist to round-trip
/// reliably; the proxy form skips that ceremony and consistently lands
/// drops in v15 / 26.
struct KanbanTaskRef: Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { (ref: KanbanTaskRef) in ref.id },
            importing: { (id: String) in KanbanTaskRef(id: id) }
        )
    }
}

/// Single Kanban card. Variant chrome differs by status:
/// - **Running** gets a blue left-edge accent + live shimmer
/// - **Blocked** gets a warning left-edge accent + ⚠ glyph
/// - **Done** dims to 0.7 opacity (0.55 in dark mode)
struct KanbanCardView: View {
    let task: HermesKanbanTask
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: ScarfSpace.s2) {
                titleRow
                if hasMetaRow1 {
                    metaRow1
                }
                if !task.skills.isEmpty {
                    skillsRow
                }
                footerRow
            }
            .padding(ScarfSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ScarfRadius.lg, style: .continuous)
                    .fill(ScarfColor.backgroundPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ScarfRadius.lg, style: .continuous)
                    .stroke(ScarfColor.border, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if let edgeColor {
                    Rectangle()
                        .fill(edgeColor)
                        .frame(width: 2)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                        )
                        .padding(.vertical, 4)
                }
            }
        }
        .buttonStyle(.plain)
        .scarfShadow(.sm)
        .opacity(task.isDone ? doneOpacity : 1.0)
        .draggable(KanbanTaskRef(id: task.id)) {
            // Drag preview — the live card with a heavier shadow.
            self.dragPreview
        }
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: ScarfSpace.s2) {
            statusGlyph
            Text(task.title)
                .scarfStyle(.bodyEmph)
                .foregroundStyle(ScarfColor.foregroundPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if needsAssignmentWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ScarfColor.warning)
                    .font(.system(size: 11, weight: .semibold))
                    .help("Unassigned — Hermes's dispatcher silently skips tasks with no assignee, so this task will never run automatically. Open the task and add an assignee, or recreate it with one set.")
            }
        }
    }

    /// Cards in `todo` or `ready` with no `assignee` are about to land
    /// in a silent zombie state — Hermes's dispatcher's `--json`
    /// output literally lists them under `skipped_unassigned` and
    /// moves on. Surfacing this on the card itself (vs. only inside
    /// the inspector) is the only way the user has a chance to notice
    /// before they sit there confused.
    private var needsAssignmentWarning: Bool {
        let column = KanbanStatus.from(task.status).boardColumn
        guard column == .upNext || column == .triage else { return false }
        return (task.assignee?.isEmpty ?? true)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch KanbanStatus.from(task.status) {
        case .blocked:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ScarfColor.warning)
                .font(.system(size: 11, weight: .semibold))
                .padding(.top, 2)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ScarfColor.success)
                .font(.system(size: 11, weight: .semibold))
                .padding(.top, 2)
        case .running:
            // No leading glyph — the left-edge accent + shimmer
            // already encodes the live state.
            EmptyView()
        default:
            EmptyView()
        }
    }

    private var hasMetaRow1: Bool {
        task.assignee?.isEmpty == false || task.workspaceKind != nil
    }

    private var metaRow1: some View {
        HStack(spacing: ScarfSpace.s2) {
            if let assignee = task.assignee, !assignee.isEmpty {
                assigneeChip(assignee)
            } else {
                unassignedChip
            }
            if let workspace = task.workspaceKind {
                ScarfBadge(workspace, kind: .neutral)
            }
            Spacer(minLength: 0)
        }
    }

    private func assigneeChip(_ name: String) -> some View {
        HStack(spacing: 4) {
            Text(initials(of: name))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ScarfColor.accentActive)
                .frame(width: 16, height: 16)
                .background(ScarfColor.accentTint)
                .clipShape(Circle())
            Text(name)
                .scarfStyle(.caption)
                .foregroundStyle(ScarfColor.foregroundMuted)
        }
    }

    private var unassignedChip: some View {
        Text("Unassigned")
            .scarfStyle(.caption)
            .foregroundStyle(ScarfColor.foregroundFaint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: ScarfRadius.sm, style: .continuous)
                    .stroke(
                        ScarfColor.borderStrong,
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
            )
    }

    private var skillsRow: some View {
        HStack(spacing: 4) {
            let visible = task.skills.prefix(2)
            ForEach(Array(visible.enumerated()), id: \.offset) { _, skill in
                ScarfBadge(skill, kind: .brand)
            }
            if task.skills.count > 2 {
                ScarfBadge("+\(task.skills.count - 2)", kind: .neutral)
            }
            Spacer(minLength: 0)
        }
    }

    private var footerRow: some View {
        HStack(spacing: ScarfSpace.s2) {
            Text(relativeTimeLabel)
                .scarfStyle(.caption)
                .foregroundStyle(ScarfColor.foregroundFaint)
            Spacer(minLength: 0)
            if let priority = task.priority, priority >= 70 {
                priorityIndicator(priority)
            }
        }
    }

    private func priorityIndicator(_ priority: Int) -> some View {
        let color: Color = priority >= 90 ? ScarfColor.danger : ScarfColor.warning
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 8, height: 8)
            .help("Priority \(priority)")
    }

    private var dragPreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title)
                .scarfStyle(.bodyEmph)
                .foregroundStyle(ScarfColor.foregroundPrimary)
                .lineLimit(1)
            if let assignee = task.assignee, !assignee.isEmpty {
                Text(assignee)
                    .scarfStyle(.caption)
                    .foregroundStyle(ScarfColor.foregroundMuted)
            }
        }
        .padding(.horizontal, ScarfSpace.s2)
        .padding(.vertical, 6)
        .background(ScarfColor.backgroundPrimary)
        .overlay(
            RoundedRectangle(cornerRadius: ScarfRadius.md, style: .continuous)
                .stroke(ScarfColor.accent, lineWidth: 1)
        )
        .scarfShadow(.lg)
    }

    // MARK: - Helpers

    private var edgeColor: Color? {
        switch KanbanStatus.from(task.status) {
        case .running:  return ScarfColor.info
        case .blocked:  return ScarfColor.warning
        default:        return nil
        }
    }

    private var doneOpacity: Double {
        colorScheme == .dark ? 0.55 : 0.7
    }

    /// Display string for the footer's relative time slot. The "since"
    /// reference depends on status — running tasks show how long
    /// they've been running; blocked show how long blocked, etc.
    private var relativeTimeLabel: String {
        switch KanbanStatus.from(task.status) {
        case .running:
            if let started = task.startedAt, let label = relativeShort(from: started) {
                return "running \(label)"
            }
            return "running"
        case .blocked:
            // Hermes doesn't expose blocked-since separately; fall
            // back to created_at as a coarse signal.
            if let created = task.createdAt, let label = relativeShort(from: created) {
                return "blocked \(label)"
            }
            return "blocked"
        case .done:
            if let completed = task.completedAt, let label = relativeShort(from: completed) {
                return "done \(label) ago"
            }
            return "done"
        default:
            if let created = task.createdAt, let label = relativeShort(from: created) {
                return "\(label) ago"
            }
            return ""
        }
    }

    private func relativeShort(from iso: String) -> String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return nil
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func initials(of name: String) -> String {
        let parts = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}

private extension HermesKanbanTask {
    var isDone: Bool { KanbanStatus.from(status) == .done }
}
