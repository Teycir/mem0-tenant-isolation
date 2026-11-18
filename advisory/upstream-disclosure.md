# Upstream submission package

This file is the cover note for sending the finding to Mem0. It intentionally
follows Mem0's published process (`SECURITY.md`) rather than mailing a CNA
directly.

## Channel (in this order)

1. **Primary — GitHub Private Vulnerability Reporting** on `mem0ai/mem0`:
   <https://github.com/mem0ai/mem0/security/advisories/new>
   GitHub is the CNA that issues the GHSA/CVE identifiers for this repository.
2. **Fallback — email `support@mem0.ai`**, subject exactly
   `SECURITY: Mem0 vulnerability report`, if the advisory form is unavailable
   or no acknowledgement arrives within 72 hours.
3. **Do not** send to `cve@mitre.org` first. MITRE is only appropriate if the
   maintainers decline to assign and ask the reporter to pursue a CVE
   independently.

## AI involvement (required disclosure)

> An AI coding assistant (LLM agent) was used for source-code analysis and to
> help draft this advisory. The reporter personally executed
> `poc/exploit.py` against a live build, observed every one of the 14
> assertions pass, and verified the recorded impact. The committed transcript
> is a real run, not model output.

Mem0's policy honours AI-assisted reports only after the reporter has run the
reproduction and confirmed impact; the run log in `evidence/` is that proof.

## Fields for the advisory form

| Field | Value |
|---|---|
| Ecosystem / package | pip, `mem0ai` |
| Affected versions | 2.2.1 (server component), commit `f1791da` — the only build tested; earlier 2.x server builds not verified |
| Component | `server/main.py`, `server/routers/entities.py`, `mem0/memory/main.py` |
| Weakness | CWE-639 (authorization bypass through user-controlled key), CWE-284 |
| Severity | High — CVSS 3.1 8.8 `AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H` |
| Privileges required | Any valid API key with `role="user"` |
| User interaction | None |

## Summary

With authentication enabled, the REST server never binds `user_id` /
`agent_id` / `run_id` / memory `id` to the authenticated principal.
`GET /entities` (auth-only) enumerates every tenant, after which a
low-privilege key can read, overwrite and delete other tenants' memories via
`GET /memories?user_id=…`, `GET|PUT|DELETE /memories/{id}`,
`GET /memories/{id}/history`, and `POST /search`.

Negative control: `GET /memories` without a `user_id` returns 403
("Admin role required to list all memories"), yet the same key succeeds once
`user_id` is supplied. That contrast is the bypass, not a design choice.

Secondary, same build:
- `GET /configure` uses `verify_auth` only and leaks `host`, `port`,
  `dbname`, `user`, `history_db_path`, `model`, `collection_name`.
  Verified on `f1791da`: `GET /configure` → `Depends(verify_auth)`
  (`server/main.py` ~L322) while `POST /configure` → `Depends(require_admin)`
  (~L333). The admin-check fix on the write path did not cover the read path.
- `_redact_config` matches an exact, lower-cased key list, so
  `aws_secret_access_key`, `client_secret` and similar keys would not be
  redacted if configured.
- Any authenticated key can consume the shared embedding/LLM budget
  (`POST /search`, `POST /memories` with `infer=true`).

## Reproduction (what the maintainer runs)

```
BASE=http://127.0.0.1:8000 \
ATTACKER_KEY=<role=user key> \
VICTIM_KEY=<key owned by a different principal> \
VICTIM=<victim user_id> \
python3 poc/exploit.py --json transcript.json
```

Expected: `result: CONFIRMED  steps=14  failures=0`, exit code 0. The
write/delete target is created with the victim's key, so the attacker does not
control its creation. Only that synthetic record is modified.

## Attachments

- `advisory/2026-11-18-mem0-tenant-isolation.md` — technical advisory
- `report.md` — full assessment with request/response evidence
- `poc/exploit.py`, `poc/setup_local.sh`, `poc/poc_cross_tenant.sh`
- `evidence/04_exploit_transcript.{txt,json}` and `evidence/MANIFEST.txt`

## Handling

Per `SECURITY.md`: 72-hour acknowledgement expected; technical details stay
private until a fix or mitigation ships. This repository has **no remote** and
nothing has been published. Do not push it publicly before the maintainers
acknowledge; at most, make it private and share the advisory contents through
the GitHub security advisory.
