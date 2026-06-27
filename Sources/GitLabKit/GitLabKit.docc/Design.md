# Design

Why GitLabKit is generated, how it is structured, and the decisions behind it.

## Generate, don't adopt

The only dedicated Swift GitLab client (`malcommac/GitLabSwift`) is hand-written, covers
~20 resources, and has been unmaintained since March 2023 — it does not track the spec.
GitLab's OpenAPI document, by contrast, is now large and clean: OpenAPI 3.0.0, ~1,721
operations, 2,532 schemas, **all operationIds unique**, with a `https://{hostname}` server
template and `http` bearer + `oauth2` security. That makes generation the right call: a
typed, `Sendable`, async/await client that regenerates whenever GitLab updates the spec.

We use Apple's [swift-openapi-generator](https://github.com/apple/swift-openapi-generator)
with its **build plugin** — the client is generated at build time and never committed, so it
cannot drift from the vendored spec.

## Module layout

Two targets, deliberately split (the skill recommends isolating generated code so it
rebuilds only when the spec changes, and so SourceKit can see the symbols):

- **`GitLabOpenAPI`** — generated `Client` / `Operations` / `Components` / `Servers`.
  Holds only `openapi.yaml` + `openapi-generator-config.yaml` (+ a placeholder `Generated.swift`;
  see <doc:TechDebt>). `accessModifier: public`.
- **`GitLabKit`** — the façade: `Client.init(token:hostname:bodyLoggingPolicy:)`,
  ``HeaderMiddleware``, and ``GitLabDateTranscoder``.

## Scope via `filter:`

The full spec generates a ~157k-line `Types.swift` (~2.5-min compile), because the broad
resource tags pull in most of the 2,532 schemas. The **active** config
(`openapi-generator-config.yaml`) is therefore tightened to the review surface — merge
requests, approvals, notes, discussions, draft notes, award emoji, commits, branches,
repository diffs — yielding **218 operations** and a 65k-line `Types.swift` (~76-s compile).

Two broader tiers are preserved beside it (excluded from the build): **core** (494 ops —
review + project/group/user/issue/CI management) and **full** (~1,721 ops — the whole API,
no filter). Switch tiers by copying a template over `openapi-generator-config.yaml`.

## The spec tool

`gitlab-spec-tool` (`swift run gitlab-spec-tool`) is the maintainer pipeline that (re)vendors the
spec — fetch (`--ref` to pin a tag/branch/sha) → normalize → write — replacing an earlier bash
script so the toolchain is all Swift. It parses the YAML with Yams and applies three transforms:
drop colliding enum twins, and retype the under-typed arrays (entity fields + paginated list
responses) so real responses decode. The transforms are **idempotent** (guarded, so a correct
spec passes through unchanged). See <doc:TechDebt>.

It also **generates `Types+Identifiable.generated.swift`** — swift-openapi-generator can't emit
protocol conformances, so the tool conforms every *filtered* entity that has an `id` to
`Identifiable` (computing the filter's schema closure so it only names types that exist). This
is more robust than hand-picking entities, and GitLab's consistent `id` makes it unambiguous.

## Naming

`namingStrategy: idiomatic` gives clean Swift names (`getApiV4ProjectsIdMergeRequests…`)
rather than the verbose `defensive` mangling. It collides on exactly one GitLab pattern —
the dual `scope` enums — which the spec tool resolves by normalizing the spec (see
<doc:TechDebt>).

## Authentication & configuration

Auth is **not** generated. ``HeaderMiddleware`` injects `Authorization: Bearer <token>`,
which covers both a Personal/Project/Group Access Token and an OAuth2 access token and
matches the spec's `http` bearer scheme. It is synthesized from the author's existing
header-injection middlewares (`YooMoneyAPIClient`, `YandexDeliveryExpress`,
`SwiftOpenAPIGenMiddlewares`), minus per-API cruft.

Logging reuses the published [`OSLogLoggingMiddleware`](https://github.com/laconicman/OSLogLoggingMiddleware).
``GitLabDateTranscoder`` accepts GitLab's mixed fractional / non-fractional ISO-8601
timestamps, which the runtime's stock transcoders reject. The `{hostname}` server template
means self-managed instances work via `Client(token:hostname:)`.
