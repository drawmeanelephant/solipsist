import XCTest

final class GithubSyncTests: XCTestCase {
    // MARK: - Ahead/behind porcelain parsing (pure)

    func testParseAheadBehindV2() {
        XCTAssertEqual(GitClone.parseAheadBehind(from: "# branch.ab +1 -2")?.ahead, 1)
        XCTAssertEqual(GitClone.parseAheadBehind(from: "# branch.ab +1 -2")?.behind, 2)
        XCTAssertEqual(GitClone.parseAheadBehind(from: "# branch.ab +0 -0")?.ahead, 0)
        XCTAssertEqual(GitClone.parseAheadBehind(from: "# branch.ab +0 -0")?.behind, 0)
        XCTAssertEqual(GitClone.parseAheadBehind(from: "# branch.ab +3 -0")?.ahead, 3)
        XCTAssertEqual(GitClone.parseAheadBehind(from: "# branch.ab +0 -7")?.behind, 7)
        XCTAssertNil(GitClone.parseAheadBehind(from: "# branch.head main"))
        XCTAssertNil(GitClone.parseAheadBehind(from: "1 .M N..."))
        XCTAssertNil(GitClone.parseAheadBehind(from: "# branch.ab +1")) // malformed
        XCTAssertNil(GitClone.parseAheadBehind(from: "# branch.ab +x -y")) // non-numeric
    }

    // MARK: - Live sync (local remotes only, no network)

    func testSyncFastForwardsWorkingCopy() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw XCTSkip("git not available")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubsync-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let origin = dir.appendingPathComponent("origin.git", isDirectory: true)
        let work = dir.appendingPathComponent("work", isDirectory: true)

        try runGit(["init", "--bare", "-b", "main", origin.path], in: dir)
        // Seed the origin with one commit (a bare repo has no checkout).
        let seed = dir.appendingPathComponent("seed", isDirectory: true)
        try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: seed)
        try "one".write(to: seed.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: seed)
        try runGit(["-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-m", "one"], in: seed)
        try runGit(["remote", "add", "origin", origin.path], in: seed)
        try runGit(["push", "-u", "origin", "main"], in: seed)

        // Clone the working copy, then advance origin.
        try runGit(["clone", origin.path, work.path], in: dir)
        XCTAssertEqual(GitClone.currentBranch(at: work), "main")

        try "two".write(to: seed.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: seed)
        try runGit(["-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-m", "two"], in: seed)
        try runGit(["push", "origin", "main"], in: seed)

        // Fetch so the remote-tracking ref sees the new commit, then the
        // working copy is behind 1 (ahead/behind is against the local
        // tracking ref, which only advances on fetch/sync).
        try runGit(["fetch", "origin"], in: work)
        let before = GitClone.branchStatus(at: work)
        XCTAssertEqual(before.branch, "main")
        XCTAssertEqual(before.behind, 1)
        XCTAssertEqual(before.ahead, 0)

        let session = SyncSession()
        let result = GithubSync.sync(workingCopy: work, credentialHelperApp: nil, session: session)
        XCTAssertTrue(result.isSuccess, "sync failed: \\(result.stderr)")

        let after = GitClone.branchStatus(at: work)
        XCTAssertEqual(after.branch, "main")
        XCTAssertEqual(after.ahead, 0)
        XCTAssertEqual(after.behind, 0)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: work.appendingPathComponent("b.txt").path),
            "pulled file should exist"
        )
    }

    func testSyncFailsFastOnNonRepo() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw XCTSkip("git not available")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubsync-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let session = SyncSession()
        let result = GithubSync.sync(workingCopy: dir, credentialHelperApp: nil, session: session)
        XCTAssertFalse(result.isSuccess)
        XCTAssertFalse(result.stderr.isEmpty, "git's stderr must surface, never be swallowed")
    }

    func testSyncWithCredentialHelperAppOnLocalRemote() throws {
        // The helper app is only invoked for https remotes; passing one
        // must not disturb a local-remote sync (proves the `-c` argument
        // shape is accepted by git).
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw XCTSkip("git not available")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("githubsync-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let origin = dir.appendingPathComponent("origin.git", isDirectory: true)
        let work = dir.appendingPathComponent("work", isDirectory: true)
        try runGit(["init", "--bare", "-b", "main", origin.path], in: dir)
        let seed = dir.appendingPathComponent("seed", isDirectory: true)
        try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: seed)
        try "one".write(to: seed.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: seed)
        try runGit(["-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-m", "one"], in: seed)
        try runGit(["remote", "add", "origin", origin.path], in: seed)
        try runGit(["push", "-u", "origin", "main"], in: seed)
        try runGit(["clone", origin.path, work.path], in: dir)

        let helper = URL(fileURLWithPath: "/nonexistent/solipsist-helper")
        let session = SyncSession()
        let result = GithubSync.sync(workingCopy: work, credentialHelperApp: helper, session: session)
        XCTAssertTrue(result.isSuccess, "sync failed: \\(result.stderr)")
    }

    // MARK: - Helpers

    private func runGit(_ arguments: [String], in dir: URL) throws {
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
        XCTAssertEqual(process.terminationStatus, 0, "git \\(arguments) failed: \\(output)")
    }
}
