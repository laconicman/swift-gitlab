# Roadmap

Planned work, in rough priority order.

## Harden response decoding

The array under-typing is mitigated by `gitlab-spec-tool` (see <doc:TechDebt> #1); the
`liveDecodeReviewEntities` auto-catch reports anything still off. Remaining work:
- Extend `arrayFieldNames` as new array under-typing surfaces.
- **Scalar-retype map (undecided).** The auto-catch found scalar mismatches too
  (`milestone.group_id` typed `String` but returned as a number). A small curated
  `(schema, field) → type` map in the tool could fix these the way `arrayFieldNames` fixes
  arrays — but it risks whack-a-mole. **Not yet decided**: do it locally, or rely on the
  upstream fix below.

## Upstream spec fix (likely a series of PRs)

Retire the local retyping at the source — see the <doc:UpstreamSpecFix> handoff for the
detailed plan. This is **not one PR**: the under-typing spans much of the API surface, so
expect a sequence — a targeted PR for the review entities first, then either a systemic
Grape→OpenAPI generation fix or further per-area PRs. Each fixed area makes the corresponding
local transform a no-op (pin `--ref` to validate).

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

The active filter is review-focused (218 operations). Add tags to
`openapi-generator-config.yaml` — or swap in `openapi-generator-config.full.yaml` (494
operations: Projects, Groups, Users, Issues, Pipelines, …) — as more surface is needed.
Watch compile time (<doc:TechDebt> #4).

## Cross-platform logging

`OSLogLoggingMiddleware` is Darwin-only. For Linux/server use, swap in
[`LoggingMiddleware`](https://github.com/laconicman/LoggingMiddleware) (swift-log) under a
platform condition.

## Publish documentation

Wire up `swift-docc-plugin` output to a hosted site (or Swift Package Index) so this catalog
renders publicly.
