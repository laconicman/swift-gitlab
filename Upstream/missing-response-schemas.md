# Missing 200 response schemas

Upstream note for `gitlab-org/gitlab`. The **Issue draft** below is plain GitLab-flavoured
markdown, ready to paste into the tracker. The **PR handoff** is the implementation guide.

> **Status (2026-11-25):** verified against source on master —
> `ee/lib/ee/api/import_github.rb` declares `success code: 200` with no `model:` and
> returns `Import::Sync::GithubUpdatesStatusPresenter#to_h` plus a conditional
> `warning`. grape-openapi only models entity-backed responses, so the generated spec
> emits an empty 200 and typed clients get `Void` where the API returns a documented
> body. The `warning` field is the only machine-readable signal that GitHub updates
> were restored *without* a webhook (degraded to scheduled checks). Local mitigation
> shipped in GitLabKit: `gitlab-spec-tool` transform 6 (`missingResponseSchemas`)
> injects a hand-authored schema — verified field-for-field against the presenter.
> **Issue draft below is ready to file** (no tracker credentials handy at writing
> time); this note is the record either way.

---

## Issue draft

**Title:** OpenAPI: `POST /projects/:id/import/github/sync/restore` 200 response has no schema

### Summary

`doc/api/import.md` documents the 200 response of
`POST /api/v4/projects/:id/import/github/sync/restore` — `state`, `read_only`,
`final_pass_incomplete`, `data` (per-type update status) and a conditional
`warning` — but `doc/api/openapi/openapi_v3.yaml` declares the 200 with no
`content` at all. Strict typed clients therefore see an empty body and cannot
read the sync status or the `warning` that reports updates were restored
without a webhook. **The API is correct — this is a spec-accuracy defect, no
behaviour change is needed to fix it.** Same family as #604895/#604896/#604897
and the `date`-vs-`date-time` mistyping: grape-openapi under-describes what the
API returns.

### Root cause

`ee/lib/ee/api/import_github.rb` — the endpoint's `desc` block ends with a bare
`success code: 200` (no `model:`), and the handler returns
`Import::Sync::GithubUpdatesStatusPresenter.new(sync_repository).to_h` — a plain
hash, not an `Entities::` class. grape-openapi derives response schemas from
entities, so a presenter `to_h` payload has nothing to model and the 200 ships
empty.

### Confirmed

- Spec: `paths./api/v4/projects/{id}/import/github/sync/restore.post.responses.200`
  has `description: OK` and no `content`.
- Docs: `doc/api/import.md` "Restore GitHub updates with a new personal access
  token" documents the response attributes and a full JSON example.
- Presenter: `ee/app/presenters/import/sync/github_updates_status_presenter.rb`
  emits exactly `state`, `read_only`, `final_pass_incomplete`, `data`
  (`index_by(&:domain)` of `{state, last_updated_at, last_checked_at}`); the
  endpoint adds `warning` when the webhook could not be created
  (`ee/lib/ee/api/import_github.rb`).

### Suggested fix

Give the response an entity (or an equivalent grape-openapi-modelable
representation) and declare `success code: 200, model: …` on the `desc`. The
presenter shape maps cleanly: `data` is an object keyed by sync domain
(`additionalProperties` of `{state, last_updated_at, last_checked_at}`), and
`last_*_at` are nullable timestamps. `warning` is conditional — optional.

### Reproduction

`POST /api/v4/projects/:id/import/github/sync/restore` on a Premium/Ultimate
instance with disconnected GitHub updates returns a JSON body; validating that
body against `openapi_v3.yaml` fails because the 200 declares no schema.

---

## PR handoff

**Goal:** make the generated spec describe the restore endpoint's 200 body —
spec-generation change only, **no API behaviour change**.

**Where it originates**
- `ee/lib/ee/api/import_github.rb` — `desc 'Restore GitHub updates…'` block,
  `success code: 200` without `model:`.
- `ee/app/presenters/import/sync/github_updates_status_presenter.rb` — the
  payload shape (`to_h`).

**Shape**
- Introduce an `Entities::` class (or extend grape-openapi to model presenter
  payloads) exposing `state`, `read_only`, `final_pass_incomplete`, `data`,
  `warning`; declare it as the 200 model. The presenter can then `present …,
  with: Entities::…` or the entity can wrap the same hash.
- `data` values: `state` (string), `last_updated_at`/`last_checked_at`
  (nullable `timestamp` → `format: date-time`); keys are sync domains
  (`additionalProperties`).
- `warning`: optional string, only present when no webhook could be created.

**Validation**
- Regenerate `openapi_v3.yaml`; the operation's 200 gains
  `content.application/json.schema`.
- Consumer check: a strict typed client decoding the restore response stops
  seeing an empty body and can read `warning`.

> GitLabKit relevance: locally patched by `gitlab-spec-tool` transform 6
> (`missingResponseSchemas`) with a schema hand-authored from the presenter —
> every leaf `nullable` since the docs don't pin nullability. When upstream
> adds the model, the transform's `content`-absent guard makes it a no-op.
