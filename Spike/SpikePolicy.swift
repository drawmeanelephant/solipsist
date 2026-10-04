import Foundation

struct SpikeFailure: Error, CustomStringConvertible {
    let exitCode: Int32
    let description: String
}

/// The spike chooses a noun from the returned contract, not from a
/// particular dogfood corpus. It never computes an impact graph itself.
enum SpikePolicy {
    static func impactTarget(in graph: Graph?, requested: String?) throws -> String {
        guard let graph else {
            throw SpikeFailure(exitCode: 3, description: "IR build returned no decodable graph.json.")
        }
        guard !graph.nodes.isEmpty else {
            throw SpikeFailure(exitCode: 1, description: "IR graph has no pages to inspect with impact.")
        }
        if let requested {
            guard graph.nodes.contains(where: { $0.id == requested }) else {
                let examples = graph.nodes.prefix(5).map(\.id).joined(separator: ", ")
                throw SpikeFailure(exitCode: 2, description: "Impact page “\(requested)” is not in the supplied graph. Available IDs include: \(examples).")
            }
            return requested
        }
        return graph.nodes[0].id
    }

    static func requireSuccess(_ code: Int32, command: String, stderr: String = "") throws {
        guard code == 0 else {
            let diagnostic = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = diagnostic.isEmpty ? "" : "\n\(diagnostic)"
            throw SpikeFailure(exitCode: code > 0 && code < 256 ? code : 3, description: "\(command) failed (exit \(code)).\(suffix)")
        }
    }

    static func exitCode(for error: any Error) -> Int32 {
        if let failure = error as? SpikeFailure { return failure.exitCode }
        if let failure = error as? BorisAnalysisFailure, failure.exitCode > 0, failure.exitCode < 256 {
            return failure.exitCode
        }
        return 3
    }
}
