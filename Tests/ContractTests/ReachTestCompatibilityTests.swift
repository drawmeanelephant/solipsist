import XCTest

final class ReachTestCompatibilityTests: XCTestCase {
    // MARK: - BorisProfileArgs (#322 flat-folder collision & boris 0.9+ archetypes)

    func testValidationWorkingDirectoryMovesParentForFlatFolder() {
        let flat = URL(fileURLWithPath: "/tmp/Stunts/broken-wikilink")
        let cwd = BorisProfileArgs.validationWorkingDirectory(contentRoot: flat, workingDirectory: flat)
        XCTAssertEqual(cwd.standardizedFileURL.path, "/tmp/Stunts")
    }

    func testValidationWorkingDirectoryPreservesProjectRoot() {
        let project = URL(fileURLWithPath: "/tmp/Stunts/dogfood")
        let content = project.appendingPathComponent("content")
        let cwd = BorisProfileArgs.validationWorkingDirectory(contentRoot: content, workingDirectory: project)
        XCTAssertEqual(cwd.standardizedFileURL.path, "/tmp/Stunts/dogfood")
    }

    func testDefaultTargetFlagsMapsArchetypeProfile() {
        let profile = PublicationProfile(
            input: "content",
            input_format: "cook",
            targets: [
                PublicationTarget(
                    name: "public",
                    output: "dist",
                    public: true,
                    theme: "themes/cards",
                    layout: "themes/cards/layouts/main.html",
                    layout_rules: [
                        PublicationLayoutRule(selector: "id:index", layout: "themes/cards/layouts/home.html"),
                    ],
                    static: PublicationStaticDir(dir: "static"),
                    html_profile: "html4_strict"
                ),
            ]
        )
        let flags = BorisProfileArgs.defaultTargetFlags(for: profile)
        XCTAssertEqual(
            flags,
            [
                "--cooklang",
                "--theme", "themes/cards",
                "--html-layout", "themes/cards/layouts/main.html",
                "--layout-rule", "default", "id:index", "themes/cards/layouts/home.html",
                "--static-dir", "static",
                "--target-profile", "default=html4-strict",
            ]
        )
    }

    // MARK: - PackageArchiveReader & MachineReadableVersion (#323)

    func testMachineReadableVersionDecodesBorisPackageShape() throws {
        let json = """
        {
          "format": "boris-package",
          "package_schema_version": 1,
          "product_version": "0.9.0",
          "compiler_id": "boris/0.9.0",
          "ir_schema_version": "0.2.0",
          "rag_format": "boris-rag",
          "rag_schema_version": 2,
          "include_rag": true
        }
        """
        let decoded = try JSONDecoder().decode(MachineReadableVersion.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.displayVersion, "0.9.0")
        XCTAssertEqual(decoded.displayCompiler, "boris/0.9.0")
        XCTAssertEqual(decoded.displayIRVersion, "0.2.0")
        XCTAssertEqual(decoded.package_schema_version, 1)
    }

    func testPackageArchiveReaderExtractsUstarEntries() throws {
        let versionPayload = Data(#"{"product_version":"0.9.0","compiler_id":"boris/0.9.0","ir_schema_version":"0.2.0"}"#.utf8)
        let sumsPayload = Data("0d572d5ddd49d77c0aaf0f223923f2c9e88d592a6034c4ed743c9023942df0a7  MACHINE-READABLE-VERSION.json\n".utf8)
        let tar = makeUstarArchive([
            ("boris-package/MACHINE-READABLE-VERSION.json", versionPayload),
            ("boris-package/SHA256SUMS", sumsPayload),
        ])

        let extractedVersion = try XCTUnwrap(
            PackageArchiveReader.readEntry(endingWith: "MACHINE-READABLE-VERSION.json", from: tar)
        )
        let decoded = try JSONDecoder().decode(MachineReadableVersion.self, from: extractedVersion)
        XCTAssertEqual(decoded.displayVersion, "0.9.0")

        let extractedSums = try XCTUnwrap(
            PackageArchiveReader.readEntry(endingWith: "SHA256SUMS", from: tar)
        )
        let sumsText = try XCTUnwrap(String(bytes: extractedSums, encoding: .utf8))
        let entries = PackageChecksumEntry.parse(from: sumsText)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].filename, "MACHINE-READABLE-VERSION.json")
    }

    func testPublishEvidenceLocatorFindsTargetProofDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("proof-loc-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let distProof = root.appendingPathComponent("out/public/_boris/proof", isDirectory: true)
        try FileManager.default.createDirectory(at: distProof, withIntermediateDirectories: true)

        let profile = PublicationProfile(
            targets: [PublicationTarget(name: "public", output: "out/public", public: true)]
        )
        let active = PublishEvidenceLocator.activeProofDirectory(workspaceRoot: root, profile: profile)
        XCTAssertEqual(active?.standardizedFileURL.path, distProof.standardizedFileURL.path)
    }

    // MARK: - Broken-corpus Compose fallback (#322)

    @MainActor
    func testComposeBufferOpensBrokenCorpusFileWhenGraphMissing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("broken-compose-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pageURL = root.appendingPathComponent("page.md")
        try "---\ntitle: Broken\n---\n\nSee [[missing]].\n".write(to: pageURL, atomically: true, encoding: .utf8)

        let source = try LocalSource.make(from: root)
        XCTAssertEqual(ProblemResolver.editableSourcePath(forPath: "page.md", source: source), "page.md")
        XCTAssertNil(ProblemResolver.editableSourcePath(forPath: "../outside.md", source: source))

        let buffer = ComposeBuffer()
        let selection = WorkspaceSelection(
            sourceID: source.id,
            mailbox: WorkspaceMailbox.pages,
            noun: WorkspaceNoun(kind: "page", id: "page.md", title: "page.md", sourcePath: "page.md")
        )
        XCTAssertTrue(buffer.select(ComposeBuffer.Request(source: source, selection: selection)))
        XCTAssertEqual(buffer.document.fileURL?.standardizedFileURL, pageURL.standardizedFileURL)
        XCTAssertTrue(buffer.document.text.contains("[[missing]]"))
    }

    // MARK: - SSE stale event (boris#1119)

    func testSSEParserEmitsStaleEvent() {
        var parser = SSEParser()
        XCTAssertTrue(parser.feed(line: "event: stale").isEmpty)
        XCTAssertTrue(parser.feed(line: "data: ParseFailed").isEmpty)
        let events = parser.feed(line: "")
        XCTAssertEqual(events, [SSEEvent(name: "stale", data: "ParseFailed")])
    }

    // MARK: - PackageBinary locator

    func testPackageBinaryLocatesSiblingOfBoris() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-bin-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let boris = dir.appendingPathComponent("boris")
        let pkg = dir.appendingPathComponent("boris-package")
        try "#!/bin/sh\n".write(to: boris, atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(to: pkg, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: boris.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pkg.path)

        let located = PackageBinary.locate(environment: [:], borisBinary: boris)
        XCTAssertEqual(located?.standardizedFileURL.path, pkg.standardizedFileURL.path)
    }

    func testInputArgumentRelativizesNestedContentRoot() {
        let work = URL(fileURLWithPath: "/tmp/site")
        XCTAssertEqual(
            BorisProfileArgs.inputArgument(contentRoot: work.appendingPathComponent("content"), relativeTo: work),
            "content"
        )
        XCTAssertEqual(BorisProfileArgs.inputArgument(contentRoot: work, relativeTo: work), ".")
    }

    func testNostrPublishReportDecodesBorisClassificationAndAcceptedOutcome() throws {
        let json = """
        {
          "format": "boris-nostr-publish-report",
          "schema_version": 1,
          "classification": "partial",
          "relays": [
            { "url": "wss://relay.example.com/", "outcome": "accepted", "attempts": 1,
              "events": [{ "entity_id": "index", "event_id": "abc", "result": "accepted", "message": "" }] },
            { "url": "wss://auth.example.com/", "outcome": "auth-required", "attempts": 1,
              "events": [{ "entity_id": "index", "event_id": "abc", "result": "auth-required", "message": "auth-required: NIP-42" }] }
          ]
        }
        """
        let report = try JSONDecoder().decode(NostrPublishReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.displayVerdict, "partial")
        let relays = try XCTUnwrap(report.relays)
        XCTAssertEqual(relays.count, 2)
        XCTAssertTrue(relays[0].isSuccess)
        XCTAssertEqual(relays[0].displayMessage, "accepted")
        XCTAssertFalse(relays[1].isSuccess)
        XCTAssertTrue(relays[1].displayMessage.contains("auth-required"))
    }

    func testPublicationProfileDecodesTopLevelNostrDeclaration() throws {
        let json = """
        {
          "format": "boris-publication-profile",
          "schema_version": 1,
          "input": "content",
          "publication": { "target": "github-pages", "base_url": "https://example.org", "origin": "https://example.org", "base_path": "" },
          "nostr": {
            "enabled": true,
            "pubkey": "1f2e3d4c5b6a7988796a5b4c3d2e1f00112233445566778899aabbccddeeff00",
            "articles": ["index"],
            "relays": ["wss://relay.example.org"],
            "timeout_ms": 5000,
            "retries": 2
          }
        }
        """
        let profile = try JSONDecoder().decode(PublicationProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.publication?.target, "github-pages")
        XCTAssertEqual(profile.nostr?.enabled, true)
        XCTAssertEqual(profile.nostr?.relays, ["wss://relay.example.org"])
        XCTAssertEqual(profile.nostr?.articles, ["index"])
    }

    private func makeUstarArchive(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        for (name, data) in files {
            var header = Data(count: 512)
            let nameBytes = Array(name.utf8.prefix(100))
            header.replaceSubrange(0..<nameBytes.count, with: nameBytes)
            let sizeStr = String(format: "%011o", data.count)
            header.replaceSubrange(124..<135, with: Array(sizeStr.utf8))
            header[156] = UInt8(ascii: "0")
            out.append(header)
            out.append(data)
            let rem = data.count % 512
            if rem != 0 {
                out.append(Data(count: 512 - rem))
            }
        }
        out.append(Data(count: 1024))
        return out
    }
}

extension ReachTestCompatibilityTests {
    // MARK: - Live tests against SOLIPSIST_BORIS_BIN (skipped when unset)

    private func liveEngine() throws -> BorisEngine {
        guard let borisPath = ProcessInfo.processInfo.environment["SOLIPSIST_BORIS_BIN"],
              !borisPath.isEmpty,
              FileManager.default.isExecutableFile(atPath: borisPath)
        else {
            throw XCTSkip("SOLIPSIST_BORIS_BIN not set")
        }
        return try BorisEngine(binaryURL: URL(fileURLWithPath: borisPath))
    }

    func testLiveValidateDogfoodAndAllFourBrokenCorpora() async throws {
        let engine = try liveEngine()
        let repoRoot = Self.repoRoot()

        let dogfood = repoRoot.appendingPathComponent("Stunts/dogfood")
        let dogfoodReport = FileManager.default.temporaryDirectory.appendingPathComponent("df-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: dogfoodReport) }
        let dfRes = try await engine.validate(
            contentRoot: dogfood.appendingPathComponent("content"),
            reportURL: dogfoodReport,
            workingDirectory: dogfood
        )
        XCTAssertEqual(dfRes.exitCode, 0, "dogfood validate failed: \(dfRes.stderr)")
        XCTAssertEqual(dfRes.report?.ok, true)

        let expected: [(folder: String, code: String)] = [
            ("broken-frontmatter", "EFRONTMATTER"),
            ("broken-parent", "EPARENTMISSING"),
            ("broken-duplicate-id", "EDUPLICATEID"),
            ("broken-wikilink", "EREFERENCEMISSING"),
        ]
        for entry in expected {
            let folder = repoRoot.appendingPathComponent("Stunts/\(entry.folder)")
            let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("brk-\(UUID()).json")
            defer { try? FileManager.default.removeItem(at: reportURL) }
            let res = try await engine.validate(contentRoot: folder, reportURL: reportURL, workingDirectory: folder)
            XCTAssertEqual(res.exitCode, 1, "\(entry.folder) exited \(res.exitCode): \(res.stderr)")
            let codes = res.report?.diagnostics.map(\.code) ?? []
            XCTAssertTrue(codes.contains(entry.code), "\(entry.folder) expected \(entry.code), got \(codes)")
        }
    }

    func testLiveBuildTargetWithProjectionsAndProofPack() async throws {
        let engine = try liveEngine()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("live-pub-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.copyItem(at: Self.repoRoot().appendingPathComponent("Stunts/happy"), to: scratch)
        let staticDir = scratch.appendingPathComponent("static", isDirectory: true)
        try FileManager.default.createDirectory(at: staticDir, withIntermediateDirectories: true)
        try "User-agent: *\n".write(to: staticDir.appendingPathComponent("robots.txt"), atomically: true, encoding: .utf8)

        let target = PublicationTarget(
            name: "public",
            output: "dist",
            public: true,
            theme: "themes/boris",
            sitemap: PublicationPathOutput(path: "sitemap.xml"),
            rss: PublicationPathOutput(path: "rss.xml"),
            llms: PublicationPathOutput(path: "llms.txt"),
            static: PublicationStaticDir(dir: "static")
        )
        let built = try await engine.buildTarget(
            contentRoot: scratch.appendingPathComponent("content"),
            target: target,
            siteURL: "https://example.com",
            siteTitle: "Happy Site",
            siteDescription: "Happy description",
            workingDirectory: scratch
        )
        XCTAssertEqual(built.exitCode, 0, "buildTarget failed: \(built.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("dist/sitemap.xml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("dist/robots.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("llms.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("rss.xml").path))
        let proofDir = PublishEvidenceLocator.activeProofDirectory(
            workspaceRoot: scratch,
            profile: PublicationProfile(targets: [target])
        )
        XCTAssertNotNil(proofDir)
    }

    func testLivePackageArchiveDecodesMetadata() async throws {
        let engine = try liveEngine()
        guard PackageBinary.locate(borisBinary: engine.binaryURL) != nil else {
            throw XCTSkip("boris-package not found next to SOLIPSIST_BORIS_BIN")
        }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("live-pkg-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.copyItem(at: Self.repoRoot().appendingPathComponent("Stunts/happy"), to: scratch)

        let pkg = try await engine.package(
            contentRoot: scratch.appendingPathComponent("content"),
            workingDirectory: scratch
        )
        XCTAssertEqual(pkg.exitCode, 0, "boris-package failed: \(pkg.stderr)")
        let tarURL = scratch.appendingPathComponent("packages/boris-package.tar")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tarURL.path))
        let verData = try XCTUnwrap(
            PackageArchiveReader.readEntry(endingWith: "MACHINE-READABLE-VERSION.json", fromArchiveAt: tarURL)
        )
        let version = try JSONDecoder().decode(MachineReadableVersion.self, from: verData)
        XCTAssertNotEqual(version.displayVersion, "unknown")
    }

    func testLiveSourceRagAndCheckDraftPage() async throws {
        let engine = try liveEngine()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("live-srag-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.copyItem(at: Self.repoRoot().appendingPathComponent("Stunts/happy"), to: scratch)
        let draftURL = scratch.appendingPathComponent("content/draft-note.md")
        try "---\ntitle: Draft Note\nparent: index\nstatus: draft\n---\n\n# Draft\n".write(
            to: draftURL,
            atomically: true,
            encoding: .utf8
        )

        let analysis = try await engine.check(
            contentRoot: scratch.appendingPathComponent("content"),
            workingDirectory: scratch
        )
        XCTAssertEqual(analysis.exitCode, 0)
        XCTAssertTrue(
            analysis.report.findings.contains(where: { $0.code == "draft_page" && $0.value == "draft-note" }),
            "expected draft_page finding for draft-note, got \(analysis.report.findings)"
        )

        if let tool = SourceRagBinary.locate(borisBinary: engine.binaryURL) {
            let res = try await engine.runTool(
                binary: tool,
                arguments: ["--root=.", "--out=source-rag", "--quiet"],
                workingDirectory: scratch
            )
            XCTAssertEqual(res.exitCode, 0, "boris-source-rag failed: \(res.stderr)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("source-rag/INDEX.md").path))
        }
    }

    private static func repoRoot(from file: String = #filePath) -> URL {
        var dir = URL(fileURLWithPath: file).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Project.yml").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: ".")
    }
}
