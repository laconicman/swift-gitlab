import Foundation
import Yams
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Maintainer tool that (re)vendors GitLab's OpenAPI document for GitLabKit:
/// fetches the latest spec, then applies the normalizations that make it usable with
/// `swift-openapi-generator` + `namingStrategy: idiomatic`. Replaces the old bash script
/// so the whole toolchain is Swift and cross-platform.
///
///   swift run gitlab-spec-tool                  # fetch latest from master, normalize, write
///   swift run gitlab-spec-tool --ref v17.8.0    # fetch from a tag / branch / commit sha
///   swift run gitlab-spec-tool --no-fetch       # normalize the already-vendored spec in place
///
/// Transforms (see the DocC "Tech Debt" article for the why):
///  1. Enum twins   — drop hyphenated enum values that collide with an underscore twin
///                    (`created-by-me` vs `created_by_me`), which idiomatic naming merges.
///  2. Array fields — retype entity properties the API returns as arrays but the spec types
///                    as a single object (`assignees`, `reviewers`).
///  3. List bodies  — retype paginated GET 200 responses (those with a `page`/`per_page`
///                    query param) from a single entity to an array of that entity.
///
/// All three are **idempotent and harmless on a correctly-typed spec**: each is guarded
/// (`isSingleRef`, or "twin exists"), so an already-array field/response or an already-deduped
/// enum passes through unchanged. If GitLab fixes the spec upstream, this tool becomes a
/// no-op retyping-wise — pin `--ref` to that fixed revision and the retyping simply finds
/// nothing to do. (Verify with `--no-fetch`: a second run reports `0 / 0 / 0`.)
@main
struct GitLabSpecTool {
    static let specBaseURL = "https://gitlab.com/gitlab-org/gitlab/-/raw"
    static let specPath = "doc/api/openapi/openapi_v3.yaml"
    static let defaultOutput = "Sources/GitLabOpenAPI/openapi.yaml"
    static let identifiableOutput = "Sources/GitLabKit/Types+Identifiable.generated.swift"

    /// Entity properties that are arrays at runtime but under-typed as a single `$ref`.
    static let arrayFieldNames: Set<String> = ["assignees", "reviewers"]

    struct Stats { var enumTwins = 0; var fields = 0; var responses = 0 }

    static func main() async throws {
        // Hand-rolled parsing (keeps the tool dependency-light): `--no-fetch`, `--ref <value>`,
        // and an optional positional output path.
        var fetch = true
        var ref = "master"
        var output = defaultOutput
        var iterator = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--no-fetch": fetch = false
            case "--ref": if let value = iterator.next() { ref = value }
            default: if !arg.hasPrefix("--") { output = arg }
            }
        }

        let rawYAML: String
        if fetch {
            let specURL = URL(string: "\(specBaseURL)/\(ref)/\(specPath)")!
            FileHandle.standardError.write(Data("Fetching \(specURL.absoluteString)\n".utf8))
            let (data, _) = try await URLSession.shared.data(from: specURL)
            rawYAML = String(decoding: data, as: UTF8.self)
        } else {
            rawYAML = try String(contentsOfFile: output, encoding: .utf8)
        }

        guard var root = try Yams.compose(yaml: rawYAML) else {
            throw ToolError.couldNotParse
        }

        var stats = Stats()
        root = normalizeNode(root, stats: &stats)            // transforms 1 & 2
        root = arrayifyPaginatedResponses(root, stats: &stats) // transform 3

        let serialized = try Yams.serialize(node: root, allowUnicode: true)
        try serialized.write(toFile: output, atomically: true, encoding: .utf8)

        // swift-openapi-generator can't emit protocol conformances, so we generate
        // `Identifiable` for every filtered entity that has an `id` — robust and complete
        // versus hand-picking. GitLab's `id` convention makes this unambiguous.
        let configPath = (output as NSString).deletingLastPathComponent + "/openapi-generator-config.yaml"
        let conformances = try emitIdentifiable(root: root, configPath: configPath)

        let summary = """
        Wrote \(output)
          enum twins removed:     \(stats.enumTwins)
          array fields retyped:   \(stats.fields)
          list responses retyped: \(stats.responses)
        Wrote \(identifiableOutput)
          Identifiable conformances: \(conformances)
        """
        print(summary)
    }

    // MARK: Generate Identifiable conformances

    /// Emits `extension Components.Schemas.X: Identifiable {}` for every schema that (a) is in
    /// the active filter's generated set, (b) has a clean Swift-identifier name (skips the
    /// anonymous `RequestBody_*` schemas idiomatic naming would rename), and (c) has a
    /// top-level `id` property. Returns the count.
    @discardableResult
    static func emitIdentifiable(root: Node, configPath: String) throws -> Int {
        guard case .mapping(let rootMap) = root,
              case .mapping(let components)? = rootMap["components"],
              case .mapping(let schemas)? = components["schemas"]
        else { return 0 }

        let kept = generatedSchemaNames(rootMap: rootMap, schemas: schemas, configPath: configPath)

        let conformable = kept.filter { name in
            guard isCleanTypeName(name),
                  let schema = schemas[name], case .mapping(let m) = schema,
                  case .mapping(let props)? = m["properties"], props["id"] != nil
            else { return false }
            return true
        }.sorted()

        var out = """
        // Generated by gitlab-spec-tool — do not edit.
        // Conforms every filtered entity that has an `id` to Identifiable, so the review
        // entities drop into SwiftUI `ForEach`/`List`. The `id` is optional only because
        // GitLab marks few response fields required; real payloads always carry it.

        import GitLabOpenAPI


        """
        out += conformable.map { "extension Components.Schemas.\($0): Identifiable {}" }.joined(separator: "\n")
        out += "\n"
        try out.write(toFile: identifiableOutput, atomically: true, encoding: .utf8)
        return conformable.count
    }

    /// The set of schema names the generator will emit for the active config: every schema
    /// transitively `$ref`-reachable from an operation whose tag is in `filter.tags`. With no
    /// filter (the `full` tier) that's every schema.
    static func generatedSchemaNames(rootMap: Node.Mapping, schemas: Node.Mapping, configPath: String) -> Set<String> {
        let tags: Set<String>?
        if let yaml = try? String(contentsOfFile: configPath, encoding: .utf8),
           let config = try? Yams.compose(yaml: yaml),
           case .sequence(let tagSeq)? = config["filter"]?["tags"] {
            tags = Set(tagSeq.compactMap { $0.string })
        } else {
            tags = nil
        }

        guard let tags else { return Set(schemas.keys.compactMap { $0.string }) }

        var kept = Set<String>()
        if case .mapping(let paths)? = rootMap["paths"] {
            for (_, pathItem) in paths {
                guard case .mapping(let item) = pathItem else { continue }
                for (_, op) in item {
                    guard case .mapping(let opMap) = op,
                          case .sequence(let opTags)? = opMap["tags"],
                          opTags.contains(where: { tags.contains($0.string ?? "") })
                    else { continue }
                    collectSchemaRefs(op, into: &kept)
                }
            }
        }
        // Transitive closure through the kept schemas' own `$ref`s.
        var frontier = kept
        while !frontier.isEmpty {
            var next = Set<String>()
            for name in frontier {
                guard let schema = schemas[name] else { continue }
                var refs = Set<String>()
                collectSchemaRefs(schema, into: &refs)
                for ref in refs where !kept.contains(ref) { kept.insert(ref); next.insert(ref) }
            }
            frontier = next
        }
        return kept
    }

    /// Collects every `#/components/schemas/X` reference reachable in `node` as the bare `X`.
    static func collectSchemaRefs(_ node: Node, into refs: inout Set<String>) {
        switch node {
        case .scalar, .alias:
            return
        case .sequence(let seq):
            for item in seq { collectSchemaRefs(item, into: &refs) }
        case .mapping(let map):
            let prefix = "#/components/schemas/"
            for (key, value) in map {
                if key.string == "$ref", let ref = value.string, ref.hasPrefix(prefix) {
                    refs.insert(String(ref.dropFirst(prefix.count)))
                } else {
                    collectSchemaRefs(value, into: &refs)
                }
            }
        }
    }

    static func isCleanTypeName(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber }
    }

    // MARK: Transforms 1 & 2 — one recursive pass

    static func normalizeNode(_ node: Node, stats: inout Stats) -> Node {
        switch node {
        case .scalar, .alias:
            return node
        case .sequence(var seq):
            for i in seq.indices { seq[i] = normalizeNode(seq[i], stats: &stats) }
            return .sequence(seq)
        case .mapping(var map):
            for key in Array(map.keys) {
                guard let value = map[key] else { continue }
                var newValue = normalizeNode(value, stats: &stats)
                switch key.string {
                case "enum":
                    if case .sequence(let seq) = newValue {
                        let (deduped, removed) = dedupedEnumTwins(seq)
                        if removed > 0 { newValue = .sequence(deduped); stats.enumTwins += removed }
                    }
                case let k? where arrayFieldNames.contains(k):
                    if isSingleRef(newValue) { newValue = arrayOf(newValue); stats.fields += 1 }
                default:
                    break
                }
                map[key] = newValue
            }
            return .mapping(map)
        }
    }

    // MARK: Transform 3 — paginated list responses

    static func arrayifyPaginatedResponses(_ root: Node, stats: inout Stats) -> Node {
        guard case .mapping(var rootMap) = root,
              let pathsNode = rootMap["paths"], case .mapping(var paths) = pathsNode
        else { return root }

        for pathKey in Array(paths.keys) {
            guard case .mapping(var pathItem)? = paths[pathKey] else { continue }
            for method in Array(pathItem.keys) {
                guard method.string == "get",
                      case .mapping(var op)? = pathItem[method],
                      hasPaginationParam(op["parameters"]),
                      let wrapped = wrappingJSONResponseSchema(in: op["responses"])
                else { continue }
                op["responses"] = wrapped
                pathItem[method] = .mapping(op)
                stats.responses += 1
            }
            paths[pathKey] = .mapping(pathItem)
        }
        rootMap["paths"] = .mapping(paths)
        return .mapping(rootMap)
    }

    /// Returns a rewritten `responses` node whose `200` JSON schema is wrapped in an array,
    /// or `nil` if there is nothing single-`$ref` to wrap.
    static func wrappingJSONResponseSchema(in responses: Node?) -> Node? {
        guard case .mapping(var responses)? = responses,
              // "200" resolves to an int-tagged scalar via string subscript, which won't
              // match the string-tagged key from `'200':` — match by string value instead.
              let okKey = responses.keys.first(where: { $0.string == "200" }),
              case .mapping(var ok)? = responses[okKey],
              case .mapping(var content)? = ok["content"],
              case .mapping(var json)? = content["application/json"],
              let schema = json["schema"], isSingleRef(schema)
        else { return nil }
        json["schema"] = arrayOf(schema)
        content["application/json"] = .mapping(json)
        ok["content"] = .mapping(content)
        responses[okKey] = .mapping(ok)
        return .mapping(responses)
    }

    // MARK: Helpers

    static func hasPaginationParam(_ parameters: Node?) -> Bool {
        guard case .sequence(let seq)? = parameters else { return false }
        return seq.contains { param in
            guard case .mapping(let m) = param, let name = m["name"]?.string else { return false }
            return (name == "page" || name == "per_page") && m["in"]?.string == "query"
        }
    }

    static func isSingleRef(_ node: Node) -> Bool {
        guard case .mapping(let m) = node else { return false }
        return m.count == 1 && m["$ref"] != nil
    }

    static func arrayOf(_ ref: Node) -> Node {
        ["type": "array", "items": ref]
    }

    static func dedupedEnumTwins(_ seq: Node.Sequence) -> (Node.Sequence, Int) {
        let present = Set(seq.compactMap { $0.string })
        var kept: [Node] = []
        var removed = 0
        for item in seq {
            if let s = item.string, s.contains("-"),
               present.contains(s.replacingOccurrences(of: "-", with: "_")) {
                removed += 1
            } else {
                kept.append(item)
            }
        }
        return (Node.Sequence(kept), removed)
    }
}

enum ToolError: Error { case couldNotParse }
