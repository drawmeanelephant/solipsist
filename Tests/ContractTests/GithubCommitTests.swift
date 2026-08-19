import XCTest

final class GithubCommitTests: XCTestCase {
    // MARK: - Porcelain -z parsing (pure)

    func testParseStatusEntriesUntrackedModifiedDeleted() {
        let data = Data(" M a.txt\0 D b.txt\0?? c.txt\0".utf8)
        let entries = GitClone.parseStatusEntries(data)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].path, "a.txt")
        XCTAssertEqual(entries[0].status, " M")
        XCTAssertEqual(entries[0].statusLabel, "modified")
        XCTAssertNil(entries[0].sourcePath)
        XCTAssertEqual(entries[1].path, "b.txt")
        XCTAssertEqual(entries[1].status, " D")
        XCTAssertEqual(entries[1].statusLabel, "deleted")
        XCTAssertEqual(entries[2].path, "c.txt")
        XCTAssertEqual(entries[2].status, "??")
        XCTAssertEqual(entries[2].statusLabel, "untracked")
    }

    func testParseStatusEntriesRenameEmitsDestinationFirst() {
        // git -z emits `XY <to>\0<from>` for renames.
        let data = Data("R  moved.txt\0renamed.txt\0 M keep.txt\0".utf8)
        let entries = GitClone.parseStatusEntries(data)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].path, "moved.txt")
        XCTAssertEqual(entries[0].status, "R ")
        XCTAssertEqual(entries[0].statusLabel, "renamed")
        XCTAssertEqual(entries[0].sourcePath, "renamed.txt")
        XCTAssertEqual(entries[1].path, "keep.txt")
        XCTAssertNil(entries[1].sourcePath)
    }

    func testParseStatusEntriesEmpty() {
        XCTAssertEqual(GitClone.parseStatusEntries(Data()), [])
    }

    func testStatusEntriesLiveLocalRepo() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw XCTSkip("git not available")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitcommit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try runGit(["init", "-b", "main"], in: dir)
        try "one".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: dir)
        try runGit(["-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-m", "init"], in: dir)

        // Modified + untracked appear; untouched files do not.
        try "changed".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "new".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let entries = GitClone.statusEntries(at: dir)
        let paths = entries.map(\.path)
        XCTAssertTrue(paths.contains("a.txt"), "modified file must appear: \(paths)")
        XCTAssertTrue(paths.contains("b.txt"), "untracked file must appear: \(paths)")
    }

    // MARK: - Commit one-shots (live, local remotes only, no network)

    func testCommitStagesOnlyPickedPaths() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw XCTSkip("git not available")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitcommit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try runGit(["init", "-b", "main"], in: dir)
        try runGit(["-c", "user.email=t@example.com", "-c", "user.name=t", "config", "user.email", "t@example.com"], in: dir)
        try runGit(["config", "user.name", "t"], in: dir)
        try "one".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: dir)
        try runGit(["commit", "-m", "init"], in: dir)

        // Modify both; commit only a.txt.
        try "a2".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b2".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let session = SyncSession()
        let result = GithubCommit.commit(
            paths: ["a.txt"],
            message: "only a",
            workingCopy: dir,
            session: session
        )
        XCTAssertTrue(result.isSuccess, "commit failed: \(result.stderr)")

        // a.txt is clean; b.txt is still modified (never add -A).
        let entries = GitClone.statusEntries(at: dir)
        let paths = entries.map(\.path)
        XCTAssertFalse(paths.contains("a.txt"), "committed file should be clean: \(paths)")
        XCTAssertTrue(paths.contains("b.txt"), "unpicked file must stay modified: \(paths)")
    }

    func testCommitMissingIdentityFailsVerbatim() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw XCTSkip("git not available")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitcommit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try runGit(["init", "-b", "main"], in: dir)
        // `user.useConfigOnly` is git's documented opt-out of
        // auto-derived identity (username@hostname). Without it git
        // silently synthesizes one — this is the honest way to exercise
        // the real missing-identity path. No user.name / user.email
        // anywhere; the machine's global config is isolated.
        try runGit(["config", "user.useConfigOnly", "true"], in: dir)
        try "one".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: dir)

        let session = SyncSession()
        let result = GithubCommit.commit(
            paths: ["a.txt"],
            message: "no identity",
            workingCopy: dir,
            session: session,
            environment: ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"]
        )
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(
            result.stderr.contains("user.email") || result.stderr.contains("Please tell me who you are"),
            "git's own identity error must surface verbatim, got: \(result.stderr)"
        )
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
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments) failed: \(output)")
    }
}
