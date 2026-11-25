# Roadmap

Planned work, in rough priority order.

## Harden response decoding

The array under-typing is mostly fixed upstream (see <doc:TechDebt> #1); the
`liveDecodeReviewEntities` auto-catch reports anything still off. Remaining work:
- ~~Extend `arrayFieldNames`~~ — emptied 2026-11; re-add names only if a refresh regresses.
- ~~Scalar-retype map~~ — done 2026-11: `scalarFieldTypes` in `gitlab-spec-tool`
  retypes curated `(schema, field) → type` pairs the API returns as
  integer/boolean but the spec types as string — `group_id` (milestone entities,
  live-verified), `access_level`/`notification_level` (member-access entities),
  `show_status`→boolean (`APIEntitiesUserPath`). Lookalikes verified as
  legitimately strings are excluded (`CiRunnerDetails`/`OrgUser.access_level`,
  `EpicBaseEntity.group_id`). Still open outside the review tier:
  `export_status` enum gaps (needs enum augmentation) and `show_status` on two
  unverified user entities — see <doc:TechDebt>.
  ([#604896](https://gitlab.com/gitlab-org/gitlab/-/issues/604896) has no MRs yet).

## Upstream spec fix (a series of PRs, in flight)

Retire the remaining local retyping at the source — see the <doc:UpstreamSpecFix> handoff
for the detailed plan. [#604895](https://gitlab.com/gitlab-org/gitlab/-/issues/604895) is
landing area by area (6 MRs merged, webhooks/geo possibly open as of 2026-11-25); each
merged area makes the corresponding local transform a no-op — the array-field list is
empty and **all** list responses are now correctly typed upstream, so
`arrayifyPaginatedResponses` reports 0 (it skips `containerResponsePaths` like
`personal_access_tokens/self/associations`, whose params paginate lists *inside*
the response object). [#604897](https://gitlab.com/gitlab-org/gitlab/-/issues/604897)
(`RequestBody_<hash>` names) is **closed** — grape-openapi 0.7.0 emits stable names, so the
vendored spec went from 422 anonymous schemas to 0. A third defect family —
`date` columns typed `format: date-time` — is mitigated locally by the transcoder's
date-only branch; upstream issue
[gitlab-org/gitlab#642830](https://gitlab.com/gitlab-org/gitlab/-/work_items/642830)
filed, handoff in `Upstream/date-vs-date-time.md`.

## OAuth2 with refresh

Today ``HeaderMiddleware`` carries a static token (PAT or a non-expiring OAuth access token).
For interactive OAuth where the access token expires, adopt
[`RefreshTokenAuthMiddleware`](https://github.com/laconicman/RefreshTokenAuthMiddleware) and
implement its `SignInAndRefresh` conformance against GitLab's `/oauth/token` endpoints (which
live outside the REST spec). The static middleware stays the default.

## Extract HeaderMiddleware to its own SPM

``HeaderMiddleware`` is currently inline. Promote it to a standalone package
(`laconicman/HeaderMiddleware`) alongside `OSLogLoggingMiddleware` and
`RefreshTokenAuthMiddleware`, then depend on it by remote tag — replacing the synthesized
copy. This finishes consolidating the author's middleware family.

## Widen API coverage

The active filter is review-focused (223 operations). Add tags to
`openapi-generator-config.yaml` — or swap in `openapi-generator-config.full.yaml` (1,865
operations: Projects, Groups, Users, Issues, Pipelines, …) — as more surface is needed.
Watch compile time (<doc:TechDebt> #4).

## Cross-platform logging

`OSLogLoggingMiddleware` is Darwin-only. For Linux/server use, swap in
[`LoggingMiddleware`](https://github.com/laconicman/LoggingMiddleware) (swift-log) under a
platform condition.

## Publish documentation

Wire up `swift-docc-plugin` output to a hosted site (or Swift Package Index) so this catalog
renders publicly.
