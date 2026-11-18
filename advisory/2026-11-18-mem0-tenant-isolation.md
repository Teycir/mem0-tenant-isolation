# Advisory: mem0 self-hosted REST API — broken tenant isolation

- **Advisory ID:** MEM0-2026-01
- **Product:** mem0 (OSS), `server/` FastAPI REST API
- **Version tested:** `mem0ai 2.2.1`, commit `f1791da` (`fix(security): upgrade @azure/msal-node ... (#7850)`)
- **Affected configurations:** `AUTH_DISABLED=false`, two or more principals on one instance
- **Severity:** High
- **CVSS 3.1:** 8.8 `AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H`
- **CWE:** CWE-639, CWE-284
- **Status:** Disclosed — GitHub private advisory `GHSA-62c5-2wrq-ffpv` created 2026-11-18T19:20:25Z via the `mem0ai/mem0` web form, state `triage`, severity high, credit `Teycir`, no CVE assigned yet (email copy also sent to `support@mem0.ai` 2026-11-18T19:29Z)
- **Reporter:** Teycir (independent)
- **AI involvement:** An LLM coding assistant was used for source analysis and drafting. The reporter personally ran every reproduction step and confirmed all 14 assertions live; the committed transcript is a real run.
- **Submission channel:** GitHub private advisory `GHSA-62c5-2wrq-ffpv` on `mem0ai/mem0` (web form; REST create returns 403 without admin/security rights), plus `support@mem0.ai`; not sent to a CNA directly.

## Summary

The self-hosted mem0 API authenticates callers but does not authorize them against the
memory namespace they address. Every endpoint that touches memories accepts an
attacker-chosen `user_id`, `agent_id`, `run_id` or `memory_id` and performs no ownership
check. The only role check in the API serves the unfiltered `GET /memories` list, which is
bypassed by adding any identifier to the query string.

The server never consumes the `Mem0-User-ID` header that the official client sends
(`mem0/client/main.py`, `_client_headers`); tenant scoping exists only client-side.

## Affected endpoints

| Endpoint | Guard | Problem |
|---|---|---|
| `GET /entities` | `verify_auth` | Enumerates every `user_id`/`agent_id`/`run_id` (10k-row scan) for any key |
| `GET /memories?user_id=` | `verify_auth` | Reads any namespace; role gate only on the unfiltered branch |
| `GET /memories/{id}` | `verify_auth` | Resolves by ID alone (`mem0/memory/main.py:1222`) |
| `GET /memories/{id}/history` | `verify_auth` | Full mutation history of any record |
| `PUT /memories/{id}` | `verify_auth` | Overwrites another tenant's memory |
| `DELETE /memories/{id}` | `verify_auth` | Deletes another tenant's memory |
| `POST /search` | `verify_auth` | Attacker-controlled `filters` are trusted; core only requires *some* identifier |
| `GET /configure` | `verify_auth` | Internal DB host/port/db/user + `history_db_path` disclosed to any user |

## Root cause

`server/routers/entities.py:45` and `server/main.py:322-524` depend on
`verify_auth`, which establishes *who* the caller is and returns a `User` object, but no
handler compares that principal to the namespaced data it reads or mutates. Core
`mem0/memory/main.py` (`get`, `get_all`, `search`, `update`, `delete`, `history`) likewise
operates on caller-supplied identifiers with no scope predicate.

`server/auth.py` gives `User.role` a default of `"admin"` and `require_admin` is used for
configuration, deletion of all memories, and resets — so a non-admin role is part of the
intended design, but is never consulted for object-level access.

## Proof of concept

Full transcript and hashes: `evidence/` and `report.md`.
Reproducer: `poc/setup_local.sh` then `poc/poc_cross_tenant.sh`.

```http
GET /entities HTTP/1.1
X-API-Key: <role=user key>

HTTP/1.1 200 OK
[{"id":"alice_tenant","type":"user","total_memories":1},
 {"id":"bob_tenant","type":"user","total_memories":1}]
```

```http
GET /memories?user_id=alice_tenant HTTP/1.1
X-API-Key: <role=user key>

HTTP/1.1 200 OK
{"results":[{"id":"1bd03115-79b1-4d66-aa2a-452a3209f071",
             "memory":"Tenant Alice private: SSN 123-45-6789, API token sk-alice-secret",
             "user_id":"alice_tenant"}]}
```

```http
GET /memories HTTP/1.1
X-API-Key: <role=user key>

HTTP/1.1 403 Forbidden
{"detail":"Admin role required to list all memories."}
```

The 403 is the negative control: the role check exists, and `?user_id=` defeats it.

## Impact

- **Confidentiality:** full read of every tenant's memories — typically PII, credentials, business context, conversation history.
- **Integrity:** silent poisoning of records consumed by other tenants' agents (indirect prompt injection into victims' agent context).
- **Availability:** deletion of other tenants' memories; no audit distinction from legitimate traffic.
- Applies to any multi-tenant deployment of the self-hosted server.

## Remediation

1. Derive the namespace from the authenticated principal (`User.tenant_id`) and reject requests whose `user_id`/`agent_id`/`run_id` do not match.
2. On `/memories/{memory_id}` and `/history`, load the record and assert its stored `user_id` is in the caller's allowed set before any read/write/delete.
3. Require `require_admin` for `GET /entities` (or filter the aggregation to the caller's entities).
4. Never treat `Mem0-User-ID` as scope; it is untrusted client input.
5. Quick mitigation: gate all memory routes behind `require_admin` until tenant binding exists.
6. Defense-in-depth: per-key namespace allowlist, structured audit log of `(principal, namespace, action)`, and a regression test asserting a `role=user` key receives 403/404 on a foreign namespace.

## Secondary findings

- **MEM0-2026-02 (Medium, CWE-200):** `GET /configure` requires only `verify_auth` and redacts by exact key name (`SENSITIVE_CONFIG_KEYS`), so `aws_secret_access_key`, `client_secret`, `private_key`, `credentials_path` are returned unredacted; `host`, `port`, `dbname`, `user`, `history_db_path` always leak.
- **MEM0-2026-03 (Low, CWE-770):** no rate limits or body caps on memory routes; `/entities` performs a 10k-row scan per call; `/generate-instructions` triggers a billable LLM call per request.

## Refuted

- SQL injection in pgvector filters — parameterized via psycopg `sql` composition.
- Empty-filter `/search` enumeration — core raises `ValueError` (HTTP 400) without an identifier.
- JWT algorithm confusion — `algorithms=["HS256"]` pinned; constant-time admin key comparison.

## References

- CWE-639: https://cwe.mitre.org/data/definitions/639.html
- OWASP API1:2023 BOLA: https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/
- OWASP API5:2023 BFLA: https://owasp.org/API-Security/editions/2023/en/0xa5-broken-function-level-authorization/
