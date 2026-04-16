import Foundation
import os

/// On-disk payload for `~/Library/Application Support/scarf/connections.json`.
/// The file is plain JSON — no secrets live here today (API keys are not used,
/// since all remote traffic rides SSH and relies on the user's existing
/// `~/.ssh/` key material).
nonisolated struct ConnectionsFile: Codable, Sendable, Equatable {
    var remotes: [RemoteHermes]
    /// When non-nil, the app should boot with that remote active. Nil means local.
    var activeRemoteId: UUID?

    static let empty = ConnectionsFile(remotes: [], activeRemoteId: nil)
}

/// Persists the list of known remote Hermes endpoints and which one (if any) is active.
/// Actor-isolated so file I/O stays off the main thread per Swift 6 rules.
actor ConnectionStore {
    static let shared = ConnectionStore()

    private let storeURL: URL
    private let logger = Logger(subsystem: "com.scarf", category: "ConnectionStore")
    private var cached: ConnectionsFile?

    init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
            self.storeURL = appSupport
                .appendingPathComponent("scarf", isDirectory: true)
                .appendingPathComponent("connections.json")
        }
    }

    // MARK: - Load / Save

    func load() -> ConnectionsFile {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL) else {
            cached = .empty
            return .empty
        }
        do {
            let decoded = try JSONDecoder().decode(ConnectionsFile.self, from: data)
            cached = decoded
            return decoded
        } catch {
            logger.error("Failed to decode connections.json: \(error.localizedDescription)")
            cached = .empty
            return .empty
        }
    }

    private func persist(_ file: ConnectionsFile) throws {
        let dir = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: storeURL, options: [.atomic])
        cached = file
    }

    // MARK: - Mutations

    /// Insert a new remote or update an existing one (matched by id).
    func upsert(_ remote: RemoteHermes) throws {
        var file = load()
        if let idx = file.remotes.firstIndex(where: { $0.id == remote.id }) {
            file.remotes[idx] = remote
        } else {
            file.remotes.append(remote)
        }
        try persist(file)
    }

    /// Remove a remote. If the removed remote was active, the active selection
    /// falls back to local.
    func remove(id: UUID) throws {
        var file = load()
        file.remotes.removeAll { $0.id == id }
        if file.activeRemoteId == id {
            file.activeRemoteId = nil
        }
        try persist(file)
    }

    /// Set the active connection. `.local` clears `activeRemoteId`; `.remote` pins it.
    func setActive(_ connection: HermesConnection) throws {
        var file = load()
        switch connection {
        case .local:
            file.activeRemoteId = nil
        case .remote(let r):
            // Refuse to activate a remote we don't know about — prevents dangling ids.
            guard file.remotes.contains(where: { $0.id == r.id }) else {
                throw ConnectionStoreError.unknownRemote(r.id)
            }
            file.activeRemoteId = r.id
        }
        try persist(file)
    }

    // MARK: - Reads

    func allRemotes() -> [RemoteHermes] {
        load().remotes
    }

    func activeConnection() -> HermesConnection {
        let file = load()
        if let id = file.activeRemoteId, let r = file.remotes.first(where: { $0.id == id }) {
            return .remote(r)
        }
        return .local
    }
}

enum ConnectionStoreError: Error, LocalizedError {
    case unknownRemote(UUID)

    var errorDescription: String? {
        switch self {
        case .unknownRemote(let id):
            return "Cannot activate unknown remote \(id.uuidString)"
        }
    }
}
