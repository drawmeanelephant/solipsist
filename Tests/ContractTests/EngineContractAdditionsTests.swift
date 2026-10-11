import Foundation
import XCTest

/// Decode + behavior coverage for the engine surfaces added by the
/// boris/0.8.2 re-pin: `--build-info`, `engine-provenance.json`, plan
/// schema 3 (`nostr` / `head` / `html_profile`), `html4-strict`, and the
/// reason-counted `WatchServer` suspend.
final class EngineContractAdditionsTests: XCTestCase {
    // MARK: - `boris --build-info` (boris-build-info, schemaVersion "1")

    /// Byte shape probed live from the pinned engine:
    /// `{"format":"boris-build-info","schemaVersion":"1","version":"boris/0.8.2","vcsRevision":"3ab19ad"}`
    func testBuildInfoDecodesThePinnedDocument() throws {
        let json = """
        {"format":"boris-build-info","schemaVersion":"1","version":"boris/0.8.2","vcsRevision":"3ab19ad"}
        """
        let info = try JSONDecoder().decode(BorisBuildInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.format, "boris-build-info")
        XCTAssertEqual(info.schemaVersion, "1")
        XCTAssertEqual(info.version, "boris/0.8.2")
        XCTAssertEqual(info.vcsRevision, "3ab19ad")
    }

    /// D8: a dirty-tree suffix and a missing optional stay decodable.
    func testBuildInfoToleratesDirtyRevisionAndMissingOptionals() throws {
        let json = """
        {"format":"boris-build-info","vcsRevision":"3ab19ad.dirty"}
        """
        let info = try JSONDecoder().decode(BorisBuildInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.vcsRevision, "3ab19ad.dirty")
        XCTAssertNil(info.version)
    }

    // MARK: - `Resources/engine-provenance.json`

    /// The shape `scripts/embed-boris.sh` writes into the bundle.
    func testEngineProvenanceDecodesTheEmbedDocument() throws {
        let json = """
        {
          "format": "solipsist-engine-provenance",
          "schema_version": 1,
          "generatedBy": "scripts/embed-boris.sh",
          "boris": {
            "version": "boris/0.8.2",
            "repoCommit": "3ab19adf4d57e9061d880288ec1a2774ffa46a8c",
            "buildInfo": {
              "format": "boris-build-info",
              "schemaVersion": "1",
              "version": "boris/0.8.2",
              "vcsRevision": "3ab19ad"
            }
          },
          "borisEditor": {"version": "", "sourcePath": "boris-editor"},
          "editorUI": {"version": "", "repoCommit": "3ab19adf4d57e9061d880288ec1a2774ffa46a8c"},
          "oliver": {"version": "1.1.0", "repoCommit": "abcdef12"},
          "companions": {
            "borisPackage": "boris-package/0.8.2",
            "borisSourceRag": "boris-source-rag/0.8.2",
            "borisContentAudit": ""
          }
        }
        """
        let provenance = try JSONDecoder().decode(EngineProvenance.self, from: Data(json.utf8))
        XCTAssertEqual(provenance.format, "solipsist-engine-provenance")
        XCTAssertEqual(provenance.boris?.buildInfo?.vcsRevision, "3ab19ad")
        XCTAssertEqual(provenance.boris?.repoCommit, "3ab19adf4d57e9061d880288ec1a2774ffa46a8c")
        XCTAssertEqual(provenance.oliver?.version, "1.1.0")
        XCTAssertEqual(provenance.companions?.borisPackage, "boris-package/0.8.2")
    }

    /// Fully-optional decode: a partial or empty document yields nil
    /// fields, never a gate (dev builds may lack the file entirely).
    func testEngineProvenancePartialDocumentDecodesToNilFields() throws {
        let provenance = try JSONDecoder().decode(EngineProvenance.self, from: Data("{}".utf8))
        XCTAssertNil(provenance.boris)
        XCTAssertNil(provenance.oliver)
        XCTAssertNil(provenance.companions)
    }

    // MARK: - Publication plan schema 3

    /// `head` / `html_profile` echo on targets; the closed `nostr` object
    /// rides the top level. All additive over schema 1.
    func testPlanSchema3DecodesNostrAndHeadTarget() throws {
        let json = """
        {
          "format": "boris-publication-plan",
          "schema_version": 3,
          "input": "content",
          "targets": [
            {
              "name": "site",
              "output": "dist",
              "public": true,
              "theme": "boris",
              "html_profile": "html4_strict",
              "head": {
                "enabled": true,
                "ogp": "optional",
                "defaults": {"title": "Site", "type": "website"}
              }
            }
          ],
          "nostr": {
            "enabled": true,
            "kind": 30023,
            "pubkey": "\(String(repeating: "a", count: 64))",
            "articles": ["content/posts"],
            "relays": ["wss://relay.example"],
            "timeout_ms": 15000,
            "retries": 2
          }
        }
        """
        let plan = try JSONDecoder().decode(PublicationPlan.self, from: Data(json.utf8))
        XCTAssertEqual(plan.schema_version, 3)
        let target = try XCTUnwrap(plan.targets?.first)
        XCTAssertEqual(target.html_profile, "html4_strict")
        XCTAssertEqual(target.head?.ogp, "optional")
        XCTAssertEqual(target.head?.defaults?.type, "website")
        XCTAssertEqual(plan.nostr?.kind, 30023)
        XCTAssertEqual(plan.nostr?.relays, ["wss://relay.example"])
    }

    /// Schema-1 plans (no new keys) still decode — the re-pin cannot
    /// strand older fixtures.
    func testPlanSchema1DocumentStillDecodes() throws {
        let json = """
        {"format": "boris-publication-plan", "schema_version": 1,
         "targets": [{"name": "site", "output": "dist"}]}
        """
        let plan = try JSONDecoder().decode(PublicationPlan.self, from: Data(json.utf8))
        XCTAssertNil(plan.nostr)
        XCTAssertNil(plan.targets?.first?.head)
        XCTAssertNil(plan.targets?.first?.html_profile)
    }

    // MARK: - Oliver `html4-strict`

    /// The profile's rawValue must spell `--to html4-strict` for the oliver
    /// CLI (its JSON report spells it `html4_strict`).
    func testHTML4StrictProfileSpelling() {
        XCTAssertEqual(OliverRenderProfile.html4Strict.rawValue, "html4-strict")
    }

    // MARK: - Reason-counted WatchServer suspend

    /// Two suspend reasons keep the child SIGSTOP'd until the last lifts —
    /// a tree write must not wake a watch the editor still owns.
    /// `/usr/bin/yes` ignores the fixed watch argv and stays alive, so it
    /// stands in for boris without needing an engine.
    func testSuspendReasonsCompose() throws {
        let server = WatchServer(
            binary: URL(fileURLWithPath: "/usr/bin/yes"),
            contentRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        defer { server.stop() }
        try server.start()
        guard let pid = server.processIdentifier else {
            return XCTFail("server process did not start")
        }

        server.suspend(reason: .treeWrite)
        server.suspend(reason: .editorCompanion)
        XCTAssertTrue(server.isSuspended)
        XCTAssertTrue(processStat(pid).contains("T"), "child should be SIGSTOP'd")

        server.resume(reason: .treeWrite)
        XCTAssertTrue(server.isSuspended, "editor reason still holds the stop")
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertTrue(processStat(pid).contains("T"), "child must stay stopped until every reason lifts")

        server.resume(reason: .editorCompanion)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(server.isSuspended)
        XCTAssertFalse(processStat(pid).contains("T"), "last reason lifting resumes the child")
    }

    /// `resumeAll` lifts every reason at once (teardown path).
    func testResumeAllLiftsEveryReason() throws {
        let server = WatchServer(
            binary: URL(fileURLWithPath: "/usr/bin/yes"),
            contentRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        defer { server.stop() }
        try server.start()
        guard let pid = server.processIdentifier else {
            return XCTFail("server process did not start")
        }

        server.suspend(reason: .treeWrite)
        server.suspend(reason: .editorCompanion)
        server.resumeAll()
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(server.isSuspended)
        XCTAssertFalse(processStat(pid).contains("T"))
    }

    /// `stop()` on a suspended server SIGCONTs before SIGTERM — the child
    /// must die, not linger frozen.
    func testStopOnSuspendedServerTerminates() throws {
        let server = WatchServer(
            binary: URL(fileURLWithPath: "/usr/bin/yes"),
            contentRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        try server.start()
        guard let pid = server.processIdentifier else {
            return XCTFail("server process did not start")
        }
        server.suspend(reason: .editorCompanion)
        server.stop()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !processIsAlive(pid) { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("stopped server never exited")
    }

    // MARK: - Helpers

    private func processStat(_ pid: Int32) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "stat=", "-p", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}
