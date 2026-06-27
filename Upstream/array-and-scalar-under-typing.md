# Array & scalar under-typing

Upstream note for `gitlab-org/gitlab`. The **Issue draft** is plain GitLab-flavoured markdown,
ready to paste; the **PR handoff** is the implementation guide. (The DocC `UpstreamSpecFix`
article is the in-repo overview of the same problem.)

---

## Issue draft

**Title:** OpenAPI: response types under-describe arrays and some scalar types

### Summary

The REST API returns correct JSON, but `doc/api/openapi/openapi_v3.yaml` under-describes
response shapes in two ways, so strict typed clients fail to decode real responses. **The API
is correct — this is a spec-accuracy defect, no behaviour change is needed to fix it.**

### 1. Arrays typed as single objects

Collections and plural fields are typed as one object, not an array:

- **List endpoints** — e.g. `GET /projects/:id/merge_requests/:iid/notes` is typed as
  `APIEntitiesNote`, not `[APIEntitiesNote]`.
- **Nested fields** — on `APIEntitiesMergeRequest`, `assignees` and `reviewers` are typed
  `APIEntitiesUserBasic` (one user) but the API returns an array. (`labels` is typed correctly,
  so it's field-by-field, not uniform.)

A strict client decoding a real response throws `typeMismatch … found an array instead`,
confirmed live: `GET /projects/278964/merge_requests/1` returns 200 with a valid body, only the
typed decode disagrees.

### 2. Scalar type mismatches

Some scalar fields are mistyped — e.g. `APIEntitiesMilestone.group_id` is typed `string` but
returned as a **number**, producing `typeMismatch String … found number instead` when decoding
a merge request that carries a milestone.

### Suggested fix

- Mark array exposures/responses with `is_array` so the generated schema is `type: array`.
- Correct mistyped scalars (`group_id` → integer) at the entity exposure.

Both are documentation-only changes.

---

## PR handoff

**Where it originates**
- Entity exposures (`lib/api/entities/**.rb`): `expose :assignees, using: Entities::UserBasic`
  without `documentation: { is_array: true }` → bare `$ref` instead of `type: array`.
- Paginated routes whose success entity isn't marked as a collection → single-object 200.
- Scalar mismatches: an `expose` whose documented type doesn't match what's returned
  (`group_id`).

**Two PR shapes (smallest-leverage first)**
1. **Targeted (good first PR):** add `documentation: { is_array: true }` to the review entities'
   plural exposures (`MergeRequest` `assignees`/`reviewers`) and fix `Milestone.group_id`. Small
   and immediately useful.
2. **Systemic:** fix the Grape→OpenAPI generation so any paginated route / array exposure emits
   `type: array`. The real fix, larger change — coordinate on
   [#519959](https://gitlab.com/gitlab-org/gitlab/-/issues/519959) /
   [#591007](https://gitlab.com/gitlab-org/gitlab/-/issues/591007). Likely **a series of PRs**,
   since the under-typing spans much of the API.

**Validation**
- `swift run gitlab-spec-tool --ref <branch>` then `swift build`. When an area is fixed upstream,
  GitLabKit's retyper reports `array fields retyped: 0` / `list responses retyped: 0` for it —
  the local workaround becomes a no-op. The `liveDecodeReviewEntities` test stops recording the
  corresponding known issue.
