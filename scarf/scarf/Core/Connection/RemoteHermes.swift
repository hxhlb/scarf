import Foundation

/// Persisted record describing how to reach a remote Hermes instance.
/// Stored in `connections.json` at `~/Library/Application Support/scarf/`.
///
/// Remote access today runs entirely over SSH — `cat` / `tee` / `tail` / `sqlite3`
/// executed on the remote host, plus `ssh user@host hermes ...` for CLI and ACP.
/// No HTTP API client is used. If Hermes publishes an API schema in a future
/// release, this record can grow `remoteAPIHost` / `remoteAPIPort` fields back.
nonisolated struct RemoteHermes: Codable, Sendable, Equatable, Hashable, Identifiable {
    let id: UUID
    var nickname: String
    var host: String
    var user: String
    var sshPort: Int
    var sshKeyPath: String?
    var remoteBinaryPath: String
    var remoteHermesHome: String?

    init(
        id: UUID = UUID(),
        nickname: String,
        host: String,
        user: String,
        sshPort: Int = 22,
        sshKeyPath: String? = nil,
        remoteBinaryPath: String = "hermes",
        remoteHermesHome: String? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.host = host
        self.user = user
        self.sshPort = sshPort
        self.sshKeyPath = sshKeyPath
        self.remoteBinaryPath = remoteBinaryPath
        self.remoteHermesHome = remoteHermesHome
    }

    var sshTarget: String { "\(user)@\(host)" }
}
