import hashlib, json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DIM = 1536

def embed(text: str):
    h = hashlib.sha256(text.encode()).digest()
    vec = []
    i = 0
    while len(vec) < DIM:
        b = h[i % len(h)]
        vec.append((b - 127.5) / 127.5)
        i += 1
    return vec

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n)
        try: req = json.loads(raw or b"{}")
        except Exception: req = {}
        if self.path.endswith("/embeddings"):
            inp = req.get("input")
            texts = inp if isinstance(inp, list) else [inp or ""]
            data = [{"object": "embedding", "index": i, "embedding": embed(str(t))} for i, t in enumerate(texts)]
            return self._send({"object": "list", "data": data, "model": req.get("model", "text-embedding-3-small"),
                               "usage": {"prompt_tokens": 1, "total_tokens": 1}})
        if self.path.endswith("/chat/completions"):
            content = json.dumps({"facts": ["stub-fact"]})
            return self._send({"id": "chatcmpl-stub", "object": "chat.completion", "created": 0,
                               "model": req.get("model", "gpt-4o-mini"),
                               "choices": [{"index": 0, "message": {"role": "assistant", "content": content},
                                            "finish_reason": "stop"}],
                               "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}})
        return self._send({"error": "not found"}, 404)

ThreadingHTTPServer(("127.0.0.1", 9999), H).serve_forever()
