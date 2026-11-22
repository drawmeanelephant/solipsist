import Foundation

/// Minimal POSIX ustar `.tar` reader for `boris-package` archives (`packages/*.tar`).
/// Extracts named metadata files (`MACHINE-READABLE-VERSION.json`, `SHA256SUMS`)
/// in-process without spawning `/usr/bin/tar`, keeping the sandbox clean.
public enum PackageArchiveReader {
    private static let blockSize = 512

    public static func readEntry(endingWith suffix: String, fromArchiveAt url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return readEntry(endingWith: suffix, from: data)
    }

    public static func readEntry(endingWith suffix: String, from tarData: Data) -> Data? {
        var offset = 0
        let count = tarData.count
        while offset + blockSize <= count {
            let header = tarData[offset..<(offset + blockSize)]
            if header.allSatisfy({ $0 == 0 }) {
                break
            }
            let name = parseString(header, offset: 0, length: 100)
            let prefix = parseString(header, offset: 345, length: 155)
            let fullName = prefix.isEmpty ? name : "\(prefix)/\(name)"
            let size = parseOctal(header, offset: 124, length: 12)
            let typeFlag = header[header.startIndex + 156]
            let dataStart = offset + blockSize
            let dataEnd = dataStart + size
            guard dataEnd <= count else { break }

            let isRegularFile = typeFlag == 0 || typeFlag == UInt8(ascii: "0")
            if isRegularFile, fullName == suffix || fullName.hasSuffix("/\(suffix)") {
                return Data(tarData[dataStart..<dataEnd])
            }

            let padded = ((size + blockSize - 1) / blockSize) * blockSize
            offset = dataStart + padded
        }
        return nil
    }

    private static func parseString(_ header: Data.SubSequence, offset: Int, length: Int) -> String {
        let start = header.startIndex + offset
        let slice = header[start..<(start + length)]
        let trimmed = slice.prefix(while: { $0 != 0 })
        return String(bytes: trimmed, encoding: .utf8) ?? ""
    }

    private static func parseOctal(_ header: Data.SubSequence, offset: Int, length: Int) -> Int {
        let text = parseString(header, offset: offset, length: length)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        return Int(text, radix: 8) ?? 0
    }
}

/// Resolves `_boris/proof/` evidence directories for a workspace.
/// Boris emits proof packs inside each HTML target's output tree (e.g.
/// `dist/_boris/proof/`); older fixtures or custom layouts may also place
/// them at `<workspaceRoot>/_boris/proof/`.
public enum PublishEvidenceLocator {
    public static func proofDirectories(
        workspaceRoot: URL,
        profile: PublicationProfile?
    ) -> [URL] {
        var candidates: [URL] = []
        if let targets = profile?.targets, !targets.isEmpty {
            let ordered = targets.sorted { ($0.public == true ? 0 : 1) < ($1.public == true ? 0 : 1) }
            for target in ordered where !target.output.isEmpty {
                candidates.append(
                    workspaceRoot
                        .appendingPathComponent(target.output, isDirectory: true)
                        .appendingPathComponent("_boris/proof", isDirectory: true)
                        .standardizedFileURL
                )
            }
        }
        candidates.append(
            workspaceRoot
                .appendingPathComponent("dist/_boris/proof", isDirectory: true)
                .standardizedFileURL
        )
        candidates.append(
            workspaceRoot
                .appendingPathComponent("_boris/proof", isDirectory: true)
                .standardizedFileURL
        )
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.path).inserted }
    }

    public static func activeProofDirectory(
        workspaceRoot: URL,
        profile: PublicationProfile?
    ) -> URL? {
        let fileManager = FileManager.default
        for dir in proofDirectories(workspaceRoot: workspaceRoot, profile: profile) {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                return dir
            }
        }
        return nil
    }
}
