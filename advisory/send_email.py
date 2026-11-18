#!/usr/bin/env python3
"""Send the mem0 disclosure email over SMTP (STARTTLS 587 or SSL 465).

ponytail: stdlib only, no msmtp dependency, one file.

Usage:
  SMTP_HOST=smtp.gmail.com SMTP_PORT=587 SMTP_USER=you@gmail.com SMTP_PASS=<app-password> \
    python3 advisory/send_email.py [--log evidence/06_email_sent.txt]

Env:
  SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS MAIL_FROM MAIL_TO
  (MAIL_FROM defaults to SMTP_USER, MAIL_TO to support@mem0.ai)

Prints the SMTP acceptor line and final status; never prints the password.
Exit: 0 sent, 2 missing config, 1 SMTP failure.
"""
from __future__ import annotations
import os, smtplib, ssl, sys, time
from email.message import EmailMessage
from email.utils import formatdate, make_msgid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BODY = ROOT / "advisory" / "email-to-security.txt"
ATTACH = [ROOT / "report.md", ROOT / "evidence" / "04_exploit_transcript.txt", ROOT / "poc" / "exploit.py"]

host = os.environ.get("SMTP_HOST", "")
port = int(os.environ.get("SMTP_PORT", "587"))
user = os.environ.get("SMTP_USER", "")
pw = os.environ.get("SMTP_PASS", "")
sender = os.environ.get("MAIL_FROM", user)
to = os.environ.get("MAIL_TO", "support@mem0.ai")
log_path = None
if "--log" in sys.argv:
    log_path = Path(sys.argv[sys.argv.index("--log") + 1])

if not (host and user and pw and sender):
    print("missing config: set SMTP_HOST SMTP_USER SMTP_PASS (MAIL_FROM optional)", file=sys.stderr)
    sys.exit(2)

raw = BODY.read_text()
lines = raw.splitlines()
subject = "SECURITY: Mem0 vulnerability report"
if lines and lines[0].startswith("Subject:"):
    subject = lines[0].split(":", 1)[1].strip()
body = "\n".join(l for l in lines if not l.startswith(("To:", "Subject:"))).lstrip("\n")

msg = EmailMessage()
msg["From"], msg["To"], msg["Subject"] = sender, to, subject
msg["Date"], msg["Message-ID"] = formatdate(localtime=False), make_msgid(domain=sender.split("@")[-1])
msg.set_content(body)
for p in ATTACH:
    if not p.exists():
        print(f"missing attachment {p}", file=sys.stderr); sys.exit(2)
    msg.add_attachment(p.read_bytes(), maintype="application", subtype="octet-stream", filename=p.name)

ctx = ssl.create_default_context()
t0 = time.time()
try:
    if port == 465:
        srv = smtplib.SMTP_SSL(host, port, context=ctx, timeout=30)
    else:
        srv = smtplib.SMTP(host, port, timeout=30)
        srv.ehlo(); srv.starttls(context=ctx); srv.ehlo()
    with srv:
        srv.login(user, pw)
        refused = srv.send_message(msg)
    status = "sent" if not refused else f"partial: {refused}"
except Exception as e:
    print(f"SMTP failure: {type(e).__name__}: {e}", file=sys.stderr); sys.exit(1)

out = (f"utc={time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n"
       f"host={host}:{port} from={sender} to={to} subject={subject}\n"
       f"attachments={[p.name for p in ATTACH]}\nstatus={status} elapsed_s={time.time()-t0:.1f}\n")
print(out, end="")
if log_path:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(out)
