"""Loopback-only synthetic source. Pass an explicitly generated MP4 asset.

No user account, provider scraping, playback mock, system proxy or firewall rule.
Run: python test_support/emulator_fixture_server.py <synthetic.mp4> <evidence-dir>
"""
import hashlib, http.server, json, pathlib, re, struct, sys, time, urllib.parse, zlib
media=pathlib.Path(sys.argv[1]).resolve()
out=pathlib.Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
assert media.is_file()
def chunk(kind,data): return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data)&0xffffffff)
poster=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',160,240,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(b'\0'+bytes([45,110,75])*160 for _ in range(240))))+chunk(b'IEND',b'')
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,fmt,*args):
        with (out/'fixture-http.jsonl').open('a',encoding='utf-8') as f:
            f.write(json.dumps({'time':time.time(),'request':self.path,'message':fmt%args})+'\n')
    def do_GET(self):
        uri=urllib.parse.urlparse(self.path)
        if uri.path=='/poster.png': data=poster;content='image/png'
        elif uri.path=='/search':
            secondary='secondary' in self.path
            data=('<html><article><a href="/catalog-'+('b' if secondary else 'a')+'">Fixture 1</a></article></html>').encode();content='text/html'
        elif uri.path in ('/catalog-a','/catalog-b'):
            numbers=range(1,202) if uri.path.endswith('a') else reversed(range(1,202))
            data=('<html><div class="road">'+''.join(f'<a href="/play/{i}">EP{i}</a>' for i in numbers)+'</div><div class="road">'+''.join(f'<a href="/play/alternate/{i}">EP{i}</a>' for i in reversed(range(1,202)))+'</div></html>').encode();content='text/html'
        elif uri.path.startswith('/play/'):
            data=(f'<html><body><video controls autoplay muted src="http://10.0.2.2:18791/tracks.mp4?episode={uri.path.split("/")[-1]}"></video></body></html>').encode();content='text/html'
        elif uri.path=='/tracks.mp4':
            size=media.stat().st_size;start=0;end=size-1
            if self.headers.get('Range'):
                match=re.fullmatch(r'bytes=(\d*)-(\d*)',self.headers['Range'])
                if not match or not any(match.groups()):self.send_error(400);return
                left,right=match.groups()
                if not left:start=max(0,size-int(right))
                else:start=int(left);end=min(int(right),end) if right else end
                if start>=size or start>end:
                    self.send_response(416);self.send_header('Content-Range',f'bytes */{size}');self.send_header('Content-Length','0');self.end_headers();return
            self.send_response(206 if self.headers.get('Range') else 200)
            self.send_header('Content-Type','video/mp4');self.send_header('Accept-Ranges','bytes')
            self.send_header('Content-Length',str(end-start+1))
            if self.headers.get('Range'): self.send_header('Content-Range',f'bytes {start}-{end}/{size}')
            self.end_headers()
            try:
                with media.open('rb') as f: f.seek(start);self.wfile.write(f.read(end-start+1))
            except (BrokenPipeError,ConnectionResetError):pass
            return
        else: self.send_error(404);return
        self.send_response(200);self.send_header('Content-Type',content);self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
(out/'fixture-media.json').write_text(json.dumps({'path':str(media),'sha256':hashlib.sha256(media.read_bytes()).hexdigest(),'bytes':media.stat().st_size,'synthetic':True,'bind':'127.0.0.1:18791'},indent=2)+'\n',encoding='utf-8')
http.server.ThreadingHTTPServer(('127.0.0.1',18791),Handler).serve_forever()
