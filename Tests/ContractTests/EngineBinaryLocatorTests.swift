import XCTest

final class EngineBinaryLocatorTests: XCTestCase {
    override func tearDown() {
        for key in EngineBinaryDefaults.legacyKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Environment rung stays first (#292 must-not-land guard)

    func testBorisEnvironmentOverrideWins() {
        let url = BorisBinary.locate(environment: ["SOLIPSIST_BORIS_BIN": "/bin/ls"])
        XCTAssertEqual(url?.path, "/bin/ls")
    }

    func testOliverEnvironmentOverrideWins() {
        let url = OliverBinary.locate(
            environment: ["SOLIPSIST_OLIVER_BIN": "/bin/ls"],
            borisBinary: nil
        )
        XCTAssertEqual(url?.path, "/bin/ls")
    }

    // MARK: - Stale custom-path defaults are ignored

    func testStaleBorisDefaultDoesNotShadowResolution() {
        UserDefaults.standard.set("/bin/echo", forKey: "customBorisBinaryPath")
        let url = BorisBinary.locate(environment: [:])
        XCTAssertNotEqual(url?.path, "/bin/echo")
    }

    func testStaleOliverDefaultDoesNotShadowResolution() {
        UserDefaults.standard.set("/bin/echo", forKey: "customOliverBinaryPath")
        let url = OliverBinary.locate(environment: [:], borisBinary: nil)
        XCTAssertNotEqual(url?.path, "/bin/echo")
    }

    func testStaleEditorDefaultDoesNotShadowResolution() {
        UserDefaults.standard.set("/bin/echo", forKey: "customBorisEditorBinaryPath")
        let url = EditorServerFactory.findEditorBinary(
            relativeTo: URL(fileURLWithPath: "/usr/bin/boris")
        )
        XCTAssertNotEqual(url?.path, "/bin/echo")
    }

    // MARK: - Launch-time cleanup of legacy keys

    func testRemoveLegacyCustomPathsClearsAllThreeKeys() {
        let defaults = UserDefaults.standard
        defaults.set("/bin/echo", forKey: "customBorisBinaryPath")
        defaults.set("/bin/echo", forKey: "customOliverBinaryPath")
        defaults.set("/bin/echo", forKey: "customBorisEditorBinaryPath")

        EngineBinaryDefaults.removeLegacyCustomPaths(defaults: defaults)

        for key in EngineBinaryDefaults.legacyKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) should be removed on launch")
        }
    }

    func testRemoveLegacyCustomPathsLeavesOtherKeysAlone() {
        let defaults = UserDefaults.standard
        defaults.set("keep me", forKey: "someUnrelatedKey")
        defer { defaults.removeObject(forKey: "someUnrelatedKey") }

        EngineBinaryDefaults.removeLegacyCustomPaths(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "someUnrelatedKey"), "keep me")
    }
}
