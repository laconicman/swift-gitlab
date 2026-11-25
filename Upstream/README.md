# Upstream notes

Drafts for fixing the root causes in `gitlab-org/gitlab` so GitLabKit's local workarounds can
be retired. Each note has a **pasteable issue draft** (GitLab-flavoured markdown) and a **PR
handoff** (implementation guide). The DocC `UpstreamSpecFix` article is the in-repo overview;
these files are the actionable artifacts.

| Note | Problem | Local mitigation today | Status |
|---|---|---|---|
| [array-and-scalar-under-typing](array-and-scalar-under-typing.md) | Lists & plural fields typed as single objects; some scalars mistyped (`group_id`) | array retyping fully retired — `arrayFieldNames` emptied, `list responses retyped: 0` (associations endpoint is a container object, excluded via `containerResponsePaths`); `coverage`→string; `group_id`→integer via `scalarFieldTypes` | [#604895](https://gitlab.com/gitlab-org/gitlab/-/issues/604895) **in dev** — !268447/!268849/!270809/!268850/!270810 merged; [#604896](https://gitlab.com/gitlab-org/gitlab/-/issues/604896) (scalars) filed, no MRs |
| [anonymous-request-bodies](anonymous-request-bodies.md) | 422 inline request bodies hoisted to hash-named `RequestBody_<hash>` schemas | none needed — fixed upstream | [#604897](https://gitlab.com/gitlab-org/gitlab/-/issues/604897) **closed** — grape-openapi 0.7.0 emits stable names; spec now has 0 `RequestBody_*` schemas |
| [date-vs-date-time](date-vs-date-time.md) | `date` columns typed `format: date-time` (`last_activity_on`, `marked_for_deletion_*`, token `expires_at`, …) | `GitLabDateTranscoder` accepts `YYYY-MM-DD` (start-of-day UTC) — covers all mistyped fields | [#642830](https://gitlab.com/gitlab-org/gitlab/-/work_items/642830) **filed** — verified against `db/structure.sql` |
| [missing-response-schemas](missing-response-schemas.md) | 200 responses declared schema-less though the API returns a documented body (`…/import/github/sync/restore`) | `gitlab-spec-tool` transform 6 injects a hand-authored schema (`missingResponseSchemas`) | [#642831](https://gitlab.com/gitlab-org/gitlab/-/work_items/642831) **filed** — verified against the presenter source |

All four are **spec-accuracy defects — the API is correct**, so each is fixable with a
documentation-only change (no API behaviour change). The under-typing spans much of the API, so
expect a **series of PRs** rather than one.
