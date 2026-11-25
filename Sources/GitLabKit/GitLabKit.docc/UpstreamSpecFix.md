# Upstream Spec Fix (handoff)

How to fix the array under-typing (<doc:TechDebt> #1) at the source — a spec-only PR to
GitLab that retires our local retyping. Pick this up when there's time to contribute upstream.

> Pasteable **issue drafts** and **PR handoffs** (for this, the scalar mismatch, the
> anonymous `RequestBody_<hash>` schemas, and the `date`-vs-`date-time` mistyping) live in
> the repo's `Upstream/` directory. This article is the overview; that folder holds the
> ready-to-file artifacts.
>
> Status (2026-11-25): the first three were filed upstream on 2026-07-03 —
> [#604895](https://gitlab.com/gitlab-org/gitlab/-/issues/604895) (arrays),
> [#604896](https://gitlab.com/gitlab-org/gitlab/-/issues/604896) (scalars),
> [#604897](https://gitlab.com/gitlab-org/gitlab/-/issues/604897) (`RequestBody_<hash>` naming).
>
> - **#604895 — in dev, nearly done.** Fix MRs merged so far:
>   [!268447](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/268447) (core),
>   [!268849](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/268849) (EE),
>   [!270809](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/270809) (organizations),
>   [!268850](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/268850) (source-code),
>   [!270810](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/270810) (token-associations);
>   webhooks/geo may still be open. The merged areas cover the whole
>   review surface — `gitlab-spec-tool` now reports `array fields retyped: 0` and only
>   **1 list response** still needs retyping (`personal_access_tokens/self/associations`;
>   !270810 merged 2026-11-24 but the spec regen may lag).
> - **#604896 — filed, not started.** No related MRs. `coverage` stays locally retyped
>   to string, and `milestone.group_id` is now locally retyped to integer via the
>   curated `scalarFieldTypes` map — verified against live gitlab.com MR data;
>   the live decode records no known issues.
> - **#604897 — complete.** Fixed by gitlab-grape-openapi 0.7.0
>   ([!62](https://gitlab.com/gitlab-org/ruby/gems/gitlab-grape-openapi/-/merge_requests/62)
>   "stable, collision-safe schema names" in the tooling repo, vendored via
>   [!259271](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/259271)): the spec went
>   from 422 `RequestBody_<hash>` schemas to 0 — request bodies now carry stable
>   operation-derived names.

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
That state is already true for the array *fields* (the `arrayFieldNames` list is empty) and
nearly so for list responses; as the remaining upstream MRs merge, re-vendor master and the
response count drops toward zero — then the transform can be narrowed or removed (see
<doc:Roadmap>).


## Some strange default servers in the spec
Reconsider using OpenAPI standards and guidelines.
