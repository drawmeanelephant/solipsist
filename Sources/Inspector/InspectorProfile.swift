import Foundation

/// Inspector-local slice of `boris.json`. Fields are read from
/// `PublicationProfile` when it decodes; Save overlays only these keys
/// onto the existing object so `targets` / `editions` / `nostr` survive
/// (encoding the shared type would drop `nostr`).
public struct InspectorProfileFields: Equatable, Sendable {
    public var input: String = ""
    public var inputFormat: String = "markdown"
    public var siteTitle: String = ""
    public var siteURL: String = ""
    public var siteDescription: String = ""

    // Publication Declaration
    public var publicationTarget: String = ""
    public var publicationBaseURL: String = ""
    public var publicationOrigin: String = ""
    public var publicationBasePath: String = ""
    public var publicationSiteKind: String = ""
    public var publicationDid: String = ""
    public var publicationPds: String = ""
    public var publicationPdsOrigin: String = ""
    public var publicationName: String = ""
    public var publicationDescription: String = ""
    public var publicationShowInDiscover: Bool?
    public var publicationPrune: Bool?
    public var publicationInclude: [String] = []
    public var publicationExclude: [String] = []

    // Targets
    public var targets: [PublicationTarget] = []

    // Editions
    public var editions: PublicationEditions = PublicationEditions()

    public static let empty = InspectorProfileFields()

    public init(
        input: String = "",
        inputFormat: String = "markdown",
        siteTitle: String = "",
        siteURL: String = "",
        siteDescription: String = "",
        publicationTarget: String = "",
        publicationBaseURL: String = "",
        publicationOrigin: String = "",
        publicationBasePath: String = "",
        publicationSiteKind: String = "",
        publicationDid: String = "",
        publicationPds: String = "",
        publicationPdsOrigin: String = "",
        publicationName: String = "",
        publicationDescription: String = "",
        publicationShowInDiscover: Bool? = nil,
        publicationPrune: Bool? = nil,
        publicationInclude: [String] = [],
        publicationExclude: [String] = [],
        targets: [PublicationTarget] = [],
        editions: PublicationEditions = PublicationEditions()
    ) {
        self.input = input
        self.inputFormat = inputFormat
        self.siteTitle = siteTitle
        self.siteURL = siteURL
        self.siteDescription = siteDescription
        self.publicationTarget = publicationTarget
        self.publicationBaseURL = publicationBaseURL
        self.publicationOrigin = publicationOrigin
        self.publicationBasePath = publicationBasePath
        self.publicationSiteKind = publicationSiteKind
        self.publicationDid = publicationDid
        self.publicationPds = publicationPds
        self.publicationPdsOrigin = publicationPdsOrigin
        self.publicationName = publicationName
        self.publicationDescription = publicationDescription
        self.publicationShowInDiscover = publicationShowInDiscover
        self.publicationPrune = publicationPrune
        self.publicationInclude = publicationInclude
        self.publicationExclude = publicationExclude
        self.targets = targets
        self.editions = editions
    }
}

public enum InspectorProfileError: Error, Sendable {
    case notAnObject
}

public enum InspectorProfile {
    public static let fileName = "boris.json"
    public static let inputFormats = ["markdown", "textile", "cook"]
    public static let publicationTargets = ["github-pages", "standard-site"]

    public static func url(in root: URL) -> URL {
        root.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func targetURL(in root: URL) -> URL {
        let direct = url(in: root)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        let parent = url(in: root.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: parent.path) {
            return parent
        }
        return direct
    }

    public static func load(from root: URL) throws -> (fields: InspectorProfileFields, data: Data)? {
        let fileURL = targetURL(in: root)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        if let profile = try? JSONDecoder().decode(PublicationProfile.self, from: data) {
            return (fields(from: profile), data)
        }
        // Typed decode failed (D8). Still offer the keys we edit if the
        // file is a JSON object, so a missing Models field cannot crash.
        return (fields(from: try jsonObject(from: data)), data)
    }

    public static func save(to root: URL, original: Data, fields: InspectorProfileFields) throws {
        let fileURL = targetURL(in: root)
        let object = try jsonObject(from: original)
        let merged = overlay(object, fields: fields)
        let data = try encode(merged)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func fields(from profile: PublicationProfile) -> InspectorProfileFields {
        InspectorProfileFields(
            input: profile.input ?? "",
            inputFormat: profile.input_format ?? "markdown",
            siteTitle: profile.site?.title ?? "",
            siteURL: profile.site?.url ?? "",
            siteDescription: profile.site?.description ?? "",
            publicationTarget: profile.publication?.target ?? "",
            publicationBaseURL: profile.publication?.base_url ?? "",
            publicationOrigin: profile.publication?.origin ?? "",
            publicationBasePath: profile.publication?.base_path ?? "",
            publicationSiteKind: profile.publication?.site_kind ?? "",
            publicationDid: profile.publication?.did ?? "",
            publicationPds: profile.publication?.pds ?? "",
            publicationPdsOrigin: profile.publication?.pds_origin ?? "",
            publicationName: profile.publication?.name ?? "",
            publicationDescription: profile.publication?.description ?? "",
            publicationShowInDiscover: profile.publication?.show_in_discover,
            publicationPrune: profile.publication?.prune,
            publicationInclude: profile.publication?.include ?? [],
            publicationExclude: profile.publication?.exclude ?? [],
            targets: profile.targets ?? [],
            editions: profile.editions ?? PublicationEditions()
        )
    }

    public static func fields(from object: [String: Any]) -> InspectorProfileFields {
        let site = object["site"] as? [String: Any] ?? [:]
        let publication = object["publication"] as? [String: Any] ?? [:]
        var targets: [PublicationTarget] = []
        if let rawTargets = object["targets"] as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: rawTargets),
           let decoded = try? JSONDecoder().decode([PublicationTarget].self, from: data)
        {
            targets = decoded
        }
        var editions = PublicationEditions()
        if let rawEditions = object["editions"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: rawEditions),
           let decoded = try? JSONDecoder().decode(PublicationEditions.self, from: data)
        {
            editions = decoded
        }

        return InspectorProfileFields(
            input: string(object["input"]),
            inputFormat: {
                let value = string(object["input_format"])
                return value.isEmpty ? "markdown" : value
            }(),
            siteTitle: string(site["title"]),
            siteURL: string(site["url"]),
            siteDescription: string(site["description"]),
            publicationTarget: string(publication["target"]),
            publicationBaseURL: string(publication["base_url"]),
            publicationOrigin: string(publication["origin"]),
            publicationBasePath: string(publication["base_path"]),
            publicationSiteKind: string(publication["site_kind"]),
            publicationDid: string(publication["did"]),
            publicationPds: string(publication["pds"]),
            publicationPdsOrigin: string(publication["pds_origin"]),
            publicationName: string(publication["name"]),
            publicationDescription: string(publication["description"]),
            publicationShowInDiscover: publication["show_in_discover"] as? Bool,
            publicationPrune: publication["prune"] as? Bool,
            publicationInclude: publication["include"] as? [String] ?? [],
            publicationExclude: publication["exclude"] as? [String] ?? [],
            targets: targets,
            editions: editions
        )
    }

    public static func overlay(_ root: [String: Any], fields: InspectorProfileFields) -> [String: Any] {
        var object = root
        setOrRemove(&object, key: "input", string: fields.input)
        setOrRemove(&object, key: "input_format", string: fields.inputFormat)

        var site = object["site"] as? [String: Any] ?? [:]
        setOrRemove(&site, key: "title", string: fields.siteTitle)
        setOrRemove(&site, key: "url", string: fields.siteURL)
        setOrRemove(&site, key: "description", string: fields.siteDescription)
        if site.isEmpty {
            object.removeValue(forKey: "site")
        } else {
            object["site"] = site
        }

        var pub = object["publication"] as? [String: Any] ?? [:]
        setOrRemove(&pub, key: "target", string: fields.publicationTarget)
        setOrRemove(&pub, key: "base_url", string: fields.publicationBaseURL)
        setOrRemove(&pub, key: "origin", string: fields.publicationOrigin)
        setOrRemove(&pub, key: "base_path", string: fields.publicationBasePath)
        setOrRemove(&pub, key: "site_kind", string: fields.publicationSiteKind)
        setOrRemove(&pub, key: "did", string: fields.publicationDid)
        setOrRemove(&pub, key: "pds", string: fields.publicationPds)
        setOrRemove(&pub, key: "pds_origin", string: fields.publicationPdsOrigin)
        setOrRemove(&pub, key: "name", string: fields.publicationName)
        setOrRemove(&pub, key: "description", string: fields.publicationDescription)
        if let show = fields.publicationShowInDiscover {
            pub["show_in_discover"] = show
        } else {
            pub.removeValue(forKey: "show_in_discover")
        }
        if let prune = fields.publicationPrune {
            pub["prune"] = prune
        } else {
            pub.removeValue(forKey: "prune")
        }
        if !fields.publicationInclude.isEmpty {
            pub["include"] = fields.publicationInclude
        } else {
            pub.removeValue(forKey: "include")
        }
        if !fields.publicationExclude.isEmpty {
            pub["exclude"] = fields.publicationExclude
        } else {
            pub.removeValue(forKey: "exclude")
        }
        if pub.isEmpty {
            object.removeValue(forKey: "publication")
        } else {
            object["publication"] = pub
        }

        // Targets
        if !fields.targets.isEmpty {
            if let data = try? JSONEncoder().encode(fields.targets),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            {
                object["targets"] = arr
            }
        } else if object["targets"] != nil {
            object["targets"] = []
        }

        // Editions
        let hasEditions = fields.editions.ir != nil || fields.editions.rag != nil || fields.editions.context != nil
        if hasEditions {
            if let data = try? JSONEncoder().encode(fields.editions),
               let edObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               !edObj.isEmpty
            {
                object["editions"] = edObj
            }
        } else if object["editions"] != nil {
            object.removeValue(forKey: "editions")
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
