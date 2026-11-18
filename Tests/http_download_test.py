"""Serve bounded local fixtures; no external network or credentials are used."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import subprocess
import sys
import threading
import time

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path in ('/loop', '/redirect'):
            self.send_response(302)
            self.send_header('Location', '/loop' if self.path == '/loop' else '/small')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.path == '/failure':
            self.send_error(500)
            return
        self.send_response(200)
        if self.path in ('/small', '/empty', '/declared-large'):
            size = {'/small': 5, '/empty': 0, '/declared-large': 1_000}[self.path]
            self.send_header('Content-Length', str(size))
        self.end_headers()
        try:
            if self.path == '/small':
                self.wfile.write(b'hello')
            elif self.path == '/stream-large':
                self.wfile.write(b'x' * 1_000)
            elif self.path == '/slow':
                for _ in range(300):
                    self.wfile.write(b'x' * 1_024)
                    self.wfile.flush()
                    time.sleep(.01)
        except (BrokenPipeError, ConnectionResetError):
            pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    subprocess.run([sys.argv[1], f'http://127.0.0.1:{server.server_port}'], check=True, timeout=30)
finally:
    server.shutdown()
    server.server_close()
