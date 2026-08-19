import Foundation

/// One parsed SSE event from the watch helper's `/__boris/events` stream.
/// The only event the letter acts on is `reload`; the parser is generic so
/// the wire format is covered by tests.
struct SSEEvent: Equatable {
    var name: String
    var data: String
}

/// Incremental EventSource line parser. Feed one line at a time; a blank
/// line dispatches the buffered event. `:` comments and `id:` / `retry:`
/// fields are ignored; repeated `data:` lines join with a newline.
struct SSEParser {
    private var eventName = "message"
    private var dataLines: [String] = []

    mutating func feed(line: String) -> [SSEEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            guard !dataLines.isEmpty || eventName != "message" else { return [] }
            defer {
                eventName = "message"
                dataLines = []
            }
            return [SSEEvent(name: eventName, data: dataLines.joined(separator: "\n"))]
        }
        guard !trimmed.hasPrefix(":") else { return [] }
        if let colon = trimmed.firstIndex(of: ":") {
            let field = trimmed[..<colon]
            var value = String(trimmed[trimmed.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
            switch field {
            case "event":
                eventName = value
            case "data":
                dataLines.append(value)
            default:
                break
            }
        } else if trimmed == "event" {
            eventName = ""
        } else if trimmed == "data" {
            dataLines.append("")
        }
        return []
    }
}

/// Decides when the letter listens for SSE reloads (M14-2). The channel is
/// only the existing helper's `/__boris/events` — never a second watch, and
/// never a foreign helper: a bound-root mismatch (or watch down, or no page
/// showing) means idle.
enum LetterReloadPolicy {
    static func eventsURL(helper: URL?, bound: Bool, showingPage: Bool) -> URL? {
        guard bound, showingPage, let helper else { return nil }
        return PreviewURL.eventsURL(fromHelper: helper)
    }
}

/// Watches the existing watch helper's SSE channel and fires `onReload`
/// when the rebuild counter advances. The letter's web view reloads after a
/// rebuild without re-selecting the row and without a second watch.
///
/// The stream's first event on connect carries the *current* counter
/// (`data: 0` right after start) — the letter just loaded the page, so that
/// handshake is recorded, not reloaded. Reloads fire only when the counter
/// advances (or resets after a watch restart).
@MainActor
final class LetterSSEClient {
    var onReload: (() -> Void)?

    private(set) var isConnected = false
    private var task: Task<Void, Never>?
    private var parser = SSEParser()
    private var lastGeneration: Int?

    func connect(to eventsURL: URL) {
        disconnect()
        task = Task { [weak self] in
            await self?.run(eventsURL)
        }
    }

    func disconnect() {
        task?.cancel()
        task = nil
        isConnected = false
        parser = SSEParser()
        lastGeneration = nil
    }

    private func run(_ url: URL) async {
        while !Task.isCancelled {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: URLRequest(url: url))
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    // Watch down or not serving — idle until the pane reconnects.
                    return
                }
                isConnected = true
                // `bytes.lines` does not yield incrementally on this SDK;
                // assemble lines from raw bytes (SSE lines are ASCII).
                var line = ""
                var iterator = bytes.makeAsyncIterator()
                while let byte: UInt8 = try await iterator.next() {
                    if Task.isCancelled { break }
                    if byte == 0x0A {
                        for event in parser.feed(line: line) {
                            handle(event)
                        }
                        line = ""
                    } else if byte != 0x0D {
                        line.append(Character(UnicodeScalar(byte)))
                    }
                }
                isConnected = false
                guard !Task.isCancelled else { break }
                // The server dropped the stream without a restart — reconnect
                // after a beat, like the helper page's EventSource does.
                try? await Task.sleep(for: .seconds(2))
            } catch {
                // Cancelled by disconnect, or the watch is down — idle until
                // the pane's channel identity asks again.
                return
            }
        }
        isConnected = false
    }

    private func handle(_ event: SSEEvent) {
        guard event.name == "reload", let generation = Int(event.data) else { return }
        let (reload, next) = Self.shouldReload(generation: generation, lastGeneration: lastGeneration)
        lastGeneration = next
        if reload {
            onReload?()
        }
    }

    /// Pure reload policy. The first event after connect is the current-state
    /// handshake — record without reloading. Later, reload when the counter
    /// advances or resets; ignore repeats.
    nonisolated static func shouldReload(generation: Int, lastGeneration: Int?) -> (reload: Bool, last: Int) {
        guard let lastGeneration else { return (false, generation) }
        return (generation != lastGeneration, generation)
    }
}
