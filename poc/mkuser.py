#!/usr/bin/env python3
"""Provision a low-privilege (role=user) principal + API key directly in the DB.

The public API only allows creating the first admin account, so a second principal
must be created the way an operator would: with a small provisioning script.

Usage: MEM0_SRC=/path/to/mem0 python3 mkuser.py [key_out_path]
Prints JSON {user_id, role, key_prefix, key}.
"""
import json
import os
import sys
import uuid
from datetime import datetime, timezone

MEM0_SRC = os.environ.get("MEM0_SRC", os.path.expanduser("~/ResearchAIRedTeam/mem0"))
sys.path.insert(0, os.path.join(MEM0_SRC, "server"))

from auth import generate_api_key, hash_password  # noqa: E402
from db import SessionLocal  # noqa: E402
from models import APIKey, User  # noqa: E402

out = sys.argv[1] if len(sys.argv) > 1 else "keyB.txt"

db = SessionLocal()
try:
    user = User(
        id=uuid.uuid4(),
        name="Low Priv",
        email="lowpriv@example.com",
        password_hash=hash_password("LowPrivPass123"),
        role="user",
        created_at=datetime.now(timezone.utc),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    full_key, prefix, key_hash = generate_api_key()
    db.add(
        APIKey(
            key_prefix=prefix,
            key_hash=key_hash,
            label="tenant-b-app",
            created_by=user.id,
            created_at=datetime.now(timezone.utc),
        )
    )
    db.commit()
finally:
    db.close()

with open(out, "w") as fh:
    fh.write(full_key)
print(json.dumps({"user_id": str(user.id), "role": user.role, "key_prefix": prefix, "key": full_key}))
