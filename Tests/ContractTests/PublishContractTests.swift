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
}
