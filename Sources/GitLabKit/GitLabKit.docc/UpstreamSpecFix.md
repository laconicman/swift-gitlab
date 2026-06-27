# Upstream Spec Fix (handoff)

How to fix the array under-typing (<doc:TechDebt> #1) at the source — a spec-only PR to
GitLab that retires our local retyping. Pick this up when there's time to contribute upstream.

> Pasteable **issue drafts** and **PR handoffs** (for this, the scalar mismatch, and the
> anonymous `RequestBody_<hash>` schemas) live in the repo's `Upstream/` directory. This
> article is the overview; that folder holds the ready-to-file artifacts.

## The claim to make in the PR

GitLab's REST API returns JSON **arrays** for list endpoints and for plural entity fields
(`assignees`, `reviewers`, …), but the published OpenAPI document
(`doc/api/openapi/openapi_v3.yaml`) types them as a **single object**. This is a
documentation defect, not an API defect — **no runtime behavior changes**, only the generated
schema. Evidence: a live `GET /projects/:id/merge_requests/:iid` returns 200 and the body is a
valid MR, but a strict OpenAPI-typed client fails with
`DecodingError typeMismatch at "assignees": expected object, found array`.

## Where it comes from

The spec is generated from the Grape API definitions. Two layers under-specify arrays:

1. **Entity exposures** (`lib/api/entities/**.rb`) — `expose :assignees, using: Entities::UserBasic`
   without `documentation: { is_array: true }` emits a bare `$ref` instead of
   `type: array, items: $ref`.
2. **List endpoints** — paginated `get` routes whose success entity isn't marked as a
   collection emit a single-object 200 response.

## Two PR shapes (smallest-leverage first)

- **Targeted (good first PR):** add `documentation: { is_array: true }` to the handful of
  plural entity exposures the review surface needs — start with `Entities::MergeRequest`
  `assignees`/`reviewers`. Small, reviewable, immediately useful.
- **Systemic (higher leverage):** fix the Grape→OpenAPI generation so any paginated route or
  array exposure emits `type: array`. This is the real fix but a larger change; coordinate on
  the existing OpenAPI tooling issues first
  ([#519959](https://gitlab.com/gitlab-org/gitlab/-/issues/519959),
  [#591007](https://gitlab.com/gitlab-org/gitlab/-/issues/591007)).

## How to validate the fix locally

```bash
swift run gitlab-spec-tool --ref <your-branch-or-mr-sha>   # vendor the patched spec
swift build                                              # regenerate
```

When the upstream fix is correct, `gitlab-spec-tool` reports **`array fields retyped: 0`** and
**`list responses retyped: 0`** for the fixed areas — the retyping has nothing left to do.
At that point the local mitigation can be narrowed or removed (see <doc:Roadmap>), and we pin
`--ref` to the fixed revision so we never "re-fix" an already-correct spec.
