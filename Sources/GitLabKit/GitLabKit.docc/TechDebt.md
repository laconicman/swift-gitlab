# Tech Debt

Known compromises, workarounds, and upstream-spec limitations carried by GitLabKit. Each
entry names the cost and how to discharge it.

## 1. Arrays are under-typed as single objects (upstream)

**The big one.** GitLab's OpenAPI document is generated from Grape annotations that
inconsistently omit the "is array" flag, so things that are arrays at runtime are typed as a
single object. This shows up in **two** places:

- **List endpoints:** `GET` collections are typed as one entity, not a list — e.g.
  `getApiV4ProjectsIdMergeRequestsNoteableIdNotes` returns `APIEntitiesNote`, not
  `[APIEntitiesNote]` (same for discussions, commits, branches, …).
- **Nested entity fields:** array properties *inside* an entity are also mis-typed — on
  `APIEntitiesMergeRequest`, `assignees` and `reviewers` are typed `APIEntitiesUserBasic?`
  (a single user) but the API returns an array. (`labels` happens to be typed correctly, so
  it is field-by-field, not uniform.)

- **Impact (if unmitigated):** decoding a real response through `.ok.body.json` throws a
  `DecodingError` (`typeMismatch … found an array instead`) — confirmed live against
  gitlab.com (HTTP 200, request/auth/dates all fine, only strict decode fails). Because the
  bad fields are nested, *even single-object endpoints* can fail, not just lists.
- **Mitigation (implemented):** `swift run gitlab-spec-tool` retypes the affected fields
  (`assignees`, `reviewers`) and every paginated `GET` 200 response to `type: array` during
  vendoring — **11 fields + 239 responses** on the current spec. Real responses now decode
  (the live single-MR test passes cleanly). **Residual risk:** the field list
  (`arrayFieldNames`) is curated, so a newly-surfaced under-typed field needs adding there.
- **A second flavor — scalar mismatches.** The under-typing isn't only array-vs-object. The
  `liveDecodeReviewEntities` auto-catch found `milestone.group_id` typed `String` but returned
  as a *number*. The array retyper doesn't fix scalar mismatches; they're whack-a-mole to
  patch locally, so for now the auto-catch test **reports** them (recorded known issues) and
  the real fix is upstream. A targeted scalar-retype map in the tool is a possible future add.
- The fix at the source retires all of this — see <doc:UpstreamSpecFix>.

## 2. Spec normalization for idiomatic naming

`namingStrategy: idiomatic` collapses GitLab's dual `scope` enums — which accept both
`created-by-me` and `created_by_me` — to the same Swift case (`createdByMe`), producing
duplicate cases that fail to compile. The vendored `openapi.yaml` is normalized to drop the
redundant hyphenated variants (GitLab accepts the underscore forms).

- **Cost:** the vendored spec diverges from upstream, and the normalization must be
  re-applied on every spec refresh. (The vendored file is also Yams-reformatted by the tool —
  valid YAML, but not byte-identical to upstream.)
- **Discharge:** `swift run gitlab-spec-tool` re-fetches and re-applies it reproducibly (the
  enum-twin dedup is rule-based, not a hard-coded line edit). The alternative —
  `namingStrategy: defensive` — needs no patch but yields unusable method names
  (`get_sol_api_sol_v4_sol_projects…`).

## 3. Placeholder file in the generated target

`Sources/GitLabOpenAPI/Generated.swift` is an (almost) empty file. SwiftPM's *product*
emptiness check runs before the build plugin and rejects a target that has only
`openapi.yaml` + config, so one real source file is required for the target to be a valid
product.

- **Discharge:** none needed — it's a one-line, well-understood SwiftPM constraint.

## 4. Generated-module compile time

Even tightened to 218 operations, `Types.swift` is ~65k lines and takes ~76 s to compile
cold. It is isolated in the `GitLabOpenAPI` target, so it rebuilds only when the spec or
config changes and stays out of the incremental loop for façade/app code.

- **Discharge:** tighten the filter further, or pre-generate via the command plugin and
  commit the output if the build-time tradeoff flips.

## 5. Preserved broad config

`openapi-generator-config.full.yaml` is kept beside the active config but `exclude:`-d in
`Package.swift` so the plugin (which matches the exact filename `openapi-generator-config.yaml`)
never sees it. It can fall out of date relative to the active filter — treat it as a
reference snapshot, not a maintained alternate.

## 6. Client initializer shapes — reconsider

`init(token:hostname:)` forces `https://{hostname}` (the spec's server template), so HTTP-only
or non-standard-port hosts can't use it — which is why `init(token:serverURL:)` was added. The
URL-based init is the general form; revisit making it primary and demoting `hostname:` to a thin
convenience over it.

## 7. Some strange servers are generated from the ``openapi.yaml``
See `Servers` enum. Might be upstream issue.
