"""Loopback controlled samples for this task's isolated AVD only.

Never use on a real device or mistake these samples for real anime. Production
rules, WebView extraction and MPV remain real; catalog metadata/images are test
data. Pass the existing synthetic MP4 explicitly; no media is downloaded.
Run: python test_support/emulator_fixture_server.py <synthetic.mp4> <new-evidence-dir>
"""
import argparse
import colorsys
import functools
import hashlib
import http.server
import json
import pathlib
import re
import struct
import threading
import time
import urllib.parse
import zlib

PORT = 18801
BASE = f'http://10.0.2.2:{PORT}'
CATALOG_SIZE = 96
LARGE_POSTER_DELAY_SECONDS = 1.0
TASK_ROOT = pathlib.Path(__file__).resolve().parents[2]
EXPECTED_TASK_ROOT = pathlib.Path(r'C:\Users\hentai\Documents\Codex\2026-10-02\task').resolve()


def chunk(kind, data):
    return (struct.pack('!I', len(data)) + kind + data
            + struct.pack('!I', zlib.crc32(kind + data) & 0xffffffff))


@functools.lru_cache(maxsize=CATALOG_SIZE * 2)
def poster_png(subject_id, large=False):
    """Deterministic distinct hues/geometry, using only Python's standard lib."""
    width, height = (320, 480) if large else (160, 240)
    hue = ((subject_id - 1) * 137.508 % 360) / 360
    base = tuple(int(channel * 255) for channel in colorsys.hsv_to_rgb(hue, 0.65, 0.8))
    accent = tuple(int(channel * 255) for channel in colorsys.hsv_to_rgb((hue + 0.18) % 1, 0.5, 0.95))
    rows = []
    for y in range(height):
        row = bytearray(b'\0')
        for x in range(width):
            fade = 0.6 + 0.4 * y / (height - 1)
            diagonal = abs(x / width - y / height) < 0.09
            panel = width // 5 < x < width * 4 // 5 and height // 3 < y < height * 2 // 3
            circle = ((x - width * 0.72) / width) ** 2 + ((y - height * 0.23) / height) ** 2 < 0.018
            color = accent if diagonal or circle else base
            if panel:
                color = tuple(min(255, channel + 38) for channel in color)
            if large and height * 0.82 < y < height * 0.87:
                color = accent
            row.extend(int(channel * fade) for channel in color)
        rows.append(bytes(row))
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b''.join(rows)))
            + chunk(b'IEND', b''))


def sample_title(subject_id):
    return f'受控样本 {subject_id} · 本地界面验收'


def handler_for(media, out):
    log_lock = threading.Lock()

    def event(values):
        with log_lock, (out / 'fixture-http.jsonl').open('a', encoding='utf-8') as output:
            output.write(json.dumps(dict(time=time.time(), **values), ensure_ascii=False) + '\n')

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            event({'event': 'http', 'request': self.path, 'message': fmt % args})

        def send_bytes(self, data, content, *, no_cache=False):
            self.send_response(200)
            self.send_header('Content-Type', content)
            self.send_header('Content-Length', str(len(data)))
            if no_cache:
                self.send_header('Cache-Control', 'no-store, max-age=0')
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def do_GET(self):
            uri = urllib.parse.urlparse(self.path)
            parameters = urllib.parse.parse_qs(uri.query)
            poster_match = re.fullmatch(r'/(poster|more-poster)/(\d+)\.png', uri.path)
            if poster_match:
                subject_id = int(poster_match[2])
                if not 1 <= subject_id <= CATALOG_SIZE:
                    self.send_error(404)
                    return
                large = poster_match[1] == 'more-poster'
                delay = LARGE_POSTER_DELAY_SECONDS if large else 0
                event({'event': 'poster-request', 'request': self.path,
                       'subject_id': subject_id, 'large': large, 'delay_seconds': delay})
                if delay:
                    time.sleep(delay)  # Bounded server response delay, never UI/FFI.
                data = poster_png(subject_id, large)
                event({'event': 'poster-ready', 'request': self.path, 'subject_id': subject_id,
                       'large': large, 'sha256': hashlib.sha256(data).hexdigest()})
                self.send_bytes(data, 'image/png', no_cache=True)
                return
            if uri.path == '/poster.png':
                self.send_bytes(poster_png(1), 'image/png', no_cache=True)
                return
            if uri.path == '/search':
                keyword = parameters.get('q', [''])[0]
                identity = re.search(r'(?:受控样本|Fixture)\s*(\d+)', keyword)
                subject_id = min(CATALOG_SIZE, max(1, int(identity[1]))) if identity else 1
                secondary = 'secondary' in parameters.get('source', [''])[0]
                catalog = 'b' if secondary else 'a'
                data = (f'<html><article><a href="/catalog-{catalog}?subject={subject_id}">'
                        f'{sample_title(subject_id)}</a></article></html>')
                self.send_bytes(data.encode('utf-8'), 'text/html; charset=utf-8')
                return
            if uri.path in ('/catalog-a', '/catalog-b'):
                # Preserve both 201-episode roads and original page/episode IDs.
                numbers = range(1, 202) if uri.path.endswith('a') else reversed(range(1, 202))
                data = ('<html><div class="road">'
                        + ''.join(f'<a href="/play/{number}">EP{number}</a>' for number in numbers)
                        + '</div><div class="road">'
                        + ''.join(f'<a href="/play/alternate/{number}">EP{number}</a>'
                                  for number in reversed(range(1, 202)))
                        + '</div></html>')
                self.send_bytes(data.encode('utf-8'), 'text/html; charset=utf-8')
                return
            if uri.path.startswith('/play/'):
                data = (f'<html><body><video controls autoplay muted '
                        f'src="{BASE}/tracks.mp4?episode={uri.path.split("/")[-1]}">'
                        '</video></body></html>')
                self.send_bytes(data.encode('utf-8'), 'text/html; charset=utf-8')
                return
            if uri.path == '/tracks.mp4':
                size = media.stat().st_size
                start, end = 0, size - 1
                if self.headers.get('Range'):
                    match = re.fullmatch(r'bytes=(\d*)-(\d*)', self.headers['Range'])
                    if not match or not any(match.groups()):
                        self.send_error(400)
                        return
                    left, right = match.groups()
                    if not left:
                        start = max(0, size - int(right))
                    else:
                        start = int(left)
                        end = min(int(right), end) if right else end
                    if start >= size or start > end:
                        self.send_response(416)
                        self.send_header('Content-Range', f'bytes */{size}')
                        self.send_header('Content-Length', '0')
                        self.end_headers()
                        return
                self.send_response(206 if self.headers.get('Range') else 200)
                self.send_header('Content-Type', 'video/mp4')
                self.send_header('Accept-Ranges', 'bytes')
                self.send_header('Content-Length', str(end - start + 1))
                if self.headers.get('Range'):
                    self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
                self.end_headers()
                try:
                    with media.open('rb') as source:
                        source.seek(start)
                        self.wfile.write(source.read(end - start + 1))
                except (BrokenPipeError, ConnectionResetError):
                    pass
                return
            self.send_error(404)

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('synthetic_mp4', type=pathlib.Path)
    parser.add_argument('evidence_directory', type=pathlib.Path)
    args = parser.parse_args()
    media = args.synthetic_mp4.resolve()
    out = args.evidence_directory.resolve()
    if TASK_ROOT != EXPECTED_TASK_ROOT or not out.is_relative_to(TASK_ROOT):
        raise RuntimeError('Write evidence only under this new isolated task')
    if not media.is_file():
        raise FileNotFoundError(media)
    out.mkdir(parents=True, exist_ok=True)
    with http.server.ThreadingHTTPServer(('127.0.0.1', PORT), handler_for(media, out)) as server:
        server.daemon_threads = True
        (out / 'fixture-media.json').write_text(json.dumps({
            'path': str(media), 'sha256': hashlib.sha256(media.read_bytes()).hexdigest(),
            'bytes': media.stat().st_size, 'synthetic': True,
            'bind': f'127.0.0.1:{PORT}', 'catalog_size': CATALOG_SIZE,
            'large_poster_delay_seconds': LARGE_POSTER_DELAY_SECONDS,
            'scope': 'new isolated AVD only; controlled samples, not real anime'},
            ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        server.serve_forever()


if __name__ == '__main__':
    main()
