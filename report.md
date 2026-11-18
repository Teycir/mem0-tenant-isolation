# mem0 Self-Hosted REST API — Broken Tenant Isolation on Memory Endpoints

## Report metadata

| Field | Value |
|---|---|
| Target | mem0 OSS repo `Teycir/…` local checkout `/home/teycir/ResearchAIRedTeam/mem0` @ `f1791da` (mem0ai 2.2.1, FastAPI 0.138.1, uvicorn 0.38.0) |
| Engagement dir | `/home/teycir/BugBounty/mem0/20261118/20261118_182222` |
| Generated (UTC) | 2026-11-18T18:25:09Z |
| Scope | `server/` REST API + `mem0/` core, self-hosted with pgvector (`pgvector/pgvector:pg17`), auth enabled (`AUTH_DISABLED=false`) |
| Status | FINAL — all claims reproduced live on 2026-11-18 |

## 1. Executive Summary

### 1.1 Background
Assessed the self-hosted mem0 REST API (`server/main.py`) with authentication enabled. Objective: determine whether the API enforces per-tenant (per `user_id`/`agent_id`/`run_id`) isolation when multiple principals share one deployment.

### 1.2 Overall Posture
Authentication is sound (bcrypt API keys, HS256-pinned JWTs, timing-safe admin key compare). **Authorization is not.** The API treats every authenticated principal as authorized for every memory namespace:

- `GET /entities` returns every `user_id`/`agent_id`/`run_id` in the store to **any** authenticated key, regardless of role — a complete tenant directory.
- Every memory endpoint (`GET/PUT/DELETE /memories/{id}`, `GET .../history`, `POST /search`, `GET /memories?user_id=…`) accepts an attacker-chosen namespace and performs **no ownership or role check**. A `role=user` key can read, overwrite, and delete another tenant's memories by ID or by namespace.
- The server never consumes the client-side `Mem0-User-ID` header; isolation is entirely delegated to client goodwill.

Only unfiltered `/memories` listing is role-gated (403 for `role=user`), which is trivially bypassed by supplying `?user_id=<victim>`. Systemic, not symptomatic: the fix requires a shared authorization layer, not per-endpoint patches.

### 1.3 Risk Profile

| ID | Severity | CVSS 3.1 | CWE | Title |
|----|----------|----------|-----|-------|
| RT-01 | High | 8.8 | CWE-639 | Cross-tenant read/write/delete of memories via unscoped endpoints |
| RT-02 | Medium | 4.3 | CWE-200 | `/configure` discloses internal infrastructure and non-redacted credential keys to any user |
| RT-03 | Low | 4.3 | CWE-770 | No rate limit or body cap on memory endpoints; 10k-row scan per `/entities` call |

Overall: **High** (8.8). Confidentiality loss includes user PII/secrets stored as memories; integrity loss allows silent poisoning of another tenant's agent context; deletion destroys tenant data.

### 1.4 Recommendation Summary
1. RT-01 — bind namespace to the authenticated principal (server-side tenant map or store-level ACL) and reject mismatched `user_id`/`agent_id`/`run_id`; add ownership checks on `/memories/{id}` CRUD and `/history`; restrict `/entities` to admin or scope it to the caller. **P0**
2. RT-02 — return infra/credential config to `require_admin` only; switch redaction to suffix/substring matching (`*secret*`, `*key*`, `*token*`, `*password*`, `*credentials*`). **P1**
3. RT-03 — per-principal rate limits on `/memories`, `/search`, `/entities`; cap `top_k`/`SCAN_LIMIT`; enforce request-body size. **P2**

## 2. Scope & Methodology
- In-scope: `server/` (main.py, auth.py, routers/{auth,entities,api_keys}.py, models.py, db.py, alembic), `mem0/memory/main.py`, `mem0/vector_stores/pgvector.py`, `mem0/vector_stores/redis.py`, `mem0/client/main.py`, dashboard auth middleware.
- Out of scope: hosted mem0 platform, third-party LLM providers, dependency CVEs.
- Constraints: non-destructive testing; write/delete proof performed only against a synthetic throwaway memory named `throwaway-poc-record`, never against tenant-like data.
- Methodology (PTES): static review → environment build (pgvector + stub OpenAI) → live exploitation with two principals (`admin`, `role=user`) → evidence capture → reporting.

## 3. Findings Summary

| ID | Severity | CVSS 3.1 | CWE | Title | Status |
|----|----------|----------|-----|-------|--------|
| RT-01 | High | 8.8 | CWE-639 | Cross-tenant read/write/delete of memories via unscoped endpoints | Confirmed |
| RT-02 | Medium | 4.3 | CWE-200 | `/configure` discloses internal infra + non-redacted credential keys | Confirmed |
| RT-03 | Low | 4.3 | CWE-770 | No rate limiting / unbounded scans on memory endpoints | Confirmed |

## 4. Findings Detail

### RT-01 — Broken object/tenant authorization in memory endpoints allows any authenticated user to read, alter and delete other tenants' memories

- **Severity:** High
- **CVSS 3.1:** 8.8 — https://www.first.org/cvss/calculator/3.1#CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H
- **CWE:** CWE-639 (Authorization Bypass Through User-Controlled Key); CWE-284
- **Affected URL/Area:** `GET /entities`, `GET /memories?user_id=`, `GET/PUT/DELETE /memories/{memory_id}`, `GET /memories/{memory_id}/history`, `POST /search`
- **Difficulty to exploit:** Low
- **Authentication required:** Yes (any `role=user` API key)
- **User interaction required:** No
- **Verified at (UTC):** 2026-11-18T18:21:57Z (seed), 2026-11-18T18:22:33Z (read), 2026-11-18T18:23:00Z (write/delete)

#### Issue Description
`server/routers/entities.py:45` (`list_entities`) and `server/main.py:444-524` guard every memory operation with `verify_auth` only. `verify_auth` authenticates the caller but returns a `User` that no handler ever compares against the namespace being operated on:

- `GET /entities` (entities.py:45-75) calls `vector_store.list(top_k=10_000)` and aggregates **every** distinct `user_id`/`agent_id`/`run_id` — a global tenant directory for any key.
- `GET /memories` (main.py:411-441) role-gates only the *unfiltered* branch; as soon as `user_id`/`agent_id`/`run_id` is supplied the request goes to `memory.get_all(filters=…)` with zero role or ownership check.
- `GET /memories/{memory_id}`, `PUT`, `DELETE`, `.../history` (main.py:443-524) pass the caller-supplied ID straight to `memory.get/update/delete/history`; core `mem0/memory/main.py:1222-1267` resolves by ID alone (`_get_memory_by_id`) without a scope predicate.
- `POST /search` (main.py:452-485) forwards attacker-controlled `filters` to core `search()`; core only requires *some* identifier to be present (main.py1389-1400, `ValueError` otherwise) — it never checks that the identifier belongs to the caller.

The only scoping signal the client sends is the `Mem0-User-ID` header (`mem0/client/main.py` `_client_headers`, ~L196), which the server never reads (no reference to that header anywhere under `server/`). Isolation therefore depends entirely on well-behaved clients.

#### Attack Scenario
A SaaS built on one self-hosted mem0 instance issues one API key per customer tenant. Tenant B (low-value subscriber) calls `GET /entities`, receives `alice_tenant`, then `GET /memories?user_id=alice_tenant` and reads Alice's stored facts — here an SSN and an API token. B then walks `GET /memories/{id}` and `/history` for full records, uses `POST /search` with `filters={"user_id":"alice_tenant"}` to mine everything semantically, and can `PUT` poisoned facts (prompt injection into Alice's agent context) or `DELETE` her records. All of it returns HTTP 200 with no audit-visible distinction from legitimate traffic.

#### Steps to Reproduce / PoC
Prereqs: mem0 server running with `AUTH_DISABLED=false`; Postgres+pgvector; one `role=user` API key (issued to the attacker tenant). Full script: `pocs/poc_cross_tenant.sh`.

1. Seed a victim namespace (as any writer): `POST /memories {"messages":[{"role":"user","content":"…"}],"user_id":"alice_tenant","infer":false}` → 200.
2. As the **low-privilege** `role=user` key: `GET /entities` → 200, lists `alice_tenant` and `bob_tenant`.
3. `GET /memories?user_id=alice_tenant` with the same key → 200, returns Alice's memory verbatim.
4. `GET /memories/1bd03115-79b1-4d66-aa2a-452a3209f071` → 200.
5. `GET /memories/1bd03115-…/history` → 200, full mutation history.
6. `POST /search {"query":"alice","filters":{"user_id":"alice_tenant"},"threshold":0}` → 200, returns victim record.
7. `PUT /memories/{id} {"text":"overwritten-by-lowpriv-key"}` → 200; subsequent `GET` shows attacker content.
8. `DELETE /memories/{id}` → 200; `GET` then 404.
9. Negative control: `GET /memories` with no identifier as `role=user` → **403** (proves the role gate exists but is bypassed by step 3).

#### Request
```http
GET /entities HTTP/1.1
X-API-Key: m0sk_K7bJpM-R4SuIla69lIHUsvahWkrCsfx1jyxuDOOJEWo
```
```http
GET /memories?user_id=alice_tenant HTTP/1.1
X-API-Key: m0sk_K7bJpM-R4SuIla69lIHUsvahWkrCsfx1jyxuDOOJEWo
```
```http
DELETE /memories/18aae2cc-c72b-4e0e-b2c9-a490ce9210ac HTTP/1.1
X-API-Key: m0sk_K7bJpM-R4SuIla69lIHUsvahWkrCsfx1jyxuDOOJEWo
```

#### Response
```http
HTTP/1.1 200 OK
date: Wed, 18 Nov 2026 18:22:45 GMT
content-type: application/json
x-request-id: 2c6c4944

[{"id":"alice_tenant","type":"user","total_memories":1,...},{"id":"bob_tenant","type":"user","total_memories":1,...}]
```
```http
HTTP/1.1 200 OK
date: Wed, 18 Nov 2026 18:22:23 GMT
x-request-id: 6d0c2e3b

{"results":[{"id":"1bd03115-79b1-4d66-aa2a-452a3209f071","memory":"Tenant Alice private: SSN 123-45-6789, API token sk-alice-secret","user_id":"alice_tenant",...}]}
```
```http
HTTP/1.1 200 OK
date: Wed, 18 Nov 2026 18:23:00 GMT
x-request-id: 1c36a2bc

{"message":"Memory deleted successfully"}
```

#### Evidence artifacts
| Path | sha256 |
|---|---|
| `evidence/01_cross_tenant_read.txt` | `050c8567391cebc8a868d5692767020787e181bbf1652a74891b0f59f850f5a5` |
| `evidence/02_entities_search_config.txt` | `62a58936ec1ee32f73c42eb9d31aa4a2e8007799214f2d9e3a3f45b60342bc62` |
| `evidence/03_write_delete_capability.txt` | `9c079a2d7d37715d730a46332b03f89da014bd962f40d1c5d0dbcc23248e2958` |
| `pocs/poc_cross_tenant.sh` | `2781f32624109d723dad5f0191ccbcc7f26062e8a44154a2d237346a89d3f932` |

Key verbatim outputs: low-priv `GET /entities` → `200` listing `alice_tenant`; `GET /memories?user_id=alice_tenant` → `200` with `"memory":"Tenant Alice private: SSN 123-45-6789, API token sk-alice-secret"`; `GET /memories/{id}` → `200`; `/history` → `200`; `PUT` → `200` then `GET` returns `overwritten-by-lowpriv-key`; `DELETE` → `200`; control `GET /memories` → `403`.

#### Impact
Any holder of a valid API key — including the lowest-privilege `role=user` tenant — can enumerate every namespace on the instance, read all stored memories (often PII, credentials, business context), silently poison records consumed by other tenants' agents, and delete them. This breaks the fundamental multi-tenant guarantee of a memory service: confidentiality, integrity and availability of all tenants on a shared deployment. There is no audit distinction between the attack and legitimate traffic; the response is identical to an owner's request.

#### Affected Demographic
Every self-hosted mem0 deployment with `AUTH_DISABLED=false` and more than one principal sharing the instance (multi-tenant SaaS, internal platform with per-team keys, agencies hosting customer agents). Single-user local setups are unaffected in practice.

#### Recommended Fix
Primary: derive the namespace from the authenticated principal server-side (e.g. `User.tenant_id`) and **reject** requests whose `user_id`/`agent_id`/`run_id` do not match; for `/memories/{memory_id}` and `/history`, load the memory and assert the stored `user_id` is in the caller's allowed set before acting. Restrict `GET /entities` to `require_admin` (or filter the aggregation to the caller's entities) and require `require_admin` for cross-namespace search. Treat the `Mem0-User-ID` header as untrusted input, never as scope. Quick mitigation: gate all memory routes behind `require_admin` until tenant binding exists (breaks multi-tenant use but stops the exposure). Defense-in-depth: per-key namespace allowlist, structured audit log of `(principal, namespace, action)`, and a regression test asserting `role=user` gets 403/404 on a foreign `user_id`.

#### References
- CWE-639: https://cwe.mitre.org/data/definitions/639.html
- CWE-284: https://cwe.mitre.org/data/definitions/284.html
- OWASP API1:2023 Broken Object Level Authorization — https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/
- OWASP API5:2023 Broken Function Level Authorization — https://owasp.org/API-Security/editions/2023/en/0xa5-broken-function-level-authorization/

### RT-02 — `/configure` discloses internal infrastructure and non-redacted credential keys to any authenticated user

- **Severity:** Medium
- **CVSS 3.1:** 4.3 — https://www.first.org/cvss/calculator/3.1#CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N
- **CWE:** CWE-200
- **Affected URL/Area:** `GET /configure` (`server/main.py:322-324`, `_redact_config` at 222-229)
- **Difficulty to exploit:** Low
- **Authentication required:** Yes (any role)
- **User interaction required:** No
- **Verified at (UTC):** 2026-11-18T18:22:46Z

#### Issue Description
`GET /configure` depends on `verify_auth`, not `require_admin`, and redacts only keys contained in `SENSITIVE_CONFIG_KEYS = {admin_api_key, api_key, authorization, jwt_secret, password, password_hash, secret, token}` matched by **exact, lowercased key name** (`_redact_config`, main.py:227). Live response to a `role=user` key disclosed the vector-store topology — `host`, `port`, `dbname`, `user` — plus `history_db_path`. Any future/env-provided config with `aws_secret_access_key`, `aws_access_key_id`, `client_secret`, `private_key`, `credentials_path`, or `connection_string` would be returned in the clear because none match the whitelist.

#### Attack Scenario
A low-privilege tenant calls `/configure`, learns the internal Postgres host/port/user and DB name, and combines it with RT-01 to target the datastore directly if network access is later obtained (SSRF, sidecar, or same-VPC foothold). On deployments configured with AWS/Vertex credentials for Bedrock/Vertex embeddings — which the config schema supports — the secret itself is disclosed outright.

#### Steps to Reproduce / PoC
1. Authenticate with any `role=user` API key.
2. `GET /configure` → 200 with full provider config.
3. Observe `vector_store.config.password` redacted but `host`/`port`/`dbname`/`user` and `history_db_path` returned; note keys outside the exact-match list are unredacted.

#### Request
```http
GET /configure HTTP/1.1
X-API-Key: m0sk_K7bJpM-R4SuIla69lIHUsvahWkrCsfx1jyxuDOOJEWo
```

#### Response
```http
HTTP/1.1 200 OK
date: Wed, 18 Nov 2026 18:22:46 GMT
x-request-id: 1bd75662

{"version":"v1.1","vector_store":{"provider":"pgvector","config":{"host":"127.0.0.1","port":8432,"dbname":"postgres","user":"postgres","password":"[redacted]","collection_name":"mem0"}},"llm":{"provider":"openai","config":{"api_key":"[redacted]","temperature":0.2,"model":"gpt-5-mini"}},"embedder":{"provider":"openai","config":{"api_key":"[redacted]","model":"text-embedding-3-small"}},"history_db_path":"/tmp/mem0-poc/history.db"}
```

#### Evidence artifacts
`evidence/02_entities_search_config.txt` — sha256 `62a58936ec1ee32f73c42eb9d31aa4a2e8007799214f2d9e3a3f45b60342bc62`.

#### Impact
Infrastructure reconnaissance (internal DB endpoint, DB username, filesystem path) available to every authenticated tenant, and a latent credential-disclosure bug for any non-whitelisted secret key. Medium: no direct compromise, but meaningfully lowers the bar for chaining with RT-01 or network-level access.

#### Affected Demographic
All deployments with more than one principal; higher-impact where memory config carries cloud provider credentials (Bedrock/Vertex) rather than plain OpenAI keys.

#### Recommended Fix
Require `require_admin` on `GET /configure`; redact by substring/suffix match on the lowercased key (`any(k in key for k in ("secret","key","token","password","credential","authorization","private"))`); return a schema-level allowlist instead of the raw config; keep `history_db_path` server-side.

#### References
- CWE-200: https://cwe.mitre.org/data/definitions/200.html
- OWASP API3:2023 Broken Object Property Level Authorization — https://owasp.org/API-Security/editions/2023/en/0xa3-broken-object-property-level-authorization/

### RT-03 — No rate limiting or size cap on memory endpoints allows resource-exhaustion and cost DoS

- **Severity:** Low
- **CVSS 3.1:** 4.3 — https://www.first.org/cvss/calculator/3.1#CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:N/I:N/A:L
- **CWE:** CWE-770
- **Affected URL/Area:** `server/main.py:367-485` (all memory routes), `server/routers/entities.py:16` (`SCAN_LIMIT = 10_000`)
- **Difficulty to exploit:** Low
- **Authentication required:** Yes
- **User interaction required:** No
- **Verified at (UTC):** 2026-11-18T18:22:45Z

#### Issue Description
`@limiter.limit` is applied only to `/auth/login` and `/auth/register` (5/minute). `/memories`, `/search`, `/entities` and `/generate-instructions` have no per-principal throttle and no request-body limit; `GET /entities` performs a `vector_store.list(top_k=10_000)` scan on **every** call, and `/generate-instructions` triggers a billable LLM completion per request. A single key can therefore drive repeated 10k-row scans and unbounded LLM calls.

#### Attack Scenario
One tenant loops `/entities` (each call scans 10k rows and aggregates in Python) or `/generate-instructions` (one paid model call each), degrading the shared instance and inflating the operator's provider bill. Combined with RT-01, the attacker can also target a victim's namespace with repeated unthresholded `/search` calls.

#### Steps to Reproduce / PoC
1. Authenticate with any key.
2. Send N rapid requests to `GET /entities` or `POST /generate-instructions`; observe all return 200 with no 429 and no throttle.
3. Note `GET /entities` response time scales with store size (10k-row scan per call in `_iter_payloads`).

#### Request
```http
POST /generate-instructions HTTP/1.1
X-API-Key: <any valid key>
Content-Type: application/json

{"use_case":"repeat-me"}
```

#### Response
```http
HTTP/1.1 200 OK
(no 429 observed across rapid repeats; each call performs one LLM completion)
```

#### Evidence artifacts
Observed during the same live session as `evidence/02_entities_search_config.txt` (sha256 `62a58936…bc62`); no rate-limit headers, no 429 across repeated `/entities` calls.

#### Impact
Availability degradation and unbounded third-party LLM spend on a shared instance; an authenticated low-privilege tenant can impose cost on the operator. Low severity: no data exposure beyond RT-01.

#### Affected Demographic
Operators running shared mem0 instances with metered LLM/embedding providers.

#### Recommended Fix
Add `slowapi` limits keyed by API key on all memory/config routes; cap `top_k` and replace the 10k `list()` scan in `/entities` with a SQL `DISTINCT` query; enforce a request-body size limit at the proxy; add per-key monthly token budgets for `/generate-instructions`.

#### References
- CWE-770: https://cwe.mitre.org/data/definitions/770.html
- OWASP API4:2023 Unrestricted Resource Consumption — https://owasp.org/API-Security/editions/2023/en/0xa4-unrestricted-resource-consumption/

## 5. Appendix

### 5.1 Evidence inventory
| Path | sha256 |
|---|---|
| `evidence/01_cross_tenant_read.txt` | `050c8567391cebc8a868d5692767020787e181bbf1652a74891b0f59f850f5a5` |
| `evidence/02_entities_search_config.txt` | `62a58936ec1ee32f73c42eb9d31aa4a2e8007799214f2d9e3a3f45b60342bc62` |
| `evidence/03_write_delete_capability.txt` | `9c079a2d7d37715d730a46332b03f89da014bd962f40d1c5d0dbcc23248e2958` |
| `pocs/poc_cross_tenant.sh` | `2781f32624109d723dad5f0191ccbcc7f26062e8a44154a2d237346a89d3f932` |

Test fixtures: victim namespace `alice_tenant` (memory `1bd03115-79b1-4d66-aa2a-452a3209f071`), second tenant `bob_tenant` (`e3e0203b-…`), low-privilege user `f852e738-3b79-4612-965b-5e2a24c57076` (`role=user`, key prefix `m0sk_K7bJpM-`), throwaway record `18aae2cc-c72b-4e0e-b2c9-a490ce9210ac`.

### 5.2 Tools used
mem0 @ `f1791da` (mem0ai 2.2.1), FastAPI 0.138.1, uvicorn 0.38.0, Starlette 1.3.1, `pgvector/pgvector:pg17` (Docker 29.10.0), Alembic migrations 001–006, Python 3.12 venv, curl, sha256sum.

### 5.3 Falsified / refuted items
- **SQL injection in pgvector filters** — refuted. `_build_filter_conditions` (`mem0/vector_stores/pgvector.py`) uses `%s` placeholders with `psycopg.sql` composition; values never interpolated. A malformed operator is rejected, not concatenated.
- **Empty-filter enumeration via `/search`** — refuted. Core `search()` raises `ValueError` (→ HTTP 400) when no `user_id`/`agent_id`/`run_id` is supplied; enumeration must go through `/entities` (RT-01).
- **JWT algorithm confusion / auth bypass** — refuted. `jose.jwt.decode(..., algorithms=["HS256"])` pinned; API keys bcrypt-verified after 12-char prefix lookup; `ADMIN_API_KEY` compared with `secrets.compare_digest`; login uses `dummy_verify_password()` to avoid a timing oracle.
- **Host-header SSRF via dashboard `getServerApiUrl()`** — refuted. URL is env-only, host header unused.
- **Unfiltered `/memories` listing as `role=user`** — correctly blocked (403); recorded as the negative control that makes the `?user_id=` bypass meaningful.
