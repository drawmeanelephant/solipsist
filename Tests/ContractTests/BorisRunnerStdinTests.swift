import XCTest

final class BorisRunnerStdinTests: XCTestCase {
    func testStdinIsPipedAndWipedNeverArgv() async throws {
        let payload = "nsec1testpayload-not-a-real-key"
        let secret = SecureBuffer(utf8String: payload)
        let output = try await BorisRunner.run(
            binary: URL(fileURLWithPath: "/bin/cat"),
            arguments: [],
            stdin: secret
        )
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.stdoutText, payload + "\n")
        XCTAssertTrue(secret.isEmpty)
        XCTAssertFalse(output.stdoutText.contains("key-stdin"))
    }

    func testNilStdinDoesNotHangCat() async throws {
        // /bin/true ignores stdin and exits 0.
        let output = try await BorisRunner.run(
            binary: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: []
        )
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertTrue(output.stdout.isEmpty)
    }
}
