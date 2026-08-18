import XCTest

final class GitCloneTests: XCTestCase {
    // MARK: - URL validation

    func testAcceptsGitTransportShapes() {
        XCTAssertTrue(GitClone.isValidCloneURL("https://github.com/user/repo.git"))
        XCTAssertTrue(GitClone.isValidCloneURL("https://github.com/user/repo"))
        XCTAssertTrue(GitClone.isValidCloneURL("ssh://git@github.com/user/repo.git"))
        XCTAssertTrue(GitClone.isValidCloneURL("git://github.com/user/repo.git"))
        XCTAssertTrue(GitClone.isValidCloneURL("git@github.com:user/repo.git"))
        XCTAssertTrue(GitClone.isValidCloneURL("git@host:path"))
    }

    func testRejectsNonsenseAndLocalShapes() {
        XCTAssertFalse(GitClone.isValidCloneURL(""))
        XCTAssertFalse(GitClone.isValidCloneURL("   "))
        XCTAssertFalse(GitClone.isValidCloneURL("not a url with spaces"))
        XCTAssertFalse(GitClone.isValidCloneURL("file:///tmp/repo"))
        XCTAssertFalse(GitClone.isValidCloneURL("hello"))
        XCTAssertFalse(GitClone.isValidCloneURL("/absolute/path"))
        XCTAssertFalse(GitClone.isValidCloneURL("~/relative/path"))
        XCTAssertFalse(GitClone.isValidCloneURL("https://"))
        XCTAssertFalse(GitClone.isValidCloneURL("git@host")) // scp-like needs a path
    }

    // MARK: - Executable resolution

    func testGitExecutableResolutionFindsARunnableGit() {
        let git = GitClone.gitExecutableURL()
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: git.path))
        XCTAssertEqual(git.path, GitClone.gitExecutableURL().path, "resolution must be deterministic")
    }

    // MARK: - Repo naming

    func testRepoNameFromUrl() {
        XCTAssertEqual(GitClone.repoName(from: "https://github.com/user/repo.git"), "repo")
        XCTAssertEqual(GitClone.repoName(from: "https://github.com/user/repo"), "repo")
        XCTAssertEqual(GitClone.repoName(from: "git@github.com:user/repo.git"), "repo")
        XCTAssertEqual(GitClone.repoName(from: "ssh://git@github.com:22/user/repo.git"), "repo")
        XCTAssertEqual(GitClone.repoName(from: "https://github.com/user/repo/"), "repo")
        XCTAssertEqual(GitClone.repoName(from: "https://github.com/user/deep/path.git"), "path")
        XCTAssertEqual(GitClone.repoName(from: ""), "repo")
        XCTAssertEqual(GitClone.repoName(from: "   "), "repo")
    }

    // MARK: - Porcelain branch parsing

    func testParseBranchPorcelainV2() {
        XCTAssertEqual(GitClone.parseBranch(from: "# branch.head main"), "main")
        XCTAssertEqual(GitClone.parseBranch(from: "# branch.head feature/x"), "feature/x")
        XCTAssertNil(GitClone.parseBranch(from: "# branch.head (detached)"))
        XCTAssertNil(GitClone.parseBranch(from: "# branch.oid abc123"))
        XCTAssertNil(GitClone.parseBranch(from: "1 .M N..."))
    }

    func testParseBranchPorcelainV1() {
        XCTAssertEqual(GitClone.parseBranch(from: "## main...origin/main"), "main")
        XCTAssertEqual(GitClone.parseBranch(from: "## main...origin/main [ahead 1, behind 2]"), "main")
        XCTAssertEqual(GitClone.parseBranch(from: "## topic"), "topic")
        XCTAssertNil(GitClone.parseBranch(from: "## HEAD (no branch)"))
        XCTAssertNil(GitClone.parseBranch(from: "##"))
    }

    // MARK: - Live branch read (local repo only, no network)

    func testCurrentBranchReadsLocalCheckout() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw XCTSkip("git not available")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitclone-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Not a repo yet.
        XCTAssertNil(GitClone.currentBranch(at: dir))

        try runGit(["init", "-b", "main"], in: dir)
        try "hello".write(to: dir.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: dir)
        try runGit([
            "-c", "user.email=t@example.com",
            "-c", "user.name=t",
            "commit", "-m", "init",
        ], in: dir)
        XCTAssertEqual(GitClone.currentBranch(at: dir), "main")
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
