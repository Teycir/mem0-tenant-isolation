## MEM0-2026-02 — `GET /configure` information disclosure

### Summary
`GET /configure` depends on `verify_auth`, not `require_admin`, while `POST /configure` is
admin-gated. Any authenticated key, including `role=user`, receives the raw provider
configuration: vector-store `host`, `port`, `dbname`, `user`, plus `history_db_path`,
`model` and `collection_name`.

### Root cause
- `server/main.py:322-324`: `GET /configure` → `Depends(verify_auth)`; `POST /configure`
  (~L333) → `Depends(require_admin)`. The admin check was added to the write path only.
- `_redact_config` (`server/main.py:222-229`) redacts by **exact, lower-cased key name**
  against `SENSITIVE_CONFIG_KEYS = {admin_api_key, api_key, authorization, jwt_secret,
  password, password_hash, secret, token}`. Keys such as `aws_secret_access_key`,
  `aws_access_key_id`, `client_secret`, `private_key`, `credentials_path`,
  `connection_string` do not match and are returned in clear when configured.

### Proof (role=user key)
```http
GET /configure HTTP/1.1
X-API-Key: <role=user key>

HTTP/1.1 200 OK
{"version":"v1.1","vector_store":{"provider":"pgvector","config":{
  "host":"postgres","port":5432,"dbname":"mem0","user":"mem0", ...}},
 "history_db_path":"/app/history/history.db", ...}
```

### Impact
Internal datastore topology disclosed to any authenticated user; chains with MEM0-2026-01 to
target the database directly given any network foothold (SSRF, sidecar, same-VPC). On
deployments configured for Bedrock/Vertex, the provider secret itself is disclosed.

### Remediation
Require `require_admin` on `GET /configure`; redact by substring/suffix match
(`secret|key|token|password|credential|authorization|private`); return a schema allowlist
instead of raw config; keep `history_db_path` server-side.
