import Foundation

/// Filter options for `hermes kanban list --json`. Empty filter (default)
/// returns all non-archived tasks across all tenants.
public struct KanbanListFilter: Sendable, Equatable {
    public var status: KanbanStatus?
    public var assignee: String?
    /// `nil` = all tenants. Empty string → "untagged" (NULL tenant)
    /// — Hermes treats `--tenant ""` as "no tenant".
    public var tenant: String?
    public var includeArchived: Bool
    /// Show only my profile's tasks (`--mine`).
    public var mineOnly: Bool

    public init(
        status: KanbanStatus? = nil,
        assignee: String? = nil,
        tenant: String? = nil,
        includeArchived: Bool = false,
        mineOnly: Bool = false
    ) {
        self.status = status
        self.assignee = assignee
        self.tenant = tenant
        self.includeArchived = includeArchived
        self.mineOnly = mineOnly
    }

    public static let all = KanbanListFilter()

    /// Build the argv suffix after `["kanban", "list"]`.
    public func argv() -> [String] {
        var args: [String] = ["--json"]
        if mineOnly {
            args.append("--mine")
        }
        if let status, status != .unknown {
            args.append(contentsOf: ["--status", status.rawValue])
        }
        if let assignee, !assignee.isEmpty {
            args.append(contentsOf: ["--assignee", assignee])
        }
        if let tenant {
            args.append(contentsOf: ["--tenant", tenant])
        }
        if includeArchived {
            args.append("--archived")
        }
        return args
    }
}

/// Filter options for `hermes kanban watch --json` (live event stream).
public struct KanbanWatchFilter: Sendable, Equatable {
    public var assignee: String?
    public var tenant: String?
    public var kinds: [KanbanEventKind]
    public var intervalSeconds: Double

    public init(
        assignee: String? = nil,
        tenant: String? = nil,
        kinds: [KanbanEventKind] = [],
        intervalSeconds: Double = 0.5
    ) {
        self.assignee = assignee
        self.tenant = tenant
        self.kinds = kinds
        self.intervalSeconds = intervalSeconds
    }

    public static let all = KanbanWatchFilter()

    public func argv() -> [String] {
        var args: [String] = []
        if let assignee, !assignee.isEmpty {
            args.append(contentsOf: ["--assignee", assignee])
        }
        if let tenant, !tenant.isEmpty {
            args.append(contentsOf: ["--tenant", tenant])
        }
        if !kinds.isEmpty {
            let joined = kinds.map(\.rawValue).joined(separator: ",")
            args.append(contentsOf: ["--kinds", joined])
        }
        if intervalSeconds > 0 && intervalSeconds != 0.5 {
            args.append(contentsOf: ["--interval", String(format: "%.2f", intervalSeconds)])
        }
        return args
    }
}

/// Summary of one `hermes kanban dispatch` pass. Used by the optional
/// "Dispatch now" button to show what happened.
public struct KanbanDispatchSummary: Sendable, Equatable, Codable {
    public let promoted: Int
    public let failed: Int
    public let dryRun: Bool
    public let perTask: [DispatchedTask]

    public init(
        promoted: Int = 0,
        failed: Int = 0,
        dryRun: Bool = false,
        perTask: [DispatchedTask] = []
    ) {
        self.promoted = promoted
        self.failed = failed
        self.dryRun = dryRun
        self.perTask = perTask
    }

    public struct DispatchedTask: Sendable, Equatable, Codable, Identifiable {
        public var id: String { taskId }
        public let taskId: String
        public let decision: String   // "promoted" | "skipped" | "failed"
        public let reason: String?

        public init(taskId: String, decision: String, reason: String? = nil) {
            self.taskId = taskId
            self.decision = decision
            self.reason = reason
        }

        enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
            case decision
            case reason
        }
    }

    enum CodingKeys: String, CodingKey {
        case promoted
        case failed
        case dryRun = "dry_run"
        case perTask = "per_task"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.promoted = try c.decodeIfPresent(Int.self, forKey: .promoted) ?? 0
        self.failed = try c.decodeIfPresent(Int.self, forKey: .failed) ?? 0
        self.dryRun = try c.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
        self.perTask = try c.decodeIfPresent([DispatchedTask].self, forKey: .perTask) ?? []
    }
}
