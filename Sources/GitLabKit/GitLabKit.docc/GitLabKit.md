# ``GitLabKit``

A modern, type-safe, async/await GitLab REST API client for Apple platforms, generated
from GitLab's official OpenAPI specification with Apple's swift-openapi-generator.

## Overview

`GitLabKit` wraps a generated client (the `GitLabOpenAPI` module) with a thin façade: a
one-line authenticated `Client` factory, a static bearer-token middleware, and a lenient
date transcoder for GitLab's timestamps. Every endpoint is a typed method; every documented
response status is an exhaustive `switch` case.

```swift
import GitLabKit
import GitLabOpenAPI

let client = try Client(token: "glpat-…")                 // gitlab.com
// let client = try Client(token: "…", hostname: "gitlab.example.com")  // self-managed

// Add a review comment to a merge request (single-object response — decodes cleanly):
let created = try await client.postApiV4ProjectsIdMergeRequestsNoteableIdNotes(
    .init(path: .init(id: "42", noteableId: 7), body: .json(.init(body: "Looks good to me 🚀")))
).created.body.json
```

The client is scoped (via the generator's `filter:`) to **code review + minimal repository
context**: merge requests, approvals, notes, discussions, draft notes, award emoji, commits,
branches, and repository diffs.

## Topics

### Architecture & Decisions
- <doc:Design>
- <doc:Roadmap>
- <doc:TechDebt>
- <doc:UpstreamSpecFix>

### Authentication
- ``HeaderMiddleware``
- ``GitLabDateTranscoder``
