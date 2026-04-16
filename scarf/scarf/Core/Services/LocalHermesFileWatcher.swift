import Foundation

/// Local file-system watcher backed by `DispatchSourceFileSystemObject` sources.
/// One source per Hermes path; each one pings `onChange` when the kernel signals
/// a write / extend / rename on the descriptor.
///
/// The 5-second heartbeat timer forces periodic `onChange` ticks so downstream
/// consumers that poll derived state (gateway status, PID, etc.) stay fresh even
/// when no monitored file has changed.
final class LocalHermesFileWatcher: HermesFileWatching {
    nonisolated let locator: any HermesLocator
    private var coreSources: [DispatchSourceFileSystemObject] = []
    private var projectSources: [DispatchSourceFileSystemObject] = []
    private var timer: Timer?
    private var onChange: (@Sendable () -> Void)?

    init(locator: any HermesLocator = LocalHermesLocator()) {
        self.locator = locator
    }

    func startWatching(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        let paths = [
            locator.stateDB,
            locator.stateDB + "-wal",
            locator.configYAML,
            locator.memoryMD,
            locator.userMD,
            locator.cronJobsJSON,
            locator.gatewayStateJSON,
            locator.agentLog,
            locator.errorsLog,
            locator.gatewayLog,
            locator.projectsRegistry,
            locator.mcpTokensDir
        ]

        for path in paths {
            if let source = makeSource(for: path) {
                coreSources.append(source)
            }
        }

        let cb = onChange
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            cb()
        }
    }

    func stopWatching() {
        for source in coreSources + projectSources {
            source.cancel()
        }
        coreSources.removeAll()
        projectSources.removeAll()
        timer?.invalidate()
        timer = nil
        onChange = nil
    }

    func updateProjectWatches(_ dashboardPaths: [String]) {
        for source in projectSources {
            source.cancel()
        }
        projectSources.removeAll()
        for path in dashboardPaths {
            if let source = makeSource(for: path) {
                projectSources.append(source)
            }
        }
    }

    private func makeSource(for path: String) -> DispatchSourceFileSystemObject? {
        let fd = Darwin.open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: .main
        )
        let cb = onChange
        source.setEventHandler {
            cb?()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        return source
    }

    deinit {
        stopWatching()
    }
}
