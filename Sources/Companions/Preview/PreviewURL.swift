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

    /// Site origin from the helper URL `http://127.0.0.1:PORT/__boris/`.
    public static func siteOrigin(fromHelper helper: URL) -> URL? {
        guard isLoopback(helper) else { return nil }
        var components = URLComponents(url: helper, resolvingAgainstBaseURL: false)
        let path = components?.path ?? ""
        if path == "/__boris" || path.hasPrefix("/__boris/") {
            components?.path = "/"
        }
        components?.fragment = nil
        components?.query = nil
        return components?.url
    }

    /// `GET /{pageID}.html` on the served tree. `pageID` is `GraphNode.id`.
    public static func pageURL(helper: URL, pageID: String) -> URL? {
        guard let origin = siteOrigin(fromHelper: helper) else { return nil }
        let trimmed = pageID.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed + ".html", relativeTo: origin)?.absoluteURL
    }
}
