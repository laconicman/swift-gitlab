# GitLabKit

[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flaconicman%2Fswift-gitlab%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/laconicman/swift-gitlab)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flaconicman%2Fswift-gitlab%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/laconicman/swift-gitlab)
[![Latest tag](https://img.shields.io/github/v/tag/laconicman/swift-gitlab?label=release&sort=semver)](https://github.com/laconicman/swift-gitlab/tags)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache_2.0-blue.svg)](LICENSE.txt)

A modern, type-safe, async/await **GitLab REST API client** for Apple platforms, generated
from GitLab's official [OpenAPI spec](https://docs.gitlab.com/api/openapi/) with Apple's
[swift-openapi-generator](https://github.com/apple/swift-openapi-generator).

> Not affiliated with GitLab Inc. "GitLab" is a trademark of GitLab Inc.; this is an
> independent, community-maintained client.

## API coverage

The **entire** GitLab REST API is available — coverage is a build-time choice, not a
limitation. To keep compile times reasonable the package ships the **`review` tier** by
default; switch tiers by copying a template over
`Sources/GitLabOpenAPI/openapi-generator-config.yaml` and rebuilding:

| Tier | Operations | Config file |
|---|---|---|
| **`review`** (default) | ~218 | `openapi-generator-config.yaml` |
| `core` | ~494 | `openapi-generator-config.core.yaml` |
| `full` (whole API) | ~1,721 | `openapi-generator-config.full.yaml` |

The default `review` tier covers merge requests, approvals, notes, discussions, draft notes,
award emoji, commits, branches, and repository diffs.

## Install

```swift
.package(url: "https://github.com/laconicman/swift-gitlab.git", from: "0.1.0")
// target dependency:
.product(name: "GitLabKit", package: "GitLabKit")
```

Requires Swift 6, iOS 16 / macOS 13 (also tvOS 16 / watchOS 9).

## Usage

```swift
import GitLabKit
import GitLabOpenAPI

let client = try Client(token: "glpat-…")                          // gitlab.com
// let client = try Client(token: "…", hostname: "gitlab.example.com")  // self-managed
// let client = try Client(token: "…", bodyLoggingPolicy: .upTo(maxBytes: 2048))  // debug

// Add a review comment to a merge request:
let note = try await client.postApiV4ProjectsIdMergeRequestsNoteableIdNotes(
    .init(path: .init(id: "42", noteableId: 7), body: .json(.init(body: "LGTM 🚀")))
).created.body.json

// Handle documented statuses exhaustively:
let output = try await client.getApiV4ProjectsIdMergeRequestsMergeRequestIid(
    .init(path: .init(id: .case1("42"), mergeRequestIid: 7))
)
switch output {
case .ok(let ok):            print(try ok.body.json.title ?? "")
case .notFound:              print("no such MR")
case .undocumented(let s, _): print("status \(s)")
}
```

Authentication is a static bearer token (PAT or OAuth2 access token) via `HeaderMiddleware`;
logging uses [`OSLogLoggingMiddleware`](https://github.com/laconicman/OSLogLoggingMiddleware).

> **Response decoding.** GitLab's *published* spec under-types arrays — list endpoints and
> fields like `assignees`/`reviewers` are typed as single objects, which would break decoding.
> GitLabKit ships a **normalized spec** (`gitlab-spec-tool` retypes them), so list endpoints and
> array fields **decode correctly out of the box**. One residual class remains — scalar
> mismatches such as `milestone.group_id` (spec says `String`, the API returns a number) — and
> the opt-in `liveDecodeReviewEntities` test reports any it finds. See the **Tech Debt** doc and
> `Upstream/` for the fixes in flight.

## Layout

| Path | What |
|---|---|
| `Sources/GitLabOpenAPI/openapi.yaml` | Vendored, normalized GitLab spec (produced by `gitlab-spec-tool`) |
| `Sources/GitLabOpenAPI/openapi-generator-config*.yaml` | Active `review` tier + preserved `core`/`full` templates |
| `Sources/GitLabKit/` | Façade: `Client` factory, `HeaderMiddleware`, `GitLabDateTranscoder`, generated `Identifiable` |
| `Sources/gitlab-spec-tool/` | Maintainer tool: fetch + normalize + retype the spec, emit `Identifiable` |
| `Sources/GitLabKit/GitLabKit.docc/` | DocC: Design, Roadmap, Tech Debt, Upstream Spec Fix |
| `Upstream/` | Pasteable issue drafts + PR handoffs for the upstream spec fixes |

The generated client (`Client`/`Operations`/`Components`/`Servers`) is **built from the
vendored spec at build time** — run `swift build`; nothing generated is committed (except the
`Identifiable` conformances, which aren't something the generator can emit).

## Regenerate from a newer spec

```bash
swift run gitlab-spec-tool                 # fetch latest from master, normalize, retype arrays
swift run gitlab-spec-tool --ref v17.8.0   # pin to a tag / branch / commit sha
swift run gitlab-spec-tool --no-fetch      # normalize the already-vendored spec in place
swift build                              # regenerate the client
```

`gitlab-spec-tool` retypes GitLab's under-typed array fields/responses so real payloads decode,
and regenerates `Types+Identifiable.generated.swift`. Its transforms are **idempotent** —
harmless on an already-correct spec — so pinning `--ref` to an upstream fix lets the retyping
become a no-op. See the **Tech Debt** doc.

## Documentation

`swift package generate-documentation` (via swift-docc-plugin) or **Product ▸ Build
Documentation** in Xcode; also hosted on the Swift Package Index (see `.spi.yml`). Start with
the **Design**, **Roadmap**, **Tech Debt**, and **Upstream Spec Fix** articles.

## License

Apache 2.0 — see [`LICENSE.txt`](LICENSE.txt).
