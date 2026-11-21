# VulnCheck submission package — mem0 (2 CVE requests)

Status: **READY — not sent.**
Channel: <https://vulncheck.com/advisories/report> (primary) or `disclosure@vulncheck.com`.
CNA scope note: GitHub is the CNA for `mem0ai/mem0`; a private advisory exists
(`GHSA-62c5-2wrq-ffpv`, state `triage`, no CVE) and the vendor has not acknowledged.
VulnCheck states it will "issue a CVE directly or work with the most appropriate CNA".

## Requests

| ID | Title | Severity | CVSS 3.1 | CWE |
|----|-------|----------|----------|-----|
| MEM0-2026-01 | Broken tenant authorization on memory endpoints | High | 8.8 | CWE-639 / CWE-284 |
| MEM0-2026-02 | `GET /configure` info disclosure (auth-only, weak redaction) | Medium | 4.3 | CWE-200 |

MEM0-2026-03 (no rate limit, CWE-770) is **excluded** — Low, not submitted.

## Files

| File | Use |
|---|---|
| `form-answers.md` | paste into the web form, field by field |
| `email-to-disclosure.txt` | paste-ready mail body |
| `MEM0-2026-01.cve.json` | CVE 5.1 record draft |
| `MEM0-2026-02.cve.json` | CVE 5.1 record draft |
| `timeline.md` | vendor-contact evidence for the form |
| `SHA256SUMS` | integrity of this directory |

## Send gate (72 h vendor SLA)

Vendor email sent `2026-11-18T19:29:30Z`; mem0 `SECURITY.md` promises acknowledgement
within 72 h → **2026-11-21T19:29:30Z**. **Decision (2026-11-21): wait for the gate;
submit only after 19:29:30Z** using the "72 h elapsed" wording now set in
`form-answers.md` and `email-to-disclosure.txt`.

## After sending

1. Record VulnCheck ticket/case ID in `timeline.md`, commit.
2. Do not publish `report.md`, `evidence/`, or `poc/` until a coordinated date is agreed.
3. Keep the repo private (GitHub `Teycir/mem0-tenant-isolation`, private).

## Evidence available to VulnCheck

`report.md`, `evidence/` (transcripts, request/response, hashes), `poc/` (14-assertion
exploit + local harness). Full package hash list: `evidence/MANIFEST.txt`.

## Validation performed (2026-11-21T13:47Z)

- Both `*.cve.json` parse and validate against the official CVE 5.1 schema
  (`CVEProject/cve-schema`, `CVE_Record_Format.json`) once `cveId` and `assignerOrgId`
  are replaced with stand-ins. The shipped drafts keep placeholders on purpose:
  `CVE-2026-XXXXX` and the all-zero org UUID — VulnCheck assigns both.
- `sha256sum -c SHA256SUMS` passes.
- VulnCheck report page reachable (`HTTP 200`).
