# Upstream notes

Drafts for fixing the root causes in `gitlab-org/gitlab` so GitLabKit's local workarounds can
be retired. Each note has a **pasteable issue draft** (GitLab-flavoured markdown) and a **PR
handoff** (implementation guide). The DocC `UpstreamSpecFix` article is the in-repo overview;
these files are the actionable artifacts.

| Note | Problem | Local mitigation today | Status |
|---|---|---|---|
| [array-and-scalar-under-typing](array-and-scalar-under-typing.md) | Lists & plural fields typed as single objects; some scalars mistyped (`group_id`) | array retyping nearly retired — `arrayFieldNames` emptied, 7 list responses left; `coverage`→string; `group_id` still a known issue | [#604895](https://gitlab.com/gitlab-org/gitlab/-/issues/604895) **in dev** — !268447/!268849/!270809 merged (review surface covered), source-code/token-auth/webhooks/geo MRs open; [#604896](https://gitlab.com/gitlab-org/gitlab/-/issues/604896) (scalars) filed, no MRs |
| [anonymous-request-bodies](anonymous-request-bodies.md) | 422 inline request bodies hoisted to hash-named `RequestBody_<hash>` schemas | none needed — fixed upstream | [#604897](https://gitlab.com/gitlab-org/gitlab/-/issues/604897) **closed** — grape-openapi 0.7.0 emits stable names; spec now has 0 `RequestBody_*` schemas |

All three are **spec-accuracy defects — the API is correct**, so each is fixable with a
documentation-only change (no API behaviour change). The under-typing spans much of the API, so
expect a **series of PRs** rather than one.
