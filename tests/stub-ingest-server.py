#!/usr/bin/env python3
"""Stub Elyseum ingest server for the upload e2e.

Answers 201 to any POST and appends the request line, headers, and body
to the log file given as the second argument, so the e2e job can assert
the envelope (and the Authorization header) actually arrived. Also serves
GET /healthz for the readiness wait loop. Not part of the Action itself.
"""
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port, log_path = int(sys.argv[1]), sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        with open(log_path, "a") as log:
            log.write(f"{self.command} {self.path}\n")
            for key, value in self.headers.items():
                log.write(f"{key}: {value}\n")
            log.write("\n")
            log.write(body.decode("utf-8", "replace"))
            log.write("\n")
        self.send_response(201)
        self.end_headers()
        self.wfile.write(b'{"status":"created"}')

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", port), Handler).serve_forever()
