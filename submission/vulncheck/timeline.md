# Disclosure timeline — mem0 (UTC)

| Time | Event |
|---|---|
| 2026-11-18T18:39:10Z | Exploit run completes: `result: CONFIRMED`, 14/14 assertions, exit 0 |
| 2026-11-18T19:20:25Z | GitHub private advisory `GHSA-62c5-2wrq-ffpv` created (state `triage`, severity high, credit Teycir, no CVE) |
| 2026-11-18T19:29:30Z | Email to `support@mem0.ai`, subject `SECURITY: Mem0 vulnerability report`; Message-ID `<5J6RvUzweY_xG7rpP942ZMxGJWo3DyUXaUqU9I2acFk3teyBeYBZuuM5fme1Gign9EI3204saP6KHRytX0zpr_d_VKDG90Ryoll9Lyujl6c=@protonmail.com>` |
| 2026-11-18T19:29:30Z + 72 h = **2026-11-21T19:29:30Z** | Vendor acknowledgement deadline per `SECURITY.md` |
| 2026-11-21T13:42Z | No vendor reply; GHSA still private (HTTP 404); upstream HEAD `fff8a64` contains no server-auth change; latest release remains v2.2.1 |
| 2026-11-21T16:20Z | VulnCheck case `68502237-1e2c-4a2d-9d00-baac94a8a65a` issued for MEM0-2026-01 submission |
| 2026-11-21T16:30Z | VulnCheck case `2f43d35e-08a2-4356-b759-0809b3adb080` issued for MEM0-2026-02 submission |
| 2026-11-21T16:36Z | Report repository `Teycir/mem0-tenant-isolation` made PUBLIC — full report, evidence and PoC now serve as the public reproduction package (submitted to VulnCheck post-facto) |
| 2026-11-23T10:36Z | Upstream `main` @ `f93aba4b` (PR #7985, Dependabot/Vanta fixes) verified against clone: MEM0-2026-01 NOT fixed, MEM0-2026-02 PARTIALLY fixed (`POST /configure` now `require_admin`; `GET` still any-auth, exact-match redaction, `history_db_path` exposed). See `report.md` §5.5 |
| 2026-11-24 | Follow-up status request to `disclosure@vulncheck.com` re cases `68502237-…` and `2f43d35e-…` (CVE assignment status, timeline, fix-status summary). Body: `followup-vulncheck-2026-11-24.txt` |
| 2026-11-24T19:51:52Z | Vulners CNA email sent to `cna@vulners.com` for MEM0-2026-01 (High, CVSS 8.8); Message-ID `<WvbiEGCCFTtkfTsFggpOsRWVUP7mAoBH1YXmVIFz4KStdqZySt4IBx4wyclKtukWf3z590BsaGuHb88LggwuVvdkxP5Nic7DXcEPoUA3LQg=@protonmail.com>`; archived `submission/vulners/sent/20261124T195155Z-vulners-mem0-2026-01.eml` (sha256 `80e96f59…7721`) |
| 2026-11-24T19:54:14Z | Vulners CNA email sent to `cna@vulners.com` for MEM0-2026-02 (Medium, CVSS 4.3); Message-ID `<qHMxvDn4DfYdKfjKLrR3Ar6xYpCuLI5ScceHiCJlE9BAODweO0xtcQ49gq8JR8K_weK-XAdkTyKGsYi_KsdfF8LKh0m3bzSkKad0-sFjpQk=@protonmail.com>`; archived `submission/vulners/sent/20261124T195415Z-vulners-mem0-2026-02.eml` (sha256 `7b884631…e780`) |

## Vendor channels used

1. GitHub private vulnerability reporting — `mem0ai/mem0` Security tab (primary per `SECURITY.md`).
2. `support@mem0.ai` (fallback per `SECURITY.md`).

No MITRE request was made. Public disclosure occurred 2026-11-21T16:36Z when the
report repository was made public (after both VulnCheck submissions were sent;
the form answers recorded "not publicly disclosed" at send time).
