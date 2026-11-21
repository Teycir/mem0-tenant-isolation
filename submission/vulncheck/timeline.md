# Disclosure timeline — mem0 (UTC)

| Time | Event |
|---|---|
| 2026-11-18T18:39:10Z | Exploit run completes: `result: CONFIRMED`, 14/14 assertions, exit 0 |
| 2026-11-18T19:20:25Z | GitHub private advisory `GHSA-62c5-2wrq-ffpv` created (state `triage`, severity high, credit Teycir, no CVE) |
| 2026-11-18T19:29:30Z | Email to `support@mem0.ai`, subject `SECURITY: Mem0 vulnerability report`; Message-ID `<5J6RvUzweY_xG7rpP942ZMxGJWo3DyUXaUqU9I2acFk3teyBeYBZuuM5fme1Gign9EI3204saP6KHRytX0zpr_d_VKDG90Ryoll9Lyujl6c=@protonmail.com>` |
| 2026-11-18T19:29:30Z + 72 h = **2026-11-21T19:29:30Z** | Vendor acknowledgement deadline per `SECURITY.md` |
| 2026-11-21T13:42Z | No vendor reply; GHSA still private (HTTP 404); upstream HEAD `fff8a64` contains no server-auth change; latest release remains v2.2.1 |
| 2026-11-21T__:__Z | VulnCheck submission sent (record case ID here) |

## Vendor channels used

1. GitHub private vulnerability reporting — `mem0ai/mem0` Security tab (primary per `SECURITY.md`).
2. `support@mem0.ai` (fallback per `SECURITY.md`).

No MITRE request was made. No public disclosure has occurred.
