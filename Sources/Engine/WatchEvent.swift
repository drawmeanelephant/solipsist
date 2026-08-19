import Foundation

/// One line of the A1 `--watch-json` NDJSON stream (boris#648; contract
/// `docs/issues/boris-A1-watch-events.md`). The pinned kit (`6b930b7`)
/// emits `watch_events_schema: 1`.
///
/// Additive decode: unknown fields are ignored, unknown `event` values
/// decode as `.unknown` and are skipped — never fatal (D8).
enum WatchEvent: Decodable {
    case hello(schema: Int, compiler: String?)
    case serveStarted(url: URL?, helper: URL?, port: Int?)
    case buildFailed(errors: Int, recoverable: Bool)
    case watchError(message: String, recoverable: Bool)
    case watchStopped(reason: String?)
    case unknown

    enum CodingKeys: String, CodingKey {
        case event
        case watchEventsSchema = "watch_events_schema"
        case compiler
        case url
        case helper
        case port
        case errors
        case recoverable
        case message
        case reason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .event) {
        case "hello":
            self = .hello(
                schema: try c.decodeIfPresent(Int.self, forKey: .watchEventsSchema) ?? 0,
                compiler: try c.decodeIfPresent(String.self, forKey: .compiler)
            )
        case "serve-started":
            self = .serveStarted(
                url: try c.decodeIfPresent(String.self, forKey: .url).flatMap(URL.init(string:)),
                helper: try c.decodeIfPresent(String.self, forKey: .helper).flatMap(URL.init(string:)),
                port: try c.decodeIfPresent(Int.self, forKey: .port)
            )
        case "build-failed":
            self = .buildFailed(
                errors: try c.decodeIfPresent(Int.self, forKey: .errors) ?? 0,
                recoverable: try c.decodeIfPresent(Bool.self, forKey: .recoverable) ?? true
            )
        case "watch-error":
            self = .watchError(
                message: try c.decodeIfPresent(String.self, forKey: .message) ?? "unknown watch error",
                recoverable: try c.decodeIfPresent(Bool.self, forKey: .recoverable) ?? true
            )
        case "watch-stopped":
            self = .watchStopped(reason: try c.decodeIfPresent(String.self, forKey: .reason))
        default:
            self = .unknown
        }
    }

    /// Decodes one NDJSON line. Blank and non-JSON lines return nil —
    /// a hostile or older stderr stream never crashes the consumer.
    static func decode(line: String) -> WatchEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WatchEvent.self, from: data)
    }
}

/// Pure, testable consumer of the A1 NDJSON stream. `WatchServer` feeds
/// complete lines; the parser owns the handshake gate (D8), the helper-URL
/// emission, and problem surfacing — so the behavior is testable without a
/// live `watch` process.
struct WatchStreamParser {
    /// The only known `watch_events_schema`. Unknown versions degrade: the
    /// stream is not trusted and problems are surfaced — no crash.
    static let supportedSchema = 1

    private(set) var handshake: Int?
    private(set) var serveURL: URL?
    private(set) var didServe = false
    private(set) var problems: [String] = []

    mutating func consume(line: String) {
        guard let event = WatchEvent.decode(line: line) else { return }
        switch event {
        case .hello(let schema, _):
            handshake = schema
            if schema != Self.supportedSchema {
                problems.append(
                    "watch events schema \(schema) is not supported (supported: \(Self.supportedSchema))"
                )
            }
        case .serveStarted(let url, let helper, let port):
            // D8: never trust an unknown contract's shapes — the helper URL
            // only counts once the stream handshook with a known schema.
            guard handshake == Self.supportedSchema else {
                problems.append("serve-started before a supported watch events handshake — ignoring")
                return
            }
            guard !didServe, let helperURL = Self.helperURL(url: url, helper: helper, port: port) else {
                return
            }
            didServe = true
            serveURL = helperURL
        case .buildFailed(let errors, let recoverable):
            problems.append(
                "build failed: \(errors) error\(errors == 1 ? "" : "s")\(recoverable ? " (recoverable)" : "")"
            )
        case .watchError(let message, _):
            problems.append("watch error: \(message)")
        case .watchStopped(let reason):
            problems.append("watch stopped: \(reason ?? "unknown reason")")
        case .unknown:
            break
        }
    }

    /// The helper page URL (`…/__boris/`) the preview web view loads. The
    /// A1 contract always carries `helper`; `url` / `port` are fallbacks
    /// for a shape that omits it.
    private static func helperURL(url: URL?, helper: URL?, port: Int?) -> URL? {
        if let helper { return helper }
        if let url { return url.appendingPathComponent("__boris/") }
        if let port { return URL(string: "http://127.0.0.1:\(port)/__boris/") }
        return nil
    }
}
