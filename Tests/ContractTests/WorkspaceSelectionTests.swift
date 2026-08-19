import XCTest

final class WorkspaceSelectionTests: XCTestCase {
    private let sourceA = SourceID()
    private let sourceB = SourceID()
    private let page = WorkspaceNoun(kind: "page", id: "index", title: "Home")
    private let target = WorkspaceNoun(kind: "target", id: "html", title: "html")

    func testMemberwiseInitsDefaultMailboxAndSourcePath() {
        let selection = WorkspaceSelection(sourceID: nil, noun: nil)
        XCTAssertNil(selection.mailbox)
        XCTAssertEqual(selection, .empty)

        let noun = WorkspaceNoun(kind: "page", id: "index", title: "Home")
        XCTAssertNil(noun.sourcePath)
    }

    func testDisplayKeepsUnknownItselfAndNilDefaultsToPages() {
        // nil (no mailbox chosen yet) is the default Pages surface.
        XCTAssertEqual(WorkspaceMailbox.display(nil), WorkspaceMailbox.pages)
        // Unknown stays itself — never coerced to Pages (M13, #144).
        XCTAssertEqual(WorkspaceMailbox.display("trunk:guides"), "trunk:guides")
        XCTAssertEqual(WorkspaceMailbox.display("guides/overview"), "guides/overview")
        XCTAssertEqual(WorkspaceMailbox.display("index"), "index")
        XCTAssertEqual(WorkspaceMailbox.display(""), "")
        // Every known token round-trips through display unchanged.
        for token in WorkspaceMailbox.all {
            XCTAssertEqual(WorkspaceMailbox.display(token), token)
        }

        XCTAssertFalse(WorkspaceMailbox.isKnown(nil))
        XCTAssertFalse(WorkspaceMailbox.isKnown("trunk:guides"))
        XCTAssertFalse(WorkspaceMailbox.isKnown("index"))
        XCTAssertTrue(WorkspaceMailbox.isKnown(WorkspaceMailbox.pages))
        XCTAssertTrue(WorkspaceMailbox.isKnown(WorkspaceMailbox.outputs))
        XCTAssertEqual(WorkspaceMailbox.all, [
            WorkspaceMailbox.pages,
            WorkspaceMailbox.outputs,
            WorkspaceMailbox.publish,
            WorkspaceMailbox.plan,
            WorkspaceMailbox.activity,
            WorkspaceMailbox.contentAudit,
        ])
    }

    func testMailboxDisplayNameAndSymbolCoverEveryKnownMailbox() {
        for mailbox in WorkspaceMailbox.all {
            XCTAssertFalse(WorkspaceMailbox.displayName(mailbox).isEmpty)
            XCTAssertFalse(WorkspaceMailbox.symbolName(mailbox).isEmpty)
        }
        XCTAssertEqual(WorkspaceMailbox.displayName(WorkspaceMailbox.pages), "Pages")
        XCTAssertEqual(WorkspaceMailbox.displayName(WorkspaceMailbox.outputs), "Outputs")
        XCTAssertEqual(WorkspaceMailbox.displayName(WorkspaceMailbox.publish), "Publish")
        XCTAssertEqual(WorkspaceMailbox.displayName(WorkspaceMailbox.plan), "Plan")
        XCTAssertEqual(WorkspaceMailbox.displayName(WorkspaceMailbox.activity), "Activity")
        // Unknown raw values display verbatim, never rewritten to Pages.
        XCTAssertEqual(WorkspaceMailbox.displayName("trunk:guides"), "trunk:guides")
        XCTAssertEqual(WorkspaceMailbox.symbolName("trunk:guides"), "folder")
    }

    func testMailboxRowIDHashEquality() {
        let firstRow = MailboxRowID(sourceID: sourceA, mailbox: WorkspaceMailbox.pages)
        let sameRow = MailboxRowID(sourceID: sourceA, mailbox: WorkspaceMailbox.pages)
        XCTAssertEqual(firstRow, sameRow)
        XCTAssertEqual(Set([firstRow, sameRow]).count, 1)
        XCTAssertNotEqual(
            firstRow,
            MailboxRowID(sourceID: sourceA, mailbox: WorkspaceMailbox.outputs)
        )
        XCTAssertNotEqual(
            firstRow,
            MailboxRowID(sourceID: sourceB, mailbox: WorkspaceMailbox.pages)
        )
    }

    func testNounRoundTripsMissingAndPresentSourcePath() throws {
        let withoutPath = WorkspaceNoun(kind: "page", id: "index", title: "Home")
        let decodedMissing = try JSONDecoder().decode(
            WorkspaceNoun.self,
            from: try JSONEncoder().encode(withoutPath)
        )
        XCTAssertNil(decodedMissing.sourcePath)

        let legacy = Data(#"{"kind":"page","id":"index","title":"Home"}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(WorkspaceNoun.self, from: legacy)
        XCTAssertNil(decodedLegacy.sourcePath)
        XCTAssertEqual(decodedLegacy.id, "index")

        let withPath = WorkspaceNoun(
            kind: "page",
            id: "index",
            title: "Home",
            sourcePath: "index.md"
        )
        let decodedPresent = try JSONDecoder().decode(
            WorkspaceNoun.self,
            from: try JSONEncoder().encode(withPath)
        )
        XCTAssertEqual(decodedPresent.sourcePath, "index.md")
    }

    func testCanEditPageRequiresPageNoun() {
        XCTAssertFalse(WorkspaceSelection.empty.canEditPage)
        XCTAssertFalse(
            WorkspaceSelection(sourceID: sourceA, mailbox: WorkspaceMailbox.pages, noun: target)
                .canEditPage
        )
        XCTAssertTrue(
            WorkspaceSelection(sourceID: sourceA, mailbox: WorkspaceMailbox.pages, noun: page)
                .canEditPage
        )
    }

    func testSelectSourceChangeWritesPagesAndClearsNoun() {
        let current = WorkspaceSelection(
            sourceID: sourceA,
            mailbox: WorkspaceMailbox.activity,
            noun: page
        )
        let next = WorkspaceSelectionRules.selectSource(current, id: sourceB)
        XCTAssertEqual(next.sourceID, sourceB)
        XCTAssertEqual(next.mailbox, WorkspaceMailbox.pages)
        XCTAssertNil(next.noun)
    }

    func testSelectSourceSameIdDoesNotClobberMailboxOrNoun() {
        let current = WorkspaceSelection(
            sourceID: sourceA,
            mailbox: WorkspaceMailbox.activity,
            noun: page
        )
        let next = WorkspaceSelectionRules.selectSource(current, id: sourceA)
        XCTAssertEqual(next, current)
    }

    func testSelectSourceNilClearsMailboxAndNoun() {
        let current = WorkspaceSelection(
            sourceID: sourceA,
            mailbox: WorkspaceMailbox.outputs,
            noun: page
        )
        let next = WorkspaceSelectionRules.selectSource(current, id: nil)
        XCTAssertEqual(next, .empty)
    }

    func testSelectMailboxClearsNounAndStoresRaw() {
        let current = WorkspaceSelection(
            sourceID: sourceA,
            mailbox: WorkspaceMailbox.pages,
            noun: page
        )
        let next = WorkspaceSelectionRules.selectMailbox(current, mailbox: WorkspaceMailbox.publish)
        XCTAssertEqual(next.sourceID, sourceA)
        XCTAssertEqual(next.mailbox, WorkspaceMailbox.publish)
        XCTAssertNil(next.noun)

        let unknown = WorkspaceSelectionRules.selectMailbox(current, mailbox: "trunk:guides")
        XCTAssertEqual(unknown.mailbox, "trunk:guides")
        XCTAssertNil(unknown.noun)
    }

    func testSelectMailboxNoopsWhenUnchangedOrNoSource() {
        let current = WorkspaceSelection(
            sourceID: sourceA,
            mailbox: WorkspaceMailbox.plan,
            noun: page
        )
        XCTAssertEqual(
            WorkspaceSelectionRules.selectMailbox(current, mailbox: WorkspaceMailbox.plan),
            current
        )
        XCTAssertEqual(
            WorkspaceSelectionRules.selectMailbox(.empty, mailbox: WorkspaceMailbox.pages),
            .empty
        )
    }

    func testSelectWritesSourceAndMailboxAndClearsNounWhenChanged() {
        let current = WorkspaceSelection(
            sourceID: sourceA,
            mailbox: WorkspaceMailbox.pages,
            noun: page
        )
        let mailboxChange = WorkspaceSelectionRules.select(
            current,
            id: sourceA,
            mailbox: WorkspaceMailbox.outputs
        )
        XCTAssertEqual(mailboxChange.sourceID, sourceA)
        XCTAssertEqual(mailboxChange.mailbox, WorkspaceMailbox.outputs)
        XCTAssertNil(mailboxChange.noun)

        let sourceChange = WorkspaceSelectionRules.select(
            current,
            id: sourceB,
            mailbox: WorkspaceMailbox.pages
        )
        XCTAssertEqual(sourceChange.sourceID, sourceB)
        XCTAssertEqual(sourceChange.mailbox, WorkspaceMailbox.pages)
        XCTAssertNil(sourceChange.noun)

        let sameRow = WorkspaceSelectionRules.select(
            current,
            id: sourceA,
            mailbox: WorkspaceMailbox.pages
        )
        XCTAssertEqual(sameRow, current)
    }

    func testRestoreKeepsRawMailboxIncludingUnknown() {
        XCTAssertEqual(
            WorkspaceSelectionRules.restore(selected: nil, mailbox: WorkspaceMailbox.activity, available: [sourceA]),
            .empty
        )
        XCTAssertEqual(
            WorkspaceSelectionRules.restore(selected: sourceB, mailbox: WorkspaceMailbox.activity, available: [sourceA]),
            .empty
        )

        let known = WorkspaceSelectionRules.restore(
            selected: sourceA,
            mailbox: WorkspaceMailbox.activity,
            available: [sourceA]
        )
        XCTAssertEqual(known.sourceID, sourceA)
        XCTAssertEqual(known.mailbox, WorkspaceMailbox.activity)
        XCTAssertNil(known.noun)

        let unknown = WorkspaceSelectionRules.restore(
            selected: sourceA,
            mailbox: "trunk:guides",
            available: [sourceA]
        )
        XCTAssertEqual(unknown.mailbox, "trunk:guides")
        XCTAssertNotEqual(unknown.mailbox, WorkspaceMailbox.pages)

        let missing = WorkspaceSelectionRules.restore(
            selected: sourceA,
            mailbox: nil,
            available: [sourceA]
        )
        XCTAssertNil(missing.mailbox)
        XCTAssertEqual(WorkspaceMailbox.display(missing.mailbox), WorkspaceMailbox.pages)
    }
}
