import XCTest

final class PublishContractTests: XCTestCase {
    func testStandardSitePublicationDeclaration() throws {
        let json = """
        {
          "format": "boris-publication-profile",
          "schema_version": 1,
          "input": "content",
          "publication": {
            "target": "standard-site",
            "base_url": "https://example.standard.site",
            "origin": "https://example.standard.site",
            "base_path": "",
            "did": "did:plc:12345678abcdefgh",
            "name": "Example Standard Site",
            "description": "A test publication",
            "show_in_discover": true,
            "prune": false
          }
        }
        """
        let profile = try JSONDecoder().decode(PublicationProfile.self, from: Data(json.utf8))
        let pub = try XCTUnwrap(profile.publication)
        XCTAssertEqual(pub.target, "standard-site")
        XCTAssertEqual(pub.base_url, "https://example.standard.site")
        XCTAssertEqual(pub.did, "did:plc:12345678abcdefgh")
        XCTAssertEqual(pub.show_in_discover, true)
    }

    func testGitHubPagesPublicationDeclaration() throws {
        let json = """
        {
          "format": "boris-publication-profile",
          "schema_version": 1,
          "input": "content",
          "publication": {
            "target": "github-pages",
            "base_url": "https://org.github.io/repo",
            "origin": "https://org.github.io",
            "base_path": "/repo"
          }
        }
        """
        let profile = try JSONDecoder().decode(PublicationProfile.self, from: Data(json.utf8))
        let pub = try XCTUnwrap(profile.publication)
        XCTAssertEqual(pub.target, "github-pages")
        XCTAssertEqual(pub.base_path, "/repo")
    }

    func testProofChainArtifactNames() {
        let expectedEvidenceFiles = [
            "artifacts.json",
            "checks.json",
            "claims.json",
            "proof-pack.json",
            "touches.json",
        ]
        XCTAssertEqual(expectedEvidenceFiles.count, 5)
    }

    func testProofPackDocumentDecoding() throws {
        let json = """
        {
          "format": "boris-proof-pack",
          "schema_version": 1,
          "digest": "sha256:abcd1234efgh5678",
          "generated_at": "2026-08-17T20:00:00Z",
          "claims": [
            {
              "id": "claim-deterministic-build",
              "statement": "Build output is byte-for-byte reproducible.",
              "category": "integrity",
              "status": "verified",
              "evidence": ["artifacts.json", "touches.json"]
            },
            {
              "id": "claim-no-active-svg",
              "statement": "No active SVG or script elements detected in media.",
              "category": "security",
              "verified": true
            }
          ],
          "checks": [
            {
              "name": "Check asset checksums",
              "status": "passed",
              "message": "All 42 assets match recorded SHA256",
              "target": "dist/assets"
            },
            {
              "name": "Check link consistency",
              "passed": true,
              "target": "dist/"
            }
          ],
          "limitations": [
            "Search index does not cover external media descriptions."
          ]
        }
        """
        let doc = try JSONDecoder().decode(ProofPackDocument.self, from: Data(json.utf8))
        XCTAssertEqual(doc.format, "boris-proof-pack")
        XCTAssertEqual(doc.digest, "sha256:abcd1234efgh5678")
        XCTAssertEqual(doc.claims?.count, 2)
        XCTAssertEqual(doc.claims?[0].isVerified, true)
        XCTAssertEqual(doc.claims?[0].displayText, "Build output is byte-for-byte reproducible.")
        XCTAssertEqual(doc.checks?.count, 2)
        XCTAssertEqual(doc.checks?[0].isPassed, true)
        XCTAssertEqual(doc.limitations?.count, 1)
    }

    func testNostrPublishReportWithRelayVerdicts() throws {
        let json = """
        {
          "format": "boris-nostr-publish",
          "schema_version": 1,
          "verdict": "complete",
          "created_at": "2026-08-17T21:00:00Z",
          "event_id": "note1xyz789",
          "relays": [
            {
              "url": "wss://relay.damus.io",
              "verdict": "complete",
              "ok": true,
              "message": "Saved note1xyz789"
            },
            {
              "url": "wss://nos.lol",
              "verdict": "failed",
              "ok": false,
              "error": "Rate limited"
            }
          ]
        }
        """
        let report = try JSONDecoder().decode(NostrPublishReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.verdict, "complete")
        let relays = try XCTUnwrap(report.relays)
        XCTAssertEqual(relays.count, 2)
        XCTAssertEqual(relays[0].relayURL, "wss://relay.damus.io")
        XCTAssertEqual(relays[0].isSuccess, true)
        XCTAssertEqual(relays[1].relayURL, "wss://nos.lol")
        XCTAssertEqual(relays[1].isSuccess, false)
        XCTAssertEqual(relays[1].displayMessage, "Rate limited")
    }

    func testMachineReadableVersionDecoding() throws {
        let json = """
        {
          "format": "boris-machine-readable-version",
          "schema_version": 1,
          "version": "0.8.1",
          "commit": "b82e9e2eace74d9ca61df23dffc1329d2a2fe628",
          "compiler": "zig-0.16.0",
          "platform": "Darwin-arm64",
          "ir_version": "0.4.0",
          "features": ["nip23", "standard-site", "rag", "proof-pack"]
        }
        """
        let version = try JSONDecoder().decode(MachineReadableVersion.self, from: Data(json.utf8))
        XCTAssertEqual(version.displayVersion, "0.8.1")
        XCTAssertEqual(version.displayCommit, "b82e9e2eace74d9ca61df23dffc1329d2a2fe628")
        XCTAssertEqual(version.displayPlatform, "Darwin-arm64")
        XCTAssertEqual(version.features?.count, 4)
    }

    func testSHA256SUMSParsing() {
        let text = """
        # Boris release hashes
        12c8cd450c4fffb47b9cb92e2468071769a6d4c13a28a961231b1b69e1555abd  bin/boris
        56d8cd450c4fffb47b9cb92e2468071769a6d4c13a28a961231b1b69e1555abc *MACHINE-READABLE-VERSION.json
        # empty lines below

        """
        let entries = PackageChecksumEntry.parse(from: text)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].filename, "bin/boris")
        XCTAssertEqual(entries[0].sha256, "12c8cd450c4fffb47b9cb92e2468071769a6d4c13a28a961231b1b69e1555abd")
        XCTAssertEqual(entries[1].filename, "MACHINE-READABLE-VERSION.json")
        XCTAssertEqual(entries[1].sha256, "56d8cd450c4fffb47b9cb92e2468071769a6d4c13a28a961231b1b69e1555abc")
    }

    func testCoordinatorVerbsAttributes() {
        XCTAssertTrue(CoordinatorVerb.package.writesTree)
        XCTAssertTrue(CoordinatorVerb.publishStandardSite.writesTree)
        XCTAssertTrue(CoordinatorVerb.publishNostr.writesTree)
        XCTAssertFalse(CoordinatorVerb.standardSiteVerify.writesTree)
        XCTAssertFalse(CoordinatorVerb.standardSiteRecords.writesTree)
        XCTAssertFalse(CoordinatorVerb.standardSiteSessions.writesTree)
        XCTAssertFalse(CoordinatorVerb.standardSiteLogout.writesTree)
        XCTAssertFalse(CoordinatorVerb.standardSiteSmoke.writesTree)
        XCTAssertEqual(CoordinatorVerb.publishStandardSite.secretTarget, PublishTargets.standardSite)
        XCTAssertEqual(CoordinatorVerb.publishNostr.secretTarget, PublishTargets.nostr)
        XCTAssertNil(CoordinatorVerb.standardSiteVerify.secretTarget)
    }
}
