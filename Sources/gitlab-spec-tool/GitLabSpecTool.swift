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
///                    as a single object. Currently a no-op: `arrayFieldNames` is empty
///                    because upstream fixed every curated field (#604895).
///  3. List bodies  — retype paginated GET 200 responses (those with a `page`/`per_page`
///                    query param) from a single entity to an array of that entity.
///  4. String fields — retype entity properties the API returns as strings but the spec
///                    types as numbers (`coverage` arrives as "98.29", not 98.29).
///  5. Scalar fields — retype curated entity properties the API returns as integers
///                    or booleans but the spec types as strings (`milestone.group_id`
///                    arrives as a number, `author.show_status` as true/false — both
///                    documented `string` because the upstream `expose` lacks a
///                    `documentation: { type: }`).
///
/// All five are **idempotent and harmless on a correctly-typed spec**: each is guarded
/// (`isSingleRef`, "twin exists", `isFloatTyped`, `isStringTyped`), so an
/// already-array field/response, an already-string/integer field, or an
/// already-deduped enum passes through unchanged. If GitLab fixes
/// the spec upstream, this tool becomes a no-op retyping-wise — pin `--ref` to that fixed
/// revision and the retyping simply finds nothing to do. (Verify with `--no-fetch`: a second
/// run reports `0 / 0 / 0 / 0 / 0`.)
@main
struct GitLabSpecTool {
    static let specBaseURL = "https://gitlab.com/gitlab-org/gitlab/-/raw"
    static let specPath = "doc/api/openapi/openapi_v3.yaml"
    static let defaultOutput = "Sources/GitLabOpenAPI/openapi.yaml"
    static let identifiableOutput = "Sources/GitLabKit/Types+Identifiable.generated.swift"

    /// Entity properties that are arrays at runtime but under-typed as a single `$ref`.
    /// Empty since the 2026-11 spec refresh: upstream now types every curated field
    /// (`assignees`, `reviewers`, `notes`, `suggestions`) as `type: array` — the fix for
    /// gitlab-org/gitlab#604895 landed in !268447, !268849 and !270809 — and a spec-wide
    /// check reports `array fields retyped: 0`. Re-add names here only if a refresh
    /// regresses or a pinned old `--ref` needs them; see the DocC "Tech Debt" article.
    static let arrayFieldNames: Set<String> = []

    /// Entity properties that are strings at runtime but the spec types `number`/`float`.
    /// `coverage` was surfaced by the MR read: `head_pipeline.coverage` arrives as "98.29".
    /// The request-side `coverage` field (update-a-job) is typed `number` WITHOUT
    /// `format: float` and legitimately accepts a number, so the guard is both keys.
    static let stringFieldNames: Set<String> = ["coverage"]

    /// `(schema, property) → runtime type` retypes for fields the API returns as
    /// integers/booleans but the spec types `string` — gitlab-org/gitlab#604896.
    /// Scoped by schema name inside `components/schemas`, so request bodies and
    /// unrelated same-named fields are untouched. Every entry was verified against
    /// GitLab's entity sources (`lib/api/entities/**`, `app/models/project.rb`,
    /// `app/serializers/concerns/user_status_tooltip.rb`). Deliberately excluded
    /// lookalikes that are legitimately strings: `APIEntitiesCiRunnerDetails.
    /// access_level` (`"not_protected"`/`"ref_protected"` enum) and
    /// `APIEntitiesOrganizationsOrganizationUser.access_level` (`"owner"` etc.),
    /// plus `EpicBaseEntity.group_id` — that entity types `id`/`iid`/`group_id` all
    /// as strings, which looks intentional for EE epic references.
    enum ScalarKind { case integer, boolean }

    static let scalarFieldTypes: [String: [String: ScalarKind]] = [
        // `milestone.group_id` — caught by the live MR-list decode ("Expected to
        // decode String but found number"); WithStats is the same milestone shape
        // surfaced through releases.
        "APIEntitiesMilestone": ["group_id": .integer],
        "APIEntitiesMilestoneWithStats": ["group_id": .integer],
        // MemberAccess exposes `access_level`/`notification_level` untyped → the
        // spec defaults them to string; runtime is `Gitlab::Access` /
        // `NotificationSetting.levels` integers. Member/Membership/Invitation
        // expose the same member `access_level` integer.
        "APIEntitiesProjectAccess": ["access_level": .integer, "notification_level": .integer],
        "APIEntitiesGroupAccess": ["access_level": .integer, "notification_level": .integer],
        "APIEntitiesMember": ["access_level": .integer],
        "APIEntitiesMembership": ["access_level": .integer],
        "APIEntitiesInvitation": ["access_level": .integer],
        // `show_status` comes from the UserStatusTooltip concern
        // (`status_loaded? && !!user.status&.customized?`) — boolean at runtime,
        // untyped expose → string. Review-reachable via context commits.
        "APIEntitiesUserPath": ["show_status": .boolean],
    ]

    struct Stats { var enumTwins = 0; var fields = 0; var responses = 0; var stringFields = 0; var scalarFields = 0 }

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
        root = normalizeNode(root, stats: &stats)            // transforms 1, 2 & 4
        root = arrayifyPaginatedResponses(root, stats: &stats) // transform 3
        root = retypeScalarFields(root, stats: &stats)      // transform 5

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
          string fields retyped:  \(stats.stringFields)
          scalar fields retyped:  \(stats.scalarFields)
        Wrote \(identifiableOutput)
          Identifiable conformances: \(conformances)
        """
        print(summary)
    }

    // MARK: Generate Identifiable conformances

    /// Emits `extension Components.Schemas.X: Identifiable {}` for every schema that (a) is in
    /// the active filter's generated set, (b) has a clean Swift-identifier name (skips any
    /// schema whose name wouldn't survive idiomatic naming), and (c) has a top-level `id`
    /// property. Returns the count.
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
                case let k? where stringFieldNames.contains(k):
                    if isFloatTyped(newValue) { newValue = stringTyped(newValue); stats.stringFields += 1 }
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

    // MARK: Transform 5 — curated string→scalar retypes

    /// Retypes the `(schema, property) → type` pairs in `scalarFieldTypes` from
    /// `type: string` to the mapped scalar type, inside `components/schemas` only —
    /// request bodies and unrelated same-named fields are untouched. Guarded by
    /// `isStringTyped`, so an upstream-fixed field (already the right type) or one
    /// legitimately typed `string` passes through unchanged.
    static func retypeScalarFields(_ root: Node, stats: inout Stats) -> Node {
        guard case .mapping(var rootMap) = root,
              case .mapping(var components)? = rootMap["components"],
              case .mapping(var schemas)? = components["schemas"]
        else { return root }

        for (schemaName, fields) in scalarFieldTypes {
            guard case .mapping(var schema)? = schemas[schemaName],
                  case .mapping(var properties)? = schema["properties"]
            else { continue }
            for key in Array(properties.keys) {
                guard let field = key.string,
                      let kind = fields[field],
                      let property = properties[key], isStringTyped(property)
                else { continue }
                properties[key] = scalarTyped(property, as: kind)
                stats.scalarFields += 1
            }
            schema["properties"] = .mapping(properties)
            schemas[schemaName] = .mapping(schema)
        }
        components["schemas"] = .mapping(schemas)
        rootMap["components"] = .mapping(components)
        return .mapping(rootMap)
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

    /// `type: number` AND `format: float` — the shape GitLab mistypes for string-valued
    /// fields. A plain `number` (request-side coverage) passes through untouched.
    static func isFloatTyped(_ node: Node) -> Bool {
        guard case .mapping(let m) = node else { return false }
        return m["type"]?.string == "number" && m["format"]?.string == "float"
    }

    /// `type: number, format: float` → `type: string`; a numeric `example` becomes a
    /// string scalar so it stays valid for the new type.
    static func stringTyped(_ node: Node) -> Node {
        guard case .mapping(var m) = node else { return node }
        m["type"] = "string"
        m["format"] = nil   // assigning nil removes the key in Yams' Mapping
        if let example = m["example"]?.string, Double(example) != nil {
            // A plain "98.29" scalar would re-read as a number under type: string —
            // force a quoted style so the example stays honest.
            m["example"] = .scalar(.init(example, Tag(.str), .singleQuoted))
        }
        return .mapping(m)
    }

    /// `type: string` on a plain (non-`$ref`) schema node — the shape GitLab mistypes
    /// for integer-valued fields like `group_id`.
    static func isStringTyped(_ node: Node) -> Bool {
        guard case .mapping(let m) = node else { return false }
        return m["type"]?.string == "string" && m["$ref"] == nil
    }

    /// `type: string` → the mapped scalar type; drops `format`, which can't carry over.
    static func scalarTyped(_ node: Node, as kind: ScalarKind) -> Node {
        guard case .mapping(var m) = node else { return node }
        switch kind {
        case .integer: m["type"] = "integer"
        case .boolean: m["type"] = "boolean"
        }
        m["format"] = nil   // assigning nil removes the key in Yams' Mapping
        return .mapping(m)
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
