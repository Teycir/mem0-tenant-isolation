# VulnCheck web form — field values

Source: <https://vulncheck.com/advisories/report>. Values are ready to paste.

## Shared fields

| Field | Value |
|---|---|
| Your name / credit | Teycir |
| Contact email | teycir@users.noreply.github.com |
| Reporting on behalf of | Myself |
| Vendor | mem0 |
| Product | mem0 — self-hosted REST API server (`server/` component of the `mem0ai/mem0` repository) |
| Product URL | https://github.com/mem0ai/mem0 |
| Tested versions | `mem0ai` 2.2.1, commit `f1791da` (2026-11-06). HEAD `fff8a64` differs only in `mem0/llms/base.py`; server code unchanged. |
| Coordinate disclosure | **Yes** — vendor unresponsive; please take over coordination |
| Previously requested CVE from MITRE without response | No |
| Already publicly disclosed | No — private GitHub advisory `GHSA-62c5-2wrq-ffpv` (state `triage`, no CVE, not public) |
| AI involvement | Yes — LLM assistant used for source analysis and drafting; reporter executed the 14-step exploit against a live local build and confirmed every assertion |
| Verified on production code | Yes — release 2.2.1 source, built and run locally (pgvector + stub OpenAI endpoint) |
| Shodan / Fofa query | N/A — self-hosted software, no internet-wide fingerprint |
| Plan to publish | Yes, on or after the coordinated disclosure date |

## Request 1 — MEM0-2026-01

- **VulnCheck case ID:** `68502237-1e2c-4a2d-9d00-baac94a8a65a` (submitted 2026-11-21)
- **Title:** Broken tenant authorization in mem0 self-hosted memory endpoints
- **Severity:** High, CVSS 3.1 8.8 `AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H`
- **CWE:** CWE-639 (primary), CWE-284
- **Affected component:** `server/main.py`, `server/routers/entities.py`, `mem0/memory/main.py`
- **Privileges:** any valid API key with `role="user"`; `AUTH_DISABLED=false`; ≥2 principals
- **Details:** paste `details-MEM0-2026-01.md`

## Request 2 — MEM0-2026-02

- **Title:** `GET /configure` discloses internal infrastructure and unredacted credential keys to any authenticated user
- **Severity:** Medium, CVSS 3.1 4.3 `AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N`
- **CWE:** CWE-200
- **Affected component:** `server/main.py:322-324` (`GET /configure`), `_redact_config` at `server/main.py:222-229`
- **Privileges:** any valid API key (`role=user`)
- **Details:** paste `details-MEM0-2026-02.md`

## Vendor-contact wording

Use exactly this (72 h window elapsed 2026-11-21T19:29:30Z; submission deferred
until after the gate):

"Reported to the vendor on 2026-11-18T19:20Z (private GitHub advisory) and
2026-11-18T19:29Z (email to support@mem0.ai). No acknowledgement after the
vendor's stated 72-hour window (elapsed 2026-11-21T19:29:30Z)."

Do not use the pre-gate "no acknowledgement yet" variant — the window has closed.
