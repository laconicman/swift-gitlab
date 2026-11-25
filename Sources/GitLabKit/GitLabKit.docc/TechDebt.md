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

- **Upstream status (2026-11-25):** [gitlab-org/gitlab#604895](https://gitlab.com/gitlab-org/gitlab/-/issues/604895)
  is `workflow::in dev` and landing as a **series of area-by-area MRs** — merged so far:
  [!268447](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/268447) (core),
  [!268849](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/268849) (EE),
  [!270809](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/270809) (organizations),
  [!268850](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/268850) (source-code),
  [!270810](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/270810) (token-associations);
  webhooks/geo areas may still be open. The merged MRs cover the whole
  review surface: `assignees`/`reviewers`/`notes`/`suggestions` are `type: array` upstream,
  and `gitlab-spec-tool` now reports **`array fields retyped: 0`** spec-wide — the curated
  `arrayFieldNames` list has been emptied (kept as a mechanism for regressions and pinned old
  `--ref`s).
- **Residual:** none — `gitlab-spec-tool` now reports **`list responses
  retyped: 0`**. Every previously-broken list — `repository/tree`,
  `repository/contributors`, the four template lists (!268850) and
  `personal_access_tokens/self/associations` (!270810) — is `type: array`
  or correctly single-object upstream. The associations endpoint turned out
  to be a **container, not a list**: its `page`/`per_page` params paginate
  the `groups`/`projects` lists *inside* the `{groups, projects}` response
  object (verified against `lib/api/personal_access_tokens/self_information.rb`),
  so upstream's single-`$ref` was right all along — the transform had been
  array-wrapping it since the params looked paginated. `arrayifyPaginatedResponses`
  now skips paths in `containerResponsePaths`. Live decode against
  gitlab.com passes for the review entities.
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

## 8. Date-valued fields mistyped as `date-time` (upstream — mitigated)

A third spec-accuracy flavor, same family as #1: GitLab `date` columns serialize as
`YYYY-MM-DD`, but the spec — and the entity `documentation:` behind it — declares
`format: date-time`, so the generator types them `Date` and strict decoding fails
with `Expected an ISO-8601 date, received '2026-11-24'` (GitHub issue #5 —
`getApiV4User` against GitLab 19.5.3). Verified against `db/structure.sql` on
master, field by field:

- **Mistyped (response entities):** `last_activity_on` on
  `APIEntitiesUserPublic`/`APIEntitiesUserWithAdmin` (`users.last_activity_on` is
  `date`); `marked_for_deletion_at`/`marked_for_deletion_on` on the four project
  schemas (`projects.marked_for_deletion_at` is `date` — the `_at` name lies);
  `expires_at` on the six personal/resource/impersonation access-token entities
  (`personal_access_tokens.expires_at` is `date`).
- **Mistyped (request bodies):** member and invitation `expires_at` —
  `members.expires_at` is `date` and the descriptions already say
  "YEAR-MONTH-DAY".
- **Suspect, unverified:** the Epic/RelatedEpic date fields (EE; `epics` date
  columns suggest the same defect).
- **Checked and correct:** `enabled_until` (pages domains), the geo-status dates,
  `merge_after`, `released_at`, and `expires_at` on keys/deploy-tokens/secure-files/
  triggers — all backed by `timestamp` columns. Naming (`_at` vs `_on`) is not a
  reliable signal; the column type is.

- **Mitigation:** `GitLabDateTranscoder.decode` accepts a bare `YYYY-MM-DD` as
  start-of-day UTC — covers every mistyped field, enumerated or not, present and
  future. Retyping to `format: date` in the vendored spec was rejected: it
  generates `String?`, a worse API than `Date?` for a date value, and only fixes
  fields we enumerate — the spec demonstrably can't be trusted to label them.
- **Upstream:** filed as
  [gitlab-org/gitlab#642830](https://gitlab.com/gitlab-org/gitlab/-/work_items/642830);
  PR handoff in `Upstream/date-vs-date-time.md`.
  When upstream lands `type: 'Date'` corrections the fields become `String?`;
  the transcoder stays useful for anything they miss.

## 9. Full-tier spec has a path/parameter mismatch (upstream — pre-existing)

`GET /api/v4/jobs/{id}/sbom_scans/{sbom_digest}` declares path param
`sbom_scan_id` — the template says `{sbom_digest}`, the parameter list says
`sbom_scan_id` (and the operationId agrees with the parameter, so the path key
is the wrong half). `swift-openapi-generator` hard-fails on it
("Parameter 'sbom_digest' … not found in the defined list of path parameters"),
so the **full tier cannot currently generate** — present already in the v19.6
vendored spec, unrelated to the 2026-11-25 refresh. The `review` and `core`
tiers are unaffected (the path is outside their filters). Discharge: upstream
fixes the path/param pairing; until then the full-tier template is unusable.
