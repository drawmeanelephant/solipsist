import Foundation

/// Helper parser for Boris editor token launch lines.
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
        guard let fragment = components.fragment, fragment.hasPrefix("token=") else {
            throw ParseError.missingTokenFragment
        }
        let token = String(fragment.dropFirst("token=".count))
        guard !token.isEmpty, token.allSatisfy({ $0.isHexDigit }) else {
            throw ParseError.invalidTokenHex
        }

        return url
    }
}
