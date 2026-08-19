import Foundation

/// `git-credential-solipsist` — helper mode of the app binary (M15).
/// Git is configured with
/// `credential.helper=!"<app>" --git-credential-helper`; git runs the
/// app with the operation as its last argument and the credential
/// request on stdin. The helper answers github.com requests from the
/// Keychain (account `github`, host-keyed — git omits the repo `path`
/// from helper input, so a per-repo lookup is impossible) and prints
/// `username=… password=…` on stdout. The token travels Keychain →
/// helper stdout → git's pipe: never argv, never env, never on disk
/// (zero-leak invariant).
enum GitCredentialHelper {
    /// argv marker the app's `init` checks before AppKit starts.
    static let flag = "--git-credential-helper"

    static func runAndExit() -> Never {
        exit(run())
    }

    /// One helper invocation. Non-`get` operations (git may ask to
    /// `store`/`erase`) are drained and ignored — the token only ever
    /// enters the Keychain through the app's own flow. No matching
    /// token → clean exit with no output; git fails with its own auth
    /// error (which we surface verbatim).
    static func run() -> Int32 {
        let operation = CommandLine.arguments.dropFirst(2).first ?? "get"
        guard operation == "get" else {
            _ = readStdin()
            return 0
        }
        let input = readStdin()
        guard let output = credentialOutput(input: input, store: GithubTokenStore()) else {
            return 0
        }
        writeStdout(output)
        return 0
    }

    /// Produce the credential lines when the request is for github.com
    /// and a token exists; nil otherwise. The loaded token is wiped
    /// after the output string is built.
    static func credentialOutput(input: String, store: GithubTokenStore) -> String? {
        guard isGitHubHost(input) else { return nil }
        guard let token = try? store.load() else { return nil }
        let password = String(data: Data(token.copyBytes()), encoding: .utf8) ?? ""
        token.wipe()
        return "username=x-access-token\npassword=\(password)\n"
    }

    /// git sends `protocol=…`, `host=…`, `username=…` (no `path`).
    static func isGitHubHost(_ input: String) -> Bool {
        for line in input.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if key == "host" {
                return value.lowercased() == "github.com"
            }
        }
        return false
    }

    private static func readStdin() -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func writeStdout(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}
