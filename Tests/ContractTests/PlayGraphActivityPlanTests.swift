import XCTest

final class PlayGraphActivityPlanTests: XCTestCase {
    func testLocalPlayGraphPagesExtraction() {
        let node1 = GraphNode(
            index: 0,
            id: "index",
            sourcePath: "index.md",
            role: .trunk,
            parent: nil,
            parentIndex: nil,
            title: "Home",
            status: "published",
            tags: ["home", "main"]
        )
        let node2 = GraphNode(
            index: 1,
            id: "guides/intro",
            sourcePath: "guides/intro.md",
            role: .satellite,
            parent: "index",
            parentIndex: 0,
            title: "Introduction",
            status: "draft",
            tags: ["guides", "starter"]
        )
        let graph = Graph(
            schemaVersion: "0.3.0",
            frozen: true,
            nodes: [node1, node2],
            edges: [],
            reverseIndex: [],
            nav: []
        )

        let pages = LocalPlayGraph.pages(from: graph)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].id, "index")
        XCTAssertEqual(pages[0].title, "Home")
        XCTAssertEqual(pages[0].depth, 0)
        XCTAssertEqual(pages[0].tags, ["home", "main"])
        XCTAssertEqual(pages[0].sourcePath, "index.md")

        XCTAssertEqual(pages[1].id, "guides/intro")
        XCTAssertEqual(pages[1].title, "Introduction")
        XCTAssertEqual(pages[1].depth, 1)
        XCTAssertEqual(pages[1].tags, ["guides", "starter"])
        XCTAssertEqual(pages[1].sourcePath, "guides/intro.md")
    }

    func testLocalPlayGraphFilterByTitleAndId() {
        let pages = [
            PlayPage(id: "index", title: "Home Page", status: "published", role: .trunk, depth: 0, tags: ["site"], sourcePath: "index.md"),
            PlayPage(id: "guides/getting-started", title: "Getting Started", status: "published", role: .satellite, depth: 1, tags: ["guide"], sourcePath: "guides/getting-started.md"),
            PlayPage(id: "guides/advanced", title: "Advanced Topics", status: "draft", role: .satellite, depth: 1, tags: ["guide", "deep-dive"], sourcePath: "guides/advanced.md"),
            PlayPage(id: "reference/api", title: "API Reference", status: "draft", role: .satellite, depth: 1, tags: ["reference"], sourcePath: "reference/api.md")
        ]

        // Empty query returns all
        XCTAssertEqual(LocalPlayGraph.filter(pages: pages, query: "").count, 4)
        XCTAssertEqual(LocalPlayGraph.filter(pages: pages, query: "   ").count, 4)

        // Filter by title substring
        let titleMatches = LocalPlayGraph.filter(pages: pages, query: "getting")
        XCTAssertEqual(titleMatches.map(\.id), ["guides/getting-started"])

        // Filter by id substring
        let idMatches = LocalPlayGraph.filter(pages: pages, query: "reference")
        XCTAssertEqual(idMatches.map(\.id), ["reference/api"])

        // Filter with prefix id:
        let idPrefixMatches = LocalPlayGraph.filter(pages: pages, query: "id:guides")
        XCTAssertEqual(idPrefixMatches.map(\.id), ["guides/getting-started", "guides/advanced"])
    }

    func testLocalPlayGraphFilterByTagAndStatus() {
        let pages = [
            PlayPage(id: "index", title: "Home Page", status: "published", role: .trunk, depth: 0, tags: ["site"], sourcePath: "index.md"),
            PlayPage(id: "guides/getting-started", title: "Getting Started", status: "published", role: .satellite, depth: 1, tags: ["guide", "beginner"], sourcePath: "guides/getting-started.md"),
            PlayPage(id: "guides/advanced", title: "Advanced Topics", status: "draft", role: .satellite, depth: 1, tags: ["guide", "deep-dive"], sourcePath: "guides/advanced.md"),
            PlayPage(id: "reference/api", title: "API Reference", status: "draft", role: .satellite, depth: 1, tags: ["reference"], sourcePath: "reference/api.md")
        ]

        // Tag query (plain)
        let tagMatches = LocalPlayGraph.filter(pages: pages, query: "deep-dive")
        XCTAssertEqual(tagMatches.map(\.id), ["guides/advanced"])

        // Tag query (prefix)
        let tagPrefixMatches = LocalPlayGraph.filter(pages: pages, query: "tag:guide")
        XCTAssertEqual(tagPrefixMatches.map(\.id), ["guides/getting-started", "guides/advanced"])

        // Status query (plain)
        let statusMatches = LocalPlayGraph.filter(pages: pages, query: "draft")
        XCTAssertEqual(statusMatches.map(\.id), ["guides/advanced", "reference/api"])

        // Status query (prefix)
        let statusPrefixMatches = LocalPlayGraph.filter(pages: pages, query: "status:published")
        XCTAssertEqual(statusPrefixMatches.map(\.id), ["index", "guides/getting-started"])

        // Multi-token: tag:guide draft
        let multiMatches = LocalPlayGraph.filter(pages: pages, query: "tag:guide draft")
        XCTAssertEqual(multiMatches.map(\.id), ["guides/advanced"])
    }

    func testLocalPlayGraphSourcePathResolution() {
        let pages = [
            PlayPage(id: "index", title: "Home", status: "published", role: .trunk, depth: 0, tags: [], sourcePath: "index.md"),
            PlayPage(id: "guides/getting-started", title: "Getting Started", status: "published", role: .satellite, depth: 1, tags: [], sourcePath: "guides/getting-started.md"),
            PlayPage(id: "recipe/soup", title: "Hot Soup", status: "published", role: .satellite, depth: 1, tags: [], sourcePath: "recipes/soup.cook")
        ]

        // Exact sourcePath match
        let match1 = LocalPlayGraph.resolvePage(forSourcePath: "guides/getting-started.md", in: pages)
        XCTAssertEqual(match1?.id, "guides/getting-started")
        XCTAssertEqual(match1?.title, "Getting Started")

        // Cooklang sourcePath match
        let match2 = LocalPlayGraph.resolvePage(forSourcePath: "recipes/soup.cook", in: pages)
        XCTAssertEqual(match2?.id, "recipe/soup")
        XCTAssertEqual(match2?.title, "Hot Soup")

        // Exact ID match
        let match3 = LocalPlayGraph.resolvePage(forSourcePath: "guides/getting-started", in: pages)
        XCTAssertEqual(match3?.id, "guides/getting-started")

        // Path without extension
        let match4 = LocalPlayGraph.resolvePage(forSourcePath: "guides/getting-started", in: pages)
        XCTAssertEqual(match4?.id, "guides/getting-started")

        // Suffix match (e.g. workspace-relative path /content/index.md)
        let match5 = LocalPlayGraph.resolvePage(forSourcePath: "content/index.md", in: pages)
        XCTAssertEqual(match5?.id, "index")

        // Unknown path returns nil
        let fallback = LocalPlayGraph.resolvePage(forSourcePath: "unknown/orphan.md", in: pages)
        XCTAssertNil(fallback)
    }

    func testCoordinatorActivityModel() {
        let timings = TimingsReport(
            format: "boris-timings",
            schemaVersion: "1",
            mode: "ir",
            phases: ["scan": 1_500_000, "parse": 3_200_000],
            counters: TimingsCounters(page_reads: 5, include_reads: 1, hash_bytes: 512, link_resolutions: 2, fast_path_hits: 1),
            totalNs: 4_700_000
        )

        let activity = CoordinatorActivity(
            verb: .buildIR,
            exitCode: 0,
            summary: "IR exit 0 · 5 pages",
            timestamp: Date(),
            durationNs: 4_700_000,
            timings: timings,
            problemsCount: 0
        )

        XCTAssertEqual(activity.verb, .buildIR)
        XCTAssertEqual(activity.exitCode, 0)
        XCTAssertTrue(activity.isSuccess)
        XCTAssertEqual(activity.durationNs, 4_700_000)
        XCTAssertEqual(activity.timings?.phases?["scan"], 1_500_000)
        XCTAssertEqual(activity.timings?.counters?.page_reads, 5)

        let failedActivity = CoordinatorActivity(
            verb: .validate,
            exitCode: 1,
            summary: "validate exit 1 · 2 error(s)",
            problemsCount: 2
        )
        XCTAssertFalse(failedActivity.isSuccess)
    }

    func testPublicationPlanDecoding() throws {
        let json = """
        {
          "format": "boris-publication-plan",
          "schema_version": 1,
          "input": "content",
          "input_format": "markdown",
          "site": {
            "url": "https://example.com",
            "title": "Example Site",
            "description": "A demo site"
          },
          "publication": {
            "target": "standard-site",
            "base_url": "https://example.com",
            "origin": "https://example.com",
            "base_path": "",
            "did": "did:plc:12345",
            "name": "Example"
          },
          "targets": [
            {
              "name": "public",
              "output": "dist",
              "public": true,
              "theme": "themes/boris",
              "layout": "default",
              "layout_rules": [
                { "selector": "id:index", "layout": "themes/boris/layouts/home.html" }
              ],
              "projections": {
                "html": true,
                "sitemap": { "path": "sitemap.xml", "limit": null },
                "rss": { "path": "rss.xml", "limit": 20 },
                "llms": { "path": "llms.txt", "limit": null }
              }
            }
          ],
          "editions": {
            "ir": { "output": ".boris" },
            "rag": { "output": "rag", "scope": "all", "split_size": 4096 },
            "context": { "output": "context", "scope": "all", "split_size": 2048 }
          }
        }
        """

        let plan = try JSONDecoder().decode(PublicationPlan.self, from: Data(json.utf8))
        XCTAssertEqual(plan.format, "boris-publication-plan")
        XCTAssertEqual(plan.schema_version, 1)
        XCTAssertEqual(plan.site?.title, "Example Site")
        XCTAssertEqual(plan.publication?.target, "standard-site")
        XCTAssertEqual(plan.targets?.count, 1)

        let target = try XCTUnwrap(plan.targets?.first)
        XCTAssertEqual(target.name, "public")
        XCTAssertEqual(target.output, "dist")
        XCTAssertEqual(target.public, true)
        XCTAssertEqual(target.theme, "themes/boris")
        XCTAssertEqual(target.layout_rules?.first?.selector, "id:index")
        XCTAssertEqual(target.projections?.html, true)
        XCTAssertEqual(target.projections?.sitemap?.path, "sitemap.xml")
        XCTAssertEqual(target.projections?.rss?.path, "rss.xml")
        XCTAssertEqual(target.projections?.llms?.path, "llms.txt")

        XCTAssertEqual(plan.editions?.ir?.output, ".boris")
        XCTAssertEqual(plan.editions?.rag?.output, "rag")
        XCTAssertEqual(plan.editions?.rag?.split_size, 4096)
        XCTAssertEqual(plan.editions?.context?.output, "context")
    }
}
