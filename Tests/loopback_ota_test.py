"""Run the real ObjC/GCDWebServer implementation; only synthetic IPA-shaped bytes."""
import pathlib
import selectors
import socket
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from urllib.parse import urlsplit

with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    payload = b'PK' + bytes(range(256)) * 128
    source = root / 'fixture.ipa'
    source.write_bytes(payload)
    stop = root / 'stop'
    process = subprocess.Popen([sys.argv[1], str(source), str(stop)], stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True)
    try:
        ready = selectors.DefaultSelector()
        ready.register(process.stdout, selectors.EVENT_READ)
        assert ready.select(10), 'Loopback did not become ready'
        line = process.stdout.readline().strip()
        assert line.startswith('HTTP_READY '), line
        endpoint = line.split(' ', 1)[1]
        parts = urlsplit(endpoint)
        assert parts.hostname == '127.0.0.1' and parts.port > 0 and parts.path.endswith('/app.ipa') and len(parts.path.split('/')[1]) == 36
        origin = f'http://127.0.0.1:{parts.port}'
        # Proxy settings must not send loopback requests outside the host.
        client = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with client.open(endpoint, timeout=5) as response:
            assert response.status == 200 and response.read() == payload
        request = urllib.request.Request(endpoint, headers={'Range': 'bytes=3-9'})
        with client.open(request, timeout=5) as response:
            assert response.status == 206 and response.read() == payload[3:10]
            assert response.headers['Content-Range'] == f'bytes 3-9/{len(payload)}'
        with client.open(urllib.request.Request(endpoint, method='HEAD'), timeout=5) as response:
            assert response.read() == b'' and int(response.headers['Content-Length']) == len(payload)
        for path in ['/', '/fixture.ipa', '/cert.p12', '/missing', '/health/extra']:
            try:
                client.open(origin + path, timeout=5)
                raise AssertionError('Unexpected exposed route ' + path)
            except urllib.error.HTTPError as error:
                assert error.code == 404, (path, error.code)
        stop.touch()
        output, _ = process.communicate(timeout=5)
        assert process.returncode == 0 and 'HTTP_STOPPED' in output, output
        with socket.socket() as connection:
            connection.settimeout(1)
            assert connection.connect_ex(('127.0.0.1', parts.port)) != 0, 'Listener stayed open'
        assert source.read_bytes() == payload
        print('PASS: actual loopback server full/range/HEAD transfers, route isolation, stop and unchanged IPA')
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
