import Foundation

struct GatewayInfo {
    let pid: Int?
    let state: String
    let exitReason: String?
    let startTime: String?
    let updatedAt: String?
    let platforms: [PlatformInfo]
    let isLoaded: Bool
    let isStale: Bool
}

struct PlatformInfo: Identifiable {
    var id: String { name }
    let name: String
    let state: String
    let updatedAt: String?

    var isConnected: Bool { state == "connected" }

    var icon: String { KnownPlatforms.icon(for: name) }
}

struct PairedUser: Identifiable {
    var id: String { platform + userId }
    let platform: String
    let userId: String
    let name: String
}

struct PendingPairing: Identifiable {
    var id: String { platform + code }
    let platform: String
    let code: String
}

@Observable
final class GatewayViewModel {
    private let fileService = HermesFileService()

    var gateway = GatewayInfo(pid: nil, state: "unknown", exitReason: nil, startTime: nil, updatedAt: nil, platforms: [], isLoaded: false, isStale: false)
    var approvedUsers: [PairedUser] = []
    var pendingPairings: [PendingPairing] = []
    var isLoading = false
    var actionMessage: String?

    func load() {
        isLoading = true
        loadGatewayStatus()
        loadPairing()
        isLoading = false
    }

    func startGateway() {
        fileService.startGateway()
        actionMessage = "Gateway start requested"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.loadGatewayStatus()
            self?.actionMessage = nil
        }
    }

    func stopGateway() {
        fileService.stopHermes()
        actionMessage = "Gateway stop requested"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.loadGatewayStatus()
            self?.actionMessage = nil
        }
    }

    func restartGateway() {
        fileService.restartGateway()
        actionMessage = "Gateway restart requested"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.loadGatewayStatus()
            self?.actionMessage = nil
        }
    }

    func approvePairing(platform: String, code: String) {
        fileService.runHermesCLI(args: ["pairing", "approve", platform, code])
        loadPairing()
    }

    func revokeUser(_ user: PairedUser) {
        fileService.runHermesCLI(args: ["pairing", "revoke", user.platform, user.userId])
        approvedUsers.removeAll { $0.id == user.id }
    }

    // MARK: - Private

    private func loadGatewayStatus() {
        let stateJSON = fileService.loadGatewayStateData()
        var pid: Int?
        var state = "unknown"
        var exitReason: String?
        var startTime: String?
        var updatedAt: String?
        var platforms: [PlatformInfo] = []

        if let data = stateJSON,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            pid = json["pid"] as? Int
            state = json["gateway_state"] as? String ?? "unknown"
            exitReason = json["exit_reason"] as? String
            startTime = json["start_time"] as? String
            updatedAt = json["updated_at"] as? String
            if let plats = json["platforms"] as? [String: Any] {
                platforms = plats.compactMap { key, value in
                    guard let info = value as? [String: Any] else { return nil }
                    return PlatformInfo(
                        name: key,
                        state: info["state"] as? String ?? "unknown",
                        updatedAt: info["updated_at"] as? String
                    )
                }.sorted { $0.name < $1.name }
            }
        }

        let statusOutput = fileService.gatewayStatus()
        let isLoaded = statusOutput.contains("service is loaded")
        let isStale = statusOutput.contains("stale")

        gateway = GatewayInfo(
            pid: pid, state: state, exitReason: exitReason,
            startTime: startTime, updatedAt: updatedAt,
            platforms: platforms, isLoaded: isLoaded, isStale: isStale
        )
    }

    private func loadPairing() {
        let output = fileService.runHermesCLI(args: ["pairing", "list"]).output
        approvedUsers = []
        pendingPairings = []

        var inApproved = false
        var inPending = false

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Approved Users") { inApproved = true; inPending = false; continue }
            if trimmed.contains("Pending") { inPending = true; inApproved = false; continue }
            if trimmed.isEmpty || trimmed.hasPrefix("Platform") || trimmed.hasPrefix("--------") { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            if inApproved && parts.count >= 3 {
                let platform = String(parts[0])
                let userId = String(parts[1])
                let name = parts[2...].joined(separator: " ")
                approvedUsers.append(PairedUser(platform: platform, userId: userId, name: name))
            }
            if inPending && parts.count >= 2 {
                let platform = String(parts[0])
                let code = String(parts[1])
                pendingPairings.append(PendingPairing(platform: platform, code: code))
            }
        }
    }

}
