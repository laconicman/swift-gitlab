# Tech Debt

Known compromises, workarounds, and upstream-spec limitations carried by GitLabKit. Each
entry names the cost and how to discharge it.

## 1. Arrays were under-typed as single objects (upstream — mostly fixed)

**The big one, now mostly discharged upstream.** GitLab's OpenAPI document was generated from
Grape annotations that inconsistently omitted the "is array" flag, so things that are arrays
at runtime were typed as a single object — in **two** places:

- **List endpoints:** `GET` collections typed as one entity, not a list.
- **Nested entity fields:** array properties *inside* an entity mis-typed — on
  `APIEntitiesMergeRequest`, `assignees` and `reviewers` were typed `APIEntitiesUserBasic?`
  (a single user) while the API returns an array.

- **Upstream status (2026-11-18):** [gitlab-org/gitlab#604895](https://gitlab.com/gitlab-org/gitlab/-/issues/604895)
  is `workflow::in dev` and landing as a **series of area-by-area MRs** — merged so far:
  [!268447](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/268447) (core),
  [!268849](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/268849) (EE),
  [!270809](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/270809) (organizations);
  open: source-code, token-associations, webhooks, geo areas. The merged MRs cover the whole
  review surface: `assignees`/`reviewers`/`notes`/`suggestions` are `type: array` upstream,
  and `gitlab-spec-tool` now reports **`array fields retyped: 0`** spec-wide — the curated
  `arrayFieldNames` list has been emptied (kept as a mechanism for regressions and pinned old
  `--ref`s).
- **Residual:** **7 paginated GETs still return single-object 200s** — the transform still
  retypes them, and every one has an MR in flight: `repository/tree` +
  `repository/contributors` + the four template lists are covered by the open
  source-code MR (!268850), and `personal_access_tokens/self/associations` by the open
  token-associations MR (!270810). Two of the seven sit inside the review tier; the rest
  only matter for `core`/`full`. Live decode against gitlab.com passes for the review
  entities.
- **A second flavor — scalar mismatches.** Still unfixed upstream:
  [#604896](https://gitlab.com/gitlab-org/gitlab/-/issues/604896) has no MRs yet.
  Locally mitigated by the curated `scalarFieldTypes` map in `gitlab-spec-tool`
  (schema-scoped `(schema, field) → type` retypes, each verified against GitLab's
  entity sources): `coverage`→string ×7 via `stringFieldNames`, and
  `group_id`→integer (`APIEntitiesMilestone`, `APIEntitiesMilestoneWithStats` —
  live-verified on gitlab.com MR data), `access_level`/`notification_level`→integer
  (member-access entities), `show_status`→boolean (`APIEntitiesUserPath`,
  review-reachable via context commits). Deliberately excluded lookalikes that are
  legitimately strings: `APIEntitiesCiRunnerDetails.access_level`
  (`"not_protected"`/`"ref_protected"`) and
  `APIEntitiesOrganizationsOrganizationUser.access_level` (`"owner"`), plus
  `EpicBaseEntity.group_id` (all-string ids look intentional for EE epics).
  Still open, all outside the review tier: `APIEntitiesProjectExportStatus.
  export_status` documents a closed enum missing the runtime values `none` and
  `regeneration_in_progress` (needs an enum-augmentation transform, not a retype),
  and `show_status` on `UserEntity` /
  `VulnerabilitiesMergeRequestLinkEntityAuthorEntity` (same boolean runtime,
  entity lineage unverified).
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

Even tightened to 223 operations, `Types.swift` is ~75k lines and takes ~100 s to compile
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
