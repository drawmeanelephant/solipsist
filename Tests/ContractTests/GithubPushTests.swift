import XCTest

final class GithubPushTests: XCTestCase {
    // MARK: - Live push (local remotes only, no network)

    func testPushSetsUpstreamAndClearsAhead() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw XCTSkip("git not available")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubpush-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let origin = dir.appendingPathComponent("origin.git", isDirectory: true)
        let work = dir.appendingPathComponent("work", isDirectory: true)
        try runGit(["init", "--bare", "-b", "main", origin.path], in: dir)
        let seed = dir.appendingPathComponent("seed", isDirectory: true)
        try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: seed)
        try runGit(["config", "user.email", "t@example.com"], in: seed)
        try runGit(["config", "user.name", "t"], in: seed)
        try "one".write(to: seed.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: seed)
        try runGit(["commit", "-m", "one"], in: seed)
        try runGit(["remote", "add", "origin", origin.path], in: seed)
        try runGit(["push", "-u", "origin", "main"], in: seed)

        // Clone the working copy, add a commit, push it back.
        try runGit(["clone", origin.path, work.path], in: dir)
        try runGit(["config", "user.email", "t@example.com"], in: work)
        try runGit(["config", "user.name", "t"], in: work)
        try "two".write(to: work.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: work)
        try runGit(["commit", "-m", "two"], in: work)

        // Ahead 1 before the push.
        let before = GitClone.branchStatus(at: work)
        XCTAssertEqual(before.branch, "main")
        XCTAssertEqual(before.ahead, 1)

        let session = SyncSession()
        let result = GithubCommit.push(
            branch: "main",
            workingCopy: work,
            credentialHelperApp: nil,
            session: session
        )
        XCTAssertTrue(result.isSuccess, "push failed: \(result.stderr)")

        // Ahead 0 after; the commit landed on the bare origin (read
        // directly — seed's local branch is stale until it fetches).
        let after = GitClone.branchStatus(at: work)
        XCTAssertEqual(after.ahead, 0)
        XCTAssertEqual(after.behind, 0)
        let originLog = try runGitOutput(["--git-dir", origin.path, "log", "--oneline", "-1"], in: dir)
        XCTAssertTrue(originLog.contains("two"), "origin head should be the pushed commit, got: \(originLog)")
    }

    func testPushNonFastForwardRejectedVerbatim() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw XCTSkip("git not available")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubpush-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let origin = dir.appendingPathComponent("origin.git", isDirectory: true)
        let work = dir.appendingPathComponent("work", isDirectory: true)
        try runGit(["init", "--bare", "-b", "main", origin.path], in: dir)
        let seed = dir.appendingPathComponent("seed", isDirectory: true)
        try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: seed)
        try runGit(["config", "user.email", "t@example.com"], in: seed)
        try runGit(["config", "user.name", "t"], in: seed)
        try "one".write(to: seed.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: seed)
        try runGit(["commit", "-m", "one"], in: seed)
        try runGit(["remote", "add", "origin", origin.path], in: seed)
        try runGit(["push", "-u", "origin", "main"], in: seed)
        try runGit(["clone", origin.path, work.path], in: dir)
        try runGit(["config", "user.email", "t@example.com"], in: work)
        try runGit(["config", "user.name", "t"], in: work)

        // Advance origin with a conflicting commit...
        try "conflict".write(to: seed.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: seed)
        try runGit(["commit", "-m", "origin-advance"], in: seed)
        try runGit(["push", "origin", "main"], in: seed)

        // ...while the working copy commits a different version of the
        // same file. Push must be rejected — never a force-push.
        try "local-change".write(to: work.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: work)
        try runGit(["commit", "-m", "local-commit"], in: work)

        let session = SyncSession()
        let result = GithubCommit.push(
            branch: "main",
            workingCopy: work,
            credentialHelperApp: nil,
            session: session
        )
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(
            result.stderr.contains("non-fast-forward") || result.stderr.contains("fetch first")
                || result.stderr.contains("rejected"),
            "git's own rejection must surface verbatim, got: \(result.stderr)"
        )
        // The origin head is unchanged — no force-push happened.
        let originLog = try runGitOutput(["--git-dir", origin.path, "log", "--oneline", "-1"], in: dir)
        XCTAssertTrue(originLog.contains("origin-advance"), "origin must be untouched, got: \(originLog)")
    }

    func testPushWithCredentialHelperAppOnLocalRemote() throws {
        // The helper only fires for https remotes; passing one must not
        // disturb a local-remote push (proves the `-c` argument shape).
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw XCTSkip("git not available")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubpush-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let origin = dir.appendingPathComponent("origin.git", isDirectory: true)
        let work = dir.appendingPathComponent("work", isDirectory: true)
        try runGit(["init", "--bare", "-b", "main", origin.path], in: dir)
        let seed = dir.appendingPathComponent("seed", isDirectory: true)
        try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: seed)
        try runGit(["config", "user.email", "t@example.com"], in: seed)
        try runGit(["config", "user.name", "t"], in: seed)
        try "one".write(to: seed.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: seed)
        try runGit(["commit", "-m", "one"], in: seed)
        try runGit(["remote", "add", "origin", origin.path], in: seed)
        try runGit(["push", "-u", "origin", "main"], in: seed)
        try runGit(["clone", origin.path, work.path], in: dir)

        let helper = URL(fileURLWithPath: "/nonexistent/solipsist-helper")
        let session = SyncSession()
        let result = GithubCommit.push(
            branch: "main",
            workingCopy: work,
            credentialHelperApp: helper,
            session: session
        )
        XCTAssertTrue(result.isSuccess, "push failed: \(result.stderr)")
    }

    // MARK: - Helpers

    private func runGit(_ arguments: [String], in dir: URL) throws {
        _ = try runGitOutput(arguments, in: dir)
    }

    private func runGitOutput(_ arguments: [String], in dir: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = dir
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(bytes: data, encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments) failed: \(output)")
        return output
    }
}
