# What the bug is, in plain terms

Companion to [`2026-11-18-mem0-tenant-isolation.md`](2026-11-18-mem0-tenant-isolation.md). No security background needed.

## Simple version

mem0 stores memories in one big shared table. Each record carries an owner tag — `user_id=alice`, `user_id=bob`. The server checks **who you are** but never checks **that the record is yours**.

Hotel analogy: reception verifies you have a room key, then lets you open any door in the building. You only need to know the room number.

## The bug in three lines

```
GET /memories                     -> 403  "Admin role required"   (door locked)
GET /memories?user_id=alice       -> 200  alice's private data    (locked only if you don't name the room)
```

Same key, same server. The only difference: you typed someone else's name.

## How it is misused

1. Hold any normal tenant key — sign up, or be a low-privilege user of the instance.
2. Ask for the tenant list: `GET /entities` -> `alice_tenant`, `bob_tenant`, and memory counts.
3. Read her namespace: `GET /memories?user_id=alice_tenant` -> memories in plaintext.
4. Read one record: `GET /memories/{id}` -> full record.
5. Read the audit trail: `GET /memories/{id}/history` -> what changed, when.
6. Search her data: `POST /search {"query":"password","filters":{"user_id":"alice_tenant"}}`.
7. Overwrite: `PUT /memories/{id} {"text":"..."}` -> her assistant now believes attacker text.
8. Delete: `DELETE /memories/{id}` -> her context gone.

Eight requests, plain `curl`, no admin rights, no exploit framework.

## Why it matters

- Memories are not metadata. People paste PII, credentials, API tokens, medical and legal details into assistants; all of it becomes readable.
- Write access is worse than read: poison a memory and the victim's assistant acts on attacker-controlled "facts" — support bot, finance assistant, health assistant.
- Multi-tenant deployments collapse: one instance, many customers, tenant A reads tenant B.

## What it is not

- Requires a valid key with `role=user`; not anonymous, not zero-auth.
- Does not grant admin, shell, or database access — it reaches every tenant's memory data, which is the sensitive payload in this product.
- Not a scanner false positive: the 403/200 pair on the same credential is the proof.

## Fix, in one paragraph

Derive the namespace from the authenticated key (e.g. `User.tenant_id`) and reject any request whose `user_id` / `agent_id` / `run_id` differs. For `/memories/{id}`, load the record and check its stored owner before returning, updating, deleting, or serving history. Restrict `GET /entities` to admins or filter it to the caller's own entities. Apply the same binding to `/search`.

## Where the evidence lives

- `evidence/01_cross_tenant_read.txt` — read proof
- `evidence/02_entities_search_config.txt` — enumeration, search, `/configure`
- `evidence/03_write_delete_capability.txt` — overwrite and delete
- `evidence/04_exploit_transcript.{json,txt}` — 14-assertion run, request ids, UTC timestamps
- `poc/exploit.py` — harness (exit 0 only on full confirmation)
