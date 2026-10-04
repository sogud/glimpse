"""Isolated HTTP tests: synthetic image only; no Photos or LM Studio access."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread


requests = []


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.respond()

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.respond()

    def respond(self):
        requests.append((self.command, self.path))
        if self.path == "/api/v1/models":
            self.send_response(200)
            body = json.dumps({"models": [
                {"type": "llm", "key": "fixture-vision", "display_name": "Fixture Vision",
                 "capabilities": {"vision": True}, "loaded_instances": [{"id": "test"}]},
                {"type": "llm", "key": "unloaded-vision", "display_name": "Unloaded Vision",
                 "capabilities": {"vision": True}, "loaded_instances": []},
                {"type": "llm", "key": "text-only", "display_name": "Text Model",
                 "capabilities": {"vision": False}, "loaded_instances": [{"id": "text"}]},
                {"type": "embedding", "key": "embedding", "display_name": "Embedding", "loaded_instances": []},
            ]}).encode()
        elif self.path.startswith("/redirect/"):
            self.send_response(307)
            self.send_header("Location", f"http://127.0.0.1:{self.server.server_port}/destination")
            body = b"redirect blocked"
        elif self.path.startswith("/error/") or self.path.startswith("/native-error/"):
            self.send_response(400)
            body = b'{"error":"MODEL_NOT_LOADED"}'
        elif self.path.startswith("/missing-category/"):
            self.send_response(200)
            body = json.dumps({"choices": [{"message": {"content": json.dumps({"reason": "fixture"})}}]}).encode()
        elif self.path.startswith("/success/"):
            self.send_response(200)
            if self.path.endswith("/models"):
                body = json.dumps({"data": [{"id": "test"}]}).encode()
            else:
                body = json.dumps({"choices": [{"message": {"content": json.dumps({
                    "category": "ordinary:pets", "reason": "synthetic cat",
                })}}]}).encode()
        else:
            self.send_response(200)
            body = json.dumps({"data": [{"id": "qwen3-vl-test"}]}).encode()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    environment = dict(os.environ, GLIMPSE_TEST_ENDPOINT=f"http://127.0.0.1:{server.server_port}")
    result = subprocess.run(
        ["swift", "run", "GlimpsePhotosCLIChecks"],
        cwd=Path(__file__).resolve().parents[1], env=environment, timeout=90,
    )
    assert result.returncode == 0, "Swift checks failed"
    with tempfile.TemporaryDirectory(prefix="glimpse-native-checks-") as temporary:
        executable = str(Path(temporary) / "native-model-checks")
        subprocess.run(["swiftc", "Sources/SmartCore/LocalPhotoClassificationCore.swift", "MacApp/LMStudioClient.swift",
                        "Tests/NativeModelChecks.swift", "-o", executable], check=True,
                       cwd=Path(__file__).resolve().parents[1], timeout=60)
        subprocess.run([executable], env=environment, check=True, timeout=20)
    assert requests == [
        ("GET", "/redirect/models"),
        ("POST", "/redirect/chat/completions"),
        ("POST", "/error/chat/completions"),
        ("POST", "/missing-category/chat/completions"),
        ("GET", "/error/models"),
        ("GET", "/success/models"),
        ("POST", "/success/chat/completions"),
        ("POST", "/native-error/chat/completions"),
        ("GET", "/api/v1/models"),
        ("GET", "/api/v1/models"),
        ("GET", "/api/v1/models"),
    ], f"Unexpected requests (redirect or retry): {requests}"
    print("Transport checks passed: no redirects, one inference attempt per image, original server errors preserved")
finally:
    server.shutdown()
    server.server_close()
    thread.join()
