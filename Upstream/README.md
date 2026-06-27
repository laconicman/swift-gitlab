# Upstream notes

Drafts for fixing the root causes in `gitlab-org/gitlab` so GitLabKit's local workarounds can
be retired. Each note has a **pasteable issue draft** (GitLab-flavoured markdown) and a **PR
handoff** (implementation guide). The DocC `UpstreamSpecFix` article is the in-repo overview;
these files are the actionable artifacts.

| Note | Problem | Local mitigation today | Status |
|---|---|---|---|
| [array-and-scalar-under-typing](array-and-scalar-under-typing.md) | Lists & plural fields typed as single objects; some scalars mistyped (`group_id`) | `gitlab-spec-tool` array retyping; auto-catch reports scalars | draft |
| [anonymous-request-bodies](anonymous-request-bodies.md) | 422 inline request bodies hoisted to hash-named `RequestBody_<hash>` schemas | none (skipped by the `Identifiable` generator) | draft |

All three are **spec-accuracy defects — the API is correct**, so each is fixable with a
documentation-only change (no API behaviour change). The under-typing spans much of the API, so
expect a **series of PRs** rather than one.
