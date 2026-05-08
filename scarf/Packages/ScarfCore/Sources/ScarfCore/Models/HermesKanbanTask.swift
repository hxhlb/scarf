import Foundation

/// One task from `hermes kanban list --json` (v0.12+).
///
/// Hermes ships a SQLite-backed task board under `~/.hermes/kanban.db`.
/// v2.6 surfaced this as a read-only list; v2.7.5 lifts it to a full
/// drag-and-drop board with the complete write surface (`create`,
/// `claim`, `complete`, `block`, `unblock`, `archive`, `assign`,
/// `link`/`unlink`, `comment`, `dispatch`).
///
/// Hermes has no `update` verb — `priority` / `title` / `body` /
/// `tenant` are write-once at create time. Mutations after that are
/// expressed as state transitions (status, assignee) or new comments.
public struct HermesKanbanTask: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let body: String?
    public let assignee: String?
    public let status: String          // archived | blocked | done | ready | running | todo | triage
    public let priority: Int?
    public let tenant: String?
    public let workspaceKind: String?  // scratch | worktree | dir
    public let workspacePath: String?
    public let createdBy: String?
    public let createdAt: String?      // ISO timestamp
    public let startedAt: String?
    public let completedAt: String?
    public let result: String?
    public let skills: [String]

    // v2.7.5 fields exposed by `kanban show --json` and `kanban watch`.
    public let idempotencyKey: String?
    public let lastHeartbeatAt: String?
    public let maxRuntimeSeconds: Int?
    public let currentRunId: Int?

    public init(
        id: String,
        title: String,
        body: String? = nil,
        assignee: String? = nil,
        status: String,
        priority: Int? = nil,
        tenant: String? = nil,
        workspaceKind: String? = nil,
        workspacePath: String? = nil,
        createdBy: String? = nil,
        createdAt: String? = nil,
        startedAt: String? = nil,
        completedAt: String? = nil,
        result: String? = nil,
        skills: [String] = [],
        idempotencyKey: String? = nil,
        lastHeartbeatAt: String? = nil,
        maxRuntimeSeconds: Int? = nil,
        currentRunId: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.assignee = assignee
        self.status = status
        self.priority = priority
        self.tenant = tenant
        self.workspaceKind = workspaceKind
        self.workspacePath = workspacePath
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.result = result
        self.skills = skills
        self.idempotencyKey = idempotencyKey
        self.lastHeartbeatAt = lastHeartbeatAt
        self.maxRuntimeSeconds = maxRuntimeSeconds
        self.currentRunId = currentRunId
    }

    enum CodingKeys: String, CodingKey {
        case id, title, body, assignee, status, priority, tenant
        case workspaceKind = "workspace_kind"
        case workspacePath = "workspace_path"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case result, skills
        case idempotencyKey = "idempotency_key"
        case lastHeartbeatAt = "last_heartbeat_at"
        case maxRuntimeSeconds = "max_runtime_seconds"
        case currentRunId = "current_run_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.body = try c.decodeIfPresent(String.self, forKey: .body)
        self.assignee = try c.decodeIfPresent(String.self, forKey: .assignee)
        self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        self.tenant = try c.decodeIfPresent(String.self, forKey: .tenant)
        self.workspaceKind = try c.decodeIfPresent(String.self, forKey: .workspaceKind)
        self.workspacePath = try c.decodeIfPresent(String.self, forKey: .workspacePath)
        self.createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
        // Hermes emits timestamps as Unix integer seconds for tasks
        // returned from `create`/`show`/`list` (its SQLite columns are
        // INTEGER) but ISO-8601 strings in some other paths. Normalize
        // both shapes into ISO-8601 strings so UI code only deals with
        // one type.
        self.createdAt = try Self.decodeFlexibleTimestamp(c, forKey: .createdAt)
        self.startedAt = try Self.decodeFlexibleTimestamp(c, forKey: .startedAt)
        self.completedAt = try Self.decodeFlexibleTimestamp(c, forKey: .completedAt)
        self.result = try c.decodeIfPresent(String.self, forKey: .result)
        self.skills = try c.decodeIfPresent([String].self, forKey: .skills) ?? []
        self.idempotencyKey = try c.decodeIfPresent(String.self, forKey: .idempotencyKey)
        self.lastHeartbeatAt = try Self.decodeFlexibleTimestamp(c, forKey: .lastHeartbeatAt)
        self.maxRuntimeSeconds = try c.decodeIfPresent(Int.self, forKey: .maxRuntimeSeconds)
        self.currentRunId = try c.decodeIfPresent(Int.self, forKey: .currentRunId)
    }

    /// Decode a timestamp that may arrive as a Unix integer or an
    /// ISO-8601 string. Returns the ISO-8601 string form so downstream
    /// code only deals with one type.
    static func decodeFlexibleTimestamp(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String? {
        if !container.contains(key) { return nil }
        // Try the SQLite-style integer first (most common from Hermes).
        if let unix = try? container.decodeIfPresent(Double.self, forKey: key) {
            let date = Date(timeIntervalSince1970: unix)
            return Self.isoFormatter.string(from: date)
        }
        // Fall back to a plain string.
        return try container.decodeIfPresent(String.self, forKey: key)
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Status enum (typed view of the wire string)

/// Typed mirror of Hermes's status enum. Models keep `status: String` for
/// forward compatibility with new statuses Hermes might add; UI code uses
/// `KanbanStatus.from(_:)` to map known values into typed categories and
/// fall back to `.unknown` for anything new.
public enum KanbanStatus: String, Sendable, CaseIterable, Identifiable {
    case triage
    case todo
    case ready
    case running
    case blocked
    case done
    case archived
    case unknown

    public var id: String { rawValue }

    public static func from(_ raw: String) -> KanbanStatus {
        KanbanStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    /// Coarse 5-column board grouping. `triage` is a column; `todo` and
    /// `ready` collapse to one ("Up Next"); everything else maps 1:1.
    /// `archived` lives outside the board (toggle).
    public var boardColumn: KanbanBoardColumn {
        switch self {
        case .triage:                return .triage
        case .todo, .ready, .unknown: return .upNext
        case .running:               return .running
        case .blocked:               return .blocked
        case .done:                  return .done
        case .archived:              return .archived
        }
    }
}

public enum KanbanBoardColumn: String, Sendable, CaseIterable, Identifiable {
    case triage
    case upNext
    case running
    case blocked
    case done
    case archived

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .triage:   return "Triage"
        case .upNext:   return "Up Next"
        case .running:  return "Running"
        case .blocked:  return "Blocked"
        case .done:     return "Done"
        case .archived: return "Archived"
        }
    }

    /// Visible columns in the default board layout. `archived` appears
    /// only when the "Show archived" toggle is on. `triage` is shown
    /// only when the board has at least one triage task (collapsed
    /// otherwise to keep the default layout focused).
    public static let defaultVisible: [KanbanBoardColumn] = [
        .triage, .upNext, .running, .blocked, .done
    ]
}
