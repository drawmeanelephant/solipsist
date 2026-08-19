import XCTest

final class GitCredentialHelperTests: XCTestCase {
    // MARK: - Host gating

    func testAcceptsGitHubHost() {
        XCTAssertTrue(GitCredentialHelper.isGitHubHost("protocol=https\nhost=github.com\n"))
    }

    func testAcceptsHostWithTrailingLine() {
        XCTAssertTrue(GitCredentialHelper.isGitHubHost("protocol=https\nhost=github.com\nusername=git\n"))
    }

    func testRejectsOtherHosts() {
        XCTAssertFalse(GitCredentialHelper.isGitHubHost("protocol=https\nhost=gitlab.com\n"))
        XCTAssertFalse(GitCredentialHelper.isGitHubHost("protocol=https\nhost=github.com.evil.example\n"))
    }

    func testAcceptsCaseInsensitiveHost() {
        XCTAssertTrue(GitCredentialHelper.isGitHubHost("protocol=https\nhost=GITHUB.COM\n"))
    }

    func testRejectsMissingHost() {
        XCTAssertFalse(GitCredentialHelper.isGitHubHost("protocol=https\n"))
        XCTAssertFalse(GitCredentialHelper.isGitHubHost(""))
    }

    // MARK: - Credential output

    func testCredentialOutputPrintsTokenLines() throws {
        let store = GithubTokenStore(keychain: MockKeychainStore(), service: "test.service")
        try store.save(SecureBuffer(utf8String: "gho_secret"))

        let output = GitCredentialHelper.credentialOutput(
            input: "protocol=https\nhost=github.com\nusername=git\n",
            store: store
        )

        XCTAssertEqual(output, "username=x-access-token\npassword=gho_secret\n")
    }

    func testCredentialOutputNilWithoutToken() {
        let store = GithubTokenStore(keychain: MockKeychainStore(), service: "test.service")

        XCTAssertNil(GitCredentialHelper.credentialOutput(
            input: "protocol=https\nhost=github.com\n",
            store: store
        ))
    }

    func testCredentialOutputNilForOtherHost() throws {
        let store = GithubTokenStore(keychain: MockKeychainStore(), service: "test.service")
        try store.save(SecureBuffer(utf8String: "gho_secret"))

        XCTAssertNil(GitCredentialHelper.credentialOutput(
            input: "protocol=https\nhost=gitlab.com\n",
            store: store
        ))
    }

    func testCredentialOutputIgnoresRequestedUsername() throws {
        let store = GithubTokenStore(keychain: MockKeychainStore(), service: "test.service")
        try store.save(SecureBuffer(utf8String: "gho_secret"))

        let output = GitCredentialHelper.credentialOutput(
            input: "protocol=https\nhost=github.com\nusername=someone-else\n",
            store: store
        )

        // We answer with the machine token regardless of the username
        // git asks for (git omits the repo path, so this is the only
        // GitHub token we can serve).
        XCTAssertEqual(output, "username=x-access-token\npassword=gho_secret\n")
    }

    // MARK: - Git config wiring

    func testCredentialHelperArgumentsUseShellQuotedAppPath() {
        let app = URL(fileURLWithPath: "/tmp/Solipsist.app/Contents/MacOS/Solipsist")
        let args = GitClone.credentialHelperArguments(appURL: app)

        XCTAssertEqual(args.count, 2)
        XCTAssertEqual(args[0], "-c")
        XCTAssertEqual(
            args[1],
            "credential.helper=!\"/tmp/Solipsist.app/Contents/MacOS/Solipsist\" --git-credential-helper"
        )
    }

    func testCredentialHelperArgumentsQuoteSpacesAndShellChars() {
        let app = URL(fileURLWithPath: "/tmp/app dir/$Solipsist")
        let args = GitClone.credentialHelperArguments(appURL: app)

        XCTAssertEqual(
            args[1],
            "credential.helper=!\"/tmp/app dir/\\$Solipsist\" --git-credential-helper"
        )
    }
}
