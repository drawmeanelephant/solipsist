import Foundation

/// The three Oliver frontends (`oliver render --from …`).
public enum OliverFrontend: String, Sendable {
    case markdown
    case textile
    case cooklang
}

/// `--to` render profile: HTML (default) or the XML-compatible fragment.
public enum OliverRenderProfile: String, Sendable {
    case html
    case xhtml
}

/// `--raw-html` policy for raw HTML/HTML blocks.
public enum OliverRawHTMLPolicy: String, Sendable {
    case allowed
    case escaped
    case rejected
}

/// `--frontmatter` policy for the shared pre-pass (`src/frontmatter.zig`).
public enum OliverFrontmatterPolicy: String, Sendable {
    case none
    case yaml
    case toml
}

/// Render options mirroring Oliver's `ParseOptions` — every flag is off by
/// default, exactly as in Oliver (`docs/CAPABILITIES.md`, `docs/FEATURE-MATRIX.md`).
public struct OliverRenderOptions: Sendable, Equatable {
    public var profile: OliverRenderProfile = .html
    public var wikilinks = false
    public var callouts = false
    public var smartypants = false
    public var footnotes = false
    public var definitionLists = false
    public var headingAttributes = false
    public var strikethrough = false
    public var headingIDs = false
    public var taskLists = false
    public var rawHTML: OliverRawHTMLPolicy = .allowed
    public var frontmatter: OliverFrontmatterPolicy = .none

    public init() {}

    /// The CLI arguments for `oliver render --from <frontend> …`.
    /// Only non-default options are emitted, mirroring the documented CLI.
    public func arguments(frontend: OliverFrontend) -> [String] {
        var args = ["render", "--from", frontend.rawValue]
        if profile != .html {
            args += ["--to", profile.rawValue]
        }
        if wikilinks { args.append("--wikilinks") }
        if callouts { args.append("--callouts") }
        if smartypants { args.append("--smartypants") }
        if footnotes { args.append("--footnotes") }
        if definitionLists { args.append("--definition-lists") }
        if headingAttributes { args.append("--heading-attributes") }
        if strikethrough { args.append("--strikethrough") }
        if headingIDs { args.append("--heading-ids") }
        if taskLists { args.append("--task-lists") }
        if rawHTML != .allowed {
            args += ["--raw-html", rawHTML.rawValue]
        }
        if frontmatter != .none {
            args += ["--frontmatter", frontmatter.rawValue]
        }
        return args
    }
}

/// Result of a successful `oliver render` invocation.
public struct OliverRenderResult: Sendable {
    public let html: String
    public let exitCode: Int32
    public let stderr: String
}

public enum OliverRenderError: Error, Sendable, CustomStringConvertible {
    case binaryNotFound
    case renderFailed(exitCode: Int32, stderr: String)

    public var description: String {
        switch self {
        case .binaryNotFound:
            return "oliver renderer not found (set SOLIPSIST_OLIVER_BIN, bundle oliver, or build ../oliver)"
        case .renderFailed(let exitCode, let stderr):
            let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = tail.isEmpty ? "" : " — \(tail.suffix(200))"
            return "oliver render failed (exit \(exitCode))\(suffix)"
        }
    }
}

/// The Engine seam for markup rendering. Lives in the Engine lane because
/// only the Engine starts subprocesses (`agents.md` boundary 5) — it reuses
/// `BorisRunner` (same capture + interrupt machinery), never a new Process
/// owner. Renders one buffer per call; cancellation terminates the child.
public struct OliverRenderer: Sendable {
    public let binaryURL: URL?

    public init(binaryURL: URL? = nil) {
        if let binaryURL {
            self.binaryURL = binaryURL
        } else {
            self.binaryURL = OliverBinary.locate()
        }
    }

    public func render(
        source: String,
        frontend: OliverFrontend,
        options: OliverRenderOptions = OliverRenderOptions()
    ) async throws -> OliverRenderResult {
        guard let binaryURL else {
            throw OliverRenderError.binaryNotFound
        }
        let handle = RunHandle()
        return try await withTaskCancellationHandler {
            let output = try await BorisRunner.run(
                binary: binaryURL,
                arguments: options.arguments(frontend: frontend),
                handle: handle,
                stdinText: source
            )
            guard output.exitCode == 0 else {
                throw OliverRenderError.renderFailed(exitCode: output.exitCode, stderr: output.stderrText)
            }
            return OliverRenderResult(html: output.stdoutText, exitCode: output.exitCode, stderr: output.stderrText)
        } onCancel: {
            handle.terminate()
        }
    }
}
