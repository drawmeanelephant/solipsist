import Foundation

/// Helper parser for Boris editor token launch lines.
///
/// The afterparty Svelte shell reads the fragment with `URLSearchParams`
/// and takes only `token`. Extra keys are ignored today. A15
/// ([boris#649](https://github.com/drawmeanelephant/boris/issues/649))
/// proposes an optional `open=<project-relative path>` key that the
/// shell would feed to its own `openFile`. This parser matches that
/// `URLSearchParams` shape so a second fragment key is not rejected,
/// and `opening(_:sourcePath:)` is how the companion appends `open=`.
public enum EditorURL {
    public enum ParseError: LocalizedError, Equatable {
        case empty
        case invalidURL
        case notLoopback
        case missingTokenFragment
        case invalidTokenHex

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "Please enter a BORIS_EDITOR_URL line or URL."
            case .invalidURL:
                return "That is not a valid URL."
            case .notLoopback:
                return "Editor URL must use a loopback host (http://127.0.0.1 or http://localhost)."
            case .missingTokenFragment:
                return "Editor URL must include a #token= fragment."
            case .invalidTokenHex:
                return "Editor token fragment must be hexadecimal characters."
            }
        }
    }

    /// Parses a `BORIS_EDITOR_URL=http://127.0.0.1:<port>/#token=<hex>` line or raw URL.
    /// Extra fragment keys (`&open=…`) are allowed; `token` must still be hex.
    public static func parse(_ raw: String) throws -> URL {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("BORIS_EDITOR_URL=") {
            trimmed = String(trimmed.dropFirst("BORIS_EDITOR_URL=".count))
        }
        guard !trimmed.isEmpty else {
            throw ParseError.empty
        }
        guard let components = URLComponents(string: trimmed), let url = components.url else {
            throw ParseError.invalidURL
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" else {
            throw ParseError.invalidURL
        }
        guard let host = components.host?.lowercased(), host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]" else {
            throw ParseError.notLoopback
        }
        guard let token = fragmentItems(components.fragment).first(where: { $0.name == "token" })?.value else {
            throw ParseError.missingTokenFragment
        }
        guard !token.isEmpty, token.allSatisfy(\.isHexDigit) else {
            throw ParseError.invalidTokenHex
        }

        return url
    }

    /// Appends or replaces `open=` with the author-owned project path for
    /// a graph `sourcePath`. Returns `url` unchanged when the path is
    /// missing or would fail `file_api.validatePath`.
    public static func opening(_ url: URL, sourcePath: String?) -> URL {
        guard let project = projectPath(fromSourcePath: sourcePath) else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = fragmentItems(components.fragment).filter { $0.name != "open" }
        items.append(URLQueryItem(name: "open", value: project))
        components.fragment = encodedFragment(items)
        return components.url ?? url
    }

    /// Maps a graph `sourcePath` (content-root relative) onto the
    /// project-relative path `boris-editor` accepts. Matches the Svelte
    /// shell's `projectPathForProblem`: `content/` / `themes/` / `boris.json`
    /// pass through; everything else is prefixed with `content/`.
    public static func projectPath(fromSourcePath sourcePath: String?) -> String? {
        guard let raw = sourcePath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let normalized = raw.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") { return nil }
        let project: String
        if normalized == "boris.json" || normalized.hasPrefix("content/") || normalized.hasPrefix("themes/") {
            project = normalized
        } else {
            project = "content/" + normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return isAuthorOwned(project) ? project : nil
    }

    /// Returns a display string for an editor URL with the security token masked.
    public static func maskedDisplayString(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        let items = fragmentItems(components.fragment)
        guard !items.isEmpty else { return url.absoluteString }

        let maskedPairs = items.map { item -> String in
            if item.name == "token" {
                return "token=••••••••"
            } else if let val = item.value {
                return "\(item.name)=\(val)"
            } else {
                return item.name
            }
        }
        let fragmentStr = maskedPairs.joined(separator: "&")

        var base = components
        base.fragment = nil
        let baseStr = base.url?.absoluteString ?? url.absoluteString
        return "\(baseStr)#\(fragmentStr)"
    }

    /// #237: Extracts `host:port` from a URL for the redacted toolbar
    /// display. Handles IPv6 (`[::1]:9000`), IPv4 (`127.0.0.1:9000`),
    /// and `localhost:9000`.
    public static func hostPort(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        let host = components.host ?? "?"
        let port = components.port.map { ":\($0)" } ?? ""
        if host.contains(":") {
            if host.hasPrefix("[") {
                return "\(host)\(port)"
            }
            return "[\(host)]\(port)"
        }
        return "\(host)\(port)"
    }

    // MARK: - Fragment (URLSearchParams)

    private static func fragmentItems(_ fragment: String?) -> [URLQueryItem] {
        guard let fragment, !fragment.isEmpty else { return [] }
        var components = URLComponents()
        components.percentEncodedQuery = fragment
        return components.queryItems ?? []
    }

    private static func encodedFragment(_ items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery ?? ""
    }

    /// afterparty `editor/src/file_api.zig` `validatePath`: no leading `/`,
    /// no empty/`.`/`..` segments, author-owned roots only.
    private static func isAuthorOwned(_ path: String) -> Bool {
        if path.isEmpty || path.count > 4096 { return false }
        if path.hasPrefix("/") { return false }
        if path.contains("\\") || path.contains("\0") { return false }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        for segment in segments {
            if segment.isEmpty || segment == "." || segment == ".." { return false }
        }
        return path == "boris.json"
            || path.hasPrefix("content/")
            || path.hasPrefix("themes/")
    }
}
