# Anonymous `RequestBody_<hash>` schemas

Upstream note for `gitlab-org/gitlab`. The **Issue draft** below is plain GitLab-flavoured
markdown, ready to paste into the tracker. The **PR handoff** is the implementation guide.

---

## Issue draft

**Title:** OpenAPI: inline request bodies are emitted as anonymous `RequestBody_<hash>` schemas

### Summary

In `doc/api/openapi/openapi_v3.yaml`, request bodies defined inline on a route are hoisted
into `components/schemas` under **hash-based names** like `RequestBody_6ef4e663c0d4`. There
are **422** such schemas in the current spec. They have no semantic name and the hash changes
whenever the body shape changes, so every code-generator that consumes this spec produces
meaningless, version-unstable types.

### Example

```yaml
# components/schemas
RequestBody_6ef4e663c0d4:
  type: object
  properties:
    start_date: { type: string, format: date, nullable: true }
    end_date:   { type: string, format: date, nullable: true }
    plan_code:  { type: string }
    # …
```

This is the body of `POST /api/v4/namespaces/{id}/gitlab_subscription`, but nothing in the
name says so. A typed client (e.g. Apple's swift-openapi-generator) turns it into
`Components.Schemas.RequestBody0f2b66d0bb55` — undiscoverable and unstable.

### Impact

| | |
|---|---|
| **Discoverability** | Consumers can't tell what `RequestBody_6ef4e663c0d4` is for. |
| **Stability** | The hash is derived from the body shape; any field change renames the type, breaking generated code across GitLab versions. |
| **Ergonomics** | Generated SDKs expose `RequestBody0f2b66d0bb55` instead of, say, `CreateNamespaceSubscriptionRequest`. |
| **Scale** | 422 occurrences — pervasive across the API. |

### Suggested fix

Give inline request bodies **stable, semantic names** derived from the operation (e.g.
`<OperationId>Request` or `<Resource><Verb>Request`), either by:
- naming the Grape `params` block so the OpenAPI generation can use it, or
- having the spec-generation tooling derive the schema name from the route's `operationId`
  instead of hashing the body.

### Reproduction

Search the spec for `^    RequestBody_[0-9a-f]+:` → 422 matches. Generate any typed client and
observe the `RequestBody<hash>` type names.

---

## PR handoff

**Goal:** replace hash-named inline request-body schemas with stable, semantic names — a
spec-generation change, **no API behaviour change**.

**Where it originates**
- Grape route definitions (`lib/api/**.rb`) with inline `params do … end` blocks that aren't
  backed by a named entity/params class.
- The Grape→OpenAPI generation step that, lacking a name, falls back to hashing the body.

**Two PR shapes (smallest-leverage first)**
1. **Generation-level (preferred, systemic):** in the OpenAPI generation tooling, name an
   inline request body from its `operationId` (e.g. `postApiV4…GitlabSubscription` →
   `PostApiV4NamespacesIdGitlabSubscriptionRequest`). One change fixes all 422. Coordinate on
   the existing OpenAPI tooling issues
   ([#519959](https://gitlab.com/gitlab-org/gitlab/-/issues/519959),
   [#591007](https://gitlab.com/gitlab-org/gitlab/-/issues/591007)).
2. **Targeted:** extract the most-used inline bodies into named params classes / entities. More
   reviewable but only chips away at the 422.

**Validation**
- Regenerate the spec; confirm `RequestBody_<hash>` keys are gone (or reduced) and replaced by
  named schemas.
- On the consumer side: `swift run gitlab-spec-tool --ref <branch>` then `swift build` — the
  generated `RequestBody<hash>` types are replaced by readable names, and stay stable across
  subsequent spec updates.

> GitLabKit relevance: these schemas are request bodies (no `id`), so the `Identifiable`
> generator already skips them; the harm is purely naming/stability on the request side.
