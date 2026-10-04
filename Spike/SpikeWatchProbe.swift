import Foundation

enum SpikeWatchProbe {
    static func run(
        _ server: WatchServer,
        startupTimeout: Duration = .seconds(30),
        stopTimeout: Duration = .seconds(5)
    ) async throws -> (url: URL, exitCode: Int32) {
        defer {
            server.stop()
            if server.isRunning { server.forceKill() }
        }
        let readyDeadline = ContinuousClock.now + startupTimeout
        while server.serveURL == nil {
            try checkProblems(server)
            if let exit = server.exit {
                throw SpikeFailure(
                    exitCode: exit.exitCode > 0 ? exit.exitCode : 3,
                    description: "watch exited before serve-started (exit \(exit.exitCode)).\n\(exit.stderrTail)"
                )
            }
            guard ContinuousClock.now < readyDeadline else {
                throw SpikeFailure(exitCode: 3, description: "watch timed out waiting for serve-started.")
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        try checkProblems(server)
        guard let url = server.serveURL else {
            throw SpikeFailure(exitCode: 3, description: "watch did not report a helper URL.")
        }
        print("serve url    : \(url.absoluteString)")
        server.stop()
        let stopDeadline = ContinuousClock.now + stopTimeout
        while server.exit == nil {
            guard ContinuousClock.now < stopDeadline else {
                throw SpikeFailure(exitCode: 3, description: "watch timed out stopping after SIGTERM.")
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        try checkProblems(server, allowSignalStop: true)
        let code = server.exit?.exitCode ?? 3
        try SpikePolicy.requireSuccess(code, command: "watch stop", stderr: server.exit?.stderrTail ?? "")
        return (url, code)
    }

    private static func checkProblems(_ server: WatchServer, allowSignalStop: Bool = false) throws {
        let problems = server.problems.filter { !allowSignalStop || $0 != "watch stopped: signal" }
        guard problems.isEmpty else {
            throw SpikeFailure(exitCode: 1, description: "watch reported problems:\n\(problems.joined(separator: "\n"))")
        }
    }
}
