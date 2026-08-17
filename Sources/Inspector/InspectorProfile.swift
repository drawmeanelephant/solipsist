import Foundation

/// Inspector-local slice of `boris.json`. Fields are read from
/// `PublicationProfile` when it decodes; Save overlays only these keys
/// onto the existing object so `targets` / `editions` / `nostr` survive
/// (encoding the shared type would drop `nostr`).
struct InspectorProfileFields: Equatable, Sendable {
    var input: String = ""
    var inputFormat: String = "markdown"
    var siteTitle: String = ""
    var siteURL: String = ""
    var publicationTarget: String = ""

    static let empty = InspectorProfileFields()
}

enum InspectorProfileError: Error, Sendable {
    case notAnObject
}

enum InspectorProfile {
    static let fileName = "boris.json"
    static let inputFormats = ["markdown", "textile", "cook"]
    static let publicationTargets = ["github-pages", "standard-site"]

    static func url(in root: URL) -> URL {
        root.appendingPathComponent(fileName, isDirectory: false)
    }

    static func load(from root: URL) throws -> (fields: InspectorProfileFields, data: Data)? {
        let fileURL = url(in: root)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        if let profile = try? JSONDecoder().decode(PublicationProfile.self, from: data) {
            return (fields(from: profile), data)
        }
        // Typed decode failed (D8). Still offer the keys we edit if the
        // file is a JSON object, so a missing Models field cannot crash.
        return (fields(from: try jsonObject(from: data)), data)
    }

    static func save(to root: URL, original: Data, fields: InspectorProfileFields) throws {
        let object = try jsonObject(from: original)
        let merged = overlay(object, fields: fields)
        let data = try encode(merged)
        try data.write(to: url(in: root), options: .atomic)
    }

    static func fields(from profile: PublicationProfile) -> InspectorProfileFields {
        InspectorProfileFields(
            input: profile.input ?? "",
            inputFormat: profile.input_format ?? "markdown",
            siteTitle: profile.site?.title ?? "",
            siteURL: profile.site?.url ?? "",
            publicationTarget: profile.publication?.target ?? ""
        )
    }

    static func fields(from object: [String: Any]) -> InspectorProfileFields {
        let site = object["site"] as? [String: Any] ?? [:]
        let publication = object["publication"] as? [String: Any] ?? [:]
        return InspectorProfileFields(
            input: string(object["input"]),
            inputFormat: {
                let value = string(object["input_format"])
                return value.isEmpty ? "markdown" : value
            }(),
            siteTitle: string(site["title"]),
            siteURL: string(site["url"]),
            publicationTarget: string(publication["target"])
        )
    }

    static func overlay(_ root: [String: Any], fields: InspectorProfileFields) -> [String: Any] {
        var object = root
        setOrRemove(&object, key: "input", string: fields.input)
        setOrRemove(&object, key: "input_format", string: fields.inputFormat)

        var site = object["site"] as? [String: Any] ?? [:]
        setOrRemove(&site, key: "title", string: fields.siteTitle)
        setOrRemove(&site, key: "url", string: fields.siteURL)
        if site.isEmpty {
            object.removeValue(forKey: "site")
        } else {
            object["site"] = site
        }

        if var publication = object["publication"] as? [String: Any] {
            setOrRemove(&publication, key: "target", string: fields.publicationTarget)
            if publication.isEmpty {
                object.removeValue(forKey: "publication")
            } else {
                object["publication"] = publication
            }
        } else if !fields.publicationTarget.isEmpty {
            object["publication"] = ["target": fields.publicationTarget]
        }
        return object
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? [String: Any] else {
            throw InspectorProfileError.notAnObject
        }
        return object
    }

    private static func encode(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        if let text = String(data: data, encoding: .utf8), !text.hasSuffix("\n") {
            data = Data((text + "\n").utf8)
        }
        return data
    }

    private static func setOrRemove(_ object: inout [String: Any], key: String, string: String) {
        if string.isEmpty {
            object.removeValue(forKey: key)
        } else {
            object[key] = string
        }
    }

    private static func string(_ value: Any?) -> String {
        value as? String ?? ""
    }
}
