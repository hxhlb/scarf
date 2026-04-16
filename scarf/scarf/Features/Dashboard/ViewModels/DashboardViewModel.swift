import Foundation

@Observable
final class DashboardViewModel {
    private let dataService = HermesDataService()
    private let fileService = HermesFileService()

    var stats = SessionStats.empty
    var recentSessions: [HermesSession] = []
    var sessionPreviews: [String: String] = [:]
    var config = HermesConfig.empty
    var gatewayState: GatewayState?
    var hermesRunning = false
    var isLoading = true

    func load() async {
        isLoading = true
        let opened = await dataService.open()
        if opened {
            stats = await dataService.fetchStats()
            recentSessions = await dataService.fetchSessions(limit: 5)
            sessionPreviews = await dataService.fetchSessionPreviews(limit: 5)
            await dataService.close()
        }
        config = fileService.loadConfig()
        gatewayState = fileService.loadGatewayState()
        hermesRunning = fileService.isHermesRunning()
        isLoading = false
    }
}
