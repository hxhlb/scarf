import Foundation

/// `HermesTransport` that runs `hermes <args>` on a remote host via
/// `ssh user@host [env HERMES_HOME=...] <remoteBinary> <args>`.
///
/// Stdout/stderr/stdin pass through SSH transparently, so an ACP stdio subprocess
/// launched via this transport behaves like a local one — the caller just gets a
/// `Process` with pipes and doesn't need to know the subprocess is remote.
nonisolated struct RemoteHermesTransport: HermesTransport {
    let remote: RemoteHermes
    let ssh: SSHSessionConfig

    init(remote: RemoteHermes) {
        self.remote = remote
        self.ssh = SSHSessionConfig(
            host: remote.host,
            user: remote.user,
            port: remote.sshPort,
            identityFile: remote.sshKeyPath,
            controlPath: SSHSessionConfig.controlPath(for: remote.id)
        )
    }

    /// The configured remote binary path. Not verifiable from the client side
    /// without an SSH round-trip — the Connections "Test Connection" flow runs
    /// `ssh host <binary> --version` to confirm it actually resolves on the remote.
    /// Callers gating UI on "Hermes available?" should invoke Test Connection
    /// rather than rely on this being non-nil.
    var hermesBinaryPath: String? {
        remote.remoteBinaryPath.isEmpty ? nil : remote.remoteBinaryPath
    }

    func makeHermesProcess(args: [String]) -> Process? {
        var remoteCmd: [String] = []
        // Shell-quote HERMES_HOME + binary path so paths containing spaces
        // (uncommon but legal — `/opt/my hermes/...`) survive SSH's argv
        // flattening + remote shell re-tokenization. `env KEY='value with space'`
        // is recognized as a single KEY=VAL assignment after quote processing.
        if let home = remote.remoteHermesHome, !home.isEmpty {
            remoteCmd += ["env", "HERMES_HOME=" + SSHSessionConfig.shellQuote(home)]
        }
        remoteCmd.append(SSHSessionConfig.shellQuote(remote.remoteBinaryPath))
        remoteCmd += args
        return ssh.makeProcess(remoteCommand: remoteCmd)
    }
}
