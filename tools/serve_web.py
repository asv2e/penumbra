#!/usr/bin/env python3
"""Serves a built web folder with the headers the skwasm build wants.

    python3 tools/serve_web.py dist/web-skwasm [port]
"""
import functools
import http.server
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".mjs": "text/javascript"}

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "credentialless")
        super().end_headers()


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else "dist/web-skwasm"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8080
    handler = functools.partial(Handler, directory=root)
    print(f"Serving {root} on http://localhost:{port}")
    http.server.ThreadingHTTPServer(("", port), handler).serve_forever()
