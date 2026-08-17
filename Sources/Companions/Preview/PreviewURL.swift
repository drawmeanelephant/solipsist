import Foundation

/// Loopback validation rules for Boris Preview companion.
public enum PreviewURL {
    public static func isAllowed(_ url: URL) -> Bool {
        if url.absoluteString == "about:blank" { return true }
        return isLoopback(url)
    }

    public static func isLoopback(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" else { return false }
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
    }
}
