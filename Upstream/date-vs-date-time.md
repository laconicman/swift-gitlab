# Date-valued fields typed `format: date-time`

Upstream note for `gitlab-org/gitlab`. The **Issue draft** below is plain GitLab-flavoured
markdown, ready to paste into the tracker. The **PR handoff** is the implementation guide.

> **Status (2026-11-25):** verified against `db/structure.sql` on master — every field
> below is backed by a `date` column but declared `type: 'DateTime'` in the entity
> `documentation:`, so the API emits `YYYY-MM-DD` while the spec promises a timestamp.
> Local mitigation shipped in GitLabKit: `GitLabDateTranscoder.decode` accepts a bare
> `YYYY-MM-DD` (start-of-day UTC), which covers every mistyped field — enumerated or
> not. **Filed upstream as
> [gitlab-org/gitlab#642830](https://gitlab.com/gitlab-org/gitlab/-/work_items/642830)**
> on 2026-11-25; the PR handoff below is the implementation guide.
> **MR open 2026-11-26:** [!274692](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/274692)
> (Draft) — patch verified against master; epic `*_from_*` fields excluded (they emit real
> timestamps, see #642892); member/invitation `expires_at` under-spec split to #642891.

---

## Issue draft

**Title:** OpenAPI: `date` columns are typed `format: date-time` in openapi_v3.yaml

### Summary

The REST API returns correct JSON — `date` columns serialize as `YYYY-MM-DD` — but
`doc/api/openapi/openapi_v3.yaml` types many of them `format: date-time`. Strict
typed clients then fail to decode real responses
(`Expected an ISO-8601 date, received '2026-11-24'`). **The API is correct — this is a
spec-accuracy defect, no behaviour change is needed to fix it.** Sibling of
#604895 (arrays) and #604896 (scalars); this is the date/time flavor of the same
under-specification problem.

### Confirmed mistyped (verified against `db/structure.sql` on master)

Response entities — a strict client fails decoding these today:

| Schema | Field | Backing column |
|---|---|---|
| `APIEntitiesUserPublic`, `APIEntitiesUserWithAdmin` | `last_activity_on` | `users.last_activity_on` (`date`) |
| `APIEntitiesProject`, `APIEntitiesProjectWithAccess`, `APIEntitiesProjectsWithAccessAndCatalogSetting`, `APIEntitiesProjectsWithCatalogSetting` | `marked_for_deletion_at`, `marked_for_deletion_on` | `projects.marked_for_deletion_at` (`date`, exposed `as: :marked_for_deletion_on`) |
| `APIEntitiesPersonalAccessToken`, `…WithToken`, `APIEntitiesResourceAccessToken`, `…WithToken`, `APIEntitiesImpersonationToken`, `…WithToken` | `expires_at` | `personal_access_tokens.expires_at` (`date`; the entity block calls `expires_at.iso8601` on a `Date`) |

Request bodies — same defect on the encode side (a `Date`-typed client param
generates a full timestamp for a `date` column):

- `postApiV4GroupsIdMembersRequest`, `putApiV4GroupsIdMembersUserIdRequest`,
  `postApiV4ProjectsIdMembersRequest`, `putApiV4ProjectsIdMembersUserIdRequest` —
  `expires_at` (`members.expires_at` is `date`; descriptions already say
  "Date string in the format YEAR-MONTH-DAY")
- `postApiV4GroupsIdInvitationsRequest`, `putApiV4GroupsIdInvitationsEmailRequest`,
  `postApiV4ProjectsIdInvitationsRequest`, `putApiV4ProjectsIdInvitationsEmailRequest` —
  `expires_at` (same column)

### Likely mistyped (EE — needs verification on an EE instance)

`APIEntitiesEpic` and `APIEntitiesRelatedEpic` type all of these `format: date-time`,
but the `epics` columns are `date`: `start_date`, `start_date_fixed`,
`start_date_from_inherited_source`, `start_date_from_milestones`, `end_date`,
`due_date`, `due_date_fixed`, `due_date_from_inherited_source`,
`due_date_from_milestones`.

### Checked and correct — do **not** "fix" these

They are real timestamps (`timestamp` columns), so `format: date-time` is right:
`enabled_until` (pages domains), the `/geo/status` payload dates,
`merge_after` (`merge_request_merge_schedules`), `released_at`, and `expires_at`
on SSH keys, deploy tokens, CI secure files, CI triggers and vulnerability exports.
The `*_at`/`*_on` naming is *not* a reliable signal — `projects.marked_for_deletion_at`
is a `date` column, `members.expires_at` is a `date` column — which is why each
entry above was verified against the schema, not the name.

### Suggested fix

In the entity `documentation:` metadata, declare `type: 'Date'` (which the generator
maps to `format: date`) instead of `type: 'DateTime'` for the fields above, and fix
the `example:` values to `YYYY-MM-DD`. Documentation-only change, no API behaviour
change. Where an entity inherits the exposure (e.g. `UserWithAdmin < UserPublic`,
the `…WithToken` token variants), fixing the parent covers the family.

### Reproduction

`GET /api/v4/user` on any instance returns `"last_activity_on": "2026-11-24"`;
decoding it against the spec's `format: date-time` fails in a strict client.

---

## PR handoff

**Executed 2026-11-26 as
[!274692](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/274692) (Draft)** —
one MR, not the per-area series sketched below. `openapi_v3.yaml` was hand-synced
(no dev env to run `rake gitlab:openapi:v3:generate`), so `check_docs` CI is the
byte-exact arbiter once a maintainer approves the pipeline.

**Goal:** correct `format:` on date-valued fields in `openapi_v3.yaml`. The entity
`documentation:` edits are generation metadata; the request-param `type:` edits
narrow Grape coercion `DateTime` → `Date` — `Date.parse` accepts `YYYY-MM-DD` and
full timestamps alike and `members.expires_at` is a `date` column, so the stored
value is unchanged (verified against `Date.parse`/`DateTime.parse`, not a live
request — `check_docs` compares spec bytes only).

**Where it originates**
- Grape entity exposures (`lib/api/entities/**.rb`, `ee/lib/api/entities/**.rb`):
  `documentation: { type: 'DateTime' }` on fields backed by `date` columns. The
  generator is faithful — it maps the declared type; the metadata is wrong.
- Examples matter too: `example: '2015-09-03T07:24:01.670Z'` on a `date` field
  should become `example: '2015-09-03'`.

**Shape — as shipped in !274692**
- `lib/api/entities/user_public.rb` — `last_activity_on` → `'Date'`
  (covers `UserWithAdmin < UserPublic`).
- `lib/api/entities/project.rb` — `marked_for_deletion_at` + `marked_for_deletion_on`
  → `'Date'` (covers the `ProjectWithAccess` / catalog-settings family).
- `lib/api/entities/personal_access_token.rb` — `expires_at` → `'Date'`
  (covers all six token schemas via inheritance: personal/resource/impersonation,
  each with a `…WithToken` variant).
- `lib/api/members.rb`, `lib/api/invitations.rb` — param `type: DateTime` → `Date`
  on POST/PUT `expires_at` (all four member + four invitation request schemas).
- `ee/lib/api/entities/epic.rb` — only the five fields that emit `YYYY-MM-DD`:
  `start_date`, `start_date_fixed`, `end_date`, `due_date`, `due_date_fixed`.
  The four `*_from_*` fields stay `date-time`: `WorkItemAsEpic` runs them through
  `.to_time.iso8601`, so the wire value is a real timestamp and retyping them
  would make the spec wrong — their server-timezone serialization wart is
  [#642892](https://gitlab.com/gitlab-org/gitlab/-/work_items/642892).
- Member/invitation **`expires_at` response** exposures (`entities/member.rb`,
  `entities/invitation.rb`) carry no `documentation:` at all — the spec emits
  plain `type: string`, a different defect; filed as
  [#642891](https://gitlab.com/gitlab-org/gitlab/-/work_items/642891).

**Validation**
- `gitlab:openapi:v3:check_docs` regenerates and compares byte-exact — it is the
  arbiter for the hand-synced yaml.
- On the consumer side: a strict typed client decoding `GET /api/v4/user` stops
  throwing on `last_activity_on`.

> GitLabKit relevance: locally mitigated by `GitLabDateTranscoder` accepting
> `YYYY-MM-DD` — the generated types stay `Date?` and keep working for every
> mistyped field, including ones not yet enumerated. Retyping to `format: date`
> upstream will generate `String?` instead; both are honest, and the transcoder
> remains useful for any field upstream misses.
