import XCTest

final class OutputsContractTests: XCTestCase {
    func testThemeCatalogFirstClassList() {
        let themes = ThemeCatalog.firstClassThemes
        XCTAssertEqual(themes.count, 20)
        XCTAssertTrue(themes.contains("boris"))
        XCTAssertTrue(themes.contains("cards"))
        XCTAssertTrue(themes.contains("press"))
        XCTAssertTrue(themes.contains("tokens"))
    }

    func testThemeCatalogLocalDiscovery() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-test-\(UUID().uuidString)")
        let themesDir = tempDir.appendingPathComponent("themes", isDirectory: true)
        try FileManager.default.createDirectory(at: themesDir.appendingPathComponent("custom-alpha"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: themesDir.appendingPathComponent("custom-beta"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let discovered = ThemeCatalog.discoverLocalThemes(in: tempDir)
        XCTAssertEqual(discovered, ["custom-alpha", "custom-beta"])

        let all = ThemeCatalog.allThemes(for: tempDir)
        XCTAssertEqual(all.first, "custom-alpha")
        XCTAssertEqual(all[1], "custom-beta")
        XCTAssertTrue(all.contains("boris"))
    }

    func testTargetAndEditionsDecoding() throws {
        let json = """
        {
          "format": "boris-publication-profile",
          "schema_version": 1,
          "input": "content",
          "targets": [
            {
              "name": "public",
              "output": "dist",
              "public": true,
              "theme": "boris",
              "layout": "layouts/main.html",
              "layout_rules": [
                { "selector": "role:trunk", "layout": "layouts/trunk.html" }
              ],
              "sitemap": { "path": "sitemap.xml" },
              "rss": { "path": "rss.xml", "limit": 50 },
              "llms": { "path": "llms.txt" }
            }
          ],
          "editions": {
            "ir": { "output": ".boris" },
            "rag": { "output": "rag", "scope": "guides", "split_size": 131072 },
            "context": { "output": "context", "split_size": 65536 }
          }
        }
        """
        let data = Data(json.utf8)
        let profile = try JSONDecoder().decode(PublicationProfile.self, from: data)

        XCTAssertEqual(profile.targets?.count, 1)
        let target = try XCTUnwrap(profile.targets?.first)
        XCTAssertEqual(target.name, "public")
        XCTAssertEqual(target.output, "dist")
        XCTAssertEqual(target.public, true)
        XCTAssertEqual(target.theme, "boris")
        XCTAssertEqual(target.layout_rules?.count, 1)
        XCTAssertEqual(target.sitemap?.path, "sitemap.xml")
        XCTAssertEqual(target.rss?.limit, 50)
        XCTAssertEqual(target.llms?.path, "llms.txt")

        let editions = try XCTUnwrap(profile.editions)
        XCTAssertEqual(editions.ir?.output, ".boris")
        XCTAssertEqual(editions.rag?.scope, "guides")
        XCTAssertEqual(editions.rag?.split_size, 131_072)
        XCTAssertEqual(editions.context?.output, "context")
    }
}
