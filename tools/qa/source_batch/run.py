"""Bounded, resumable emulator-only A/B runner. No physical-device override."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import statistics
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PACKAGE = 'com.znbsf.kazumi.fluttertv.parserqa'
ACTIVITY = 'com.example.kazumi.ParserQaActivity'
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'

def digest(data):
    return hashlib.sha256(data).hexdigest()

def paired_plan(cases, repeats):
    for repeat in range(repeats):
        for index, case in enumerate(cases):
            engines = ['webview', 'gecko'] if (index + repeat) % 2 == 0 else ['gecko', 'webview']
            for engine in engines:
                yield {**case, 'engine': engine, 'repeat': repeat, 'user_agent': UA}

def classified_stage(row):
    # The App service wraps dart:async's timeout in its own exception type.
    # Preserve raw stage/error_type in the ledger; classify it explicitly here.
    if row.get('error_type') == 'VideoSourceTimeoutException':
        return 'resolve_timeout'
    return row.get('stage', 'unknown')

def summarize(rows):
    output = []
    for group in sorted({r['group'] for r in rows}):
        for engine in ('webview', 'gecko'):
            subset = [r for r in rows if r['group'] == group and r['engine'] == engine]
            if not subset:
                continue
            success = [r for r in subset if r.get('stage') == 'first_frame']
            resolved = [r for r in subset if 'resolve' in r.get('timings_ms', {})]
            memory = [r['memory']['sampled_peak_pss_kib'] / 1024 for r in subset
                      if r.get('memory', {}).get('sampled_peak_pss_kib') is not None]
            median = lambda values: round(statistics.median(values), 1) if values else None
            output.append(dict(group=group, engine=engine, attempted=len(subset),
                resolved=len(resolved), first_frame=len(success),
                resolve_median_ms=median([r['timings_ms']['resolve'] for r in resolved]),
                frame_median_ms=median([r['timings_ms']['first_frame'] for r in success]),
                sampled_peak_pss_median_mib=median(memory),
                outcomes={stage: sum(classified_stage(r) == stage for r in subset)
                          for stage in sorted({classified_stage(r) for r in subset})}))
    return output

class FixtureHandler(BaseHTTPRequestHandler):
    media = b''
    def log_message(self, *_):
        pass
    def do_GET(self):
        path = self.path.split('?')[0]
        status, kind = 200, 'text/html; charset=utf-8'
        if path == '/fixture.mp4':
            body, kind = self.media, 'video/mp4'
        elif path == '/video':
            body = b'<video preload="none" src="/fixture.mp4"></video>'
        elif path == '/delayed':
            body = b'<script>setTimeout(()=>{document.body.innerHTML=\'<video src="/fixture.mp4" preload="none"></video>\'},700)</script>'
        elif path == '/nested':
            body = b'<iframe src="/player?url=http%3A%2F%2F127.0.0.1%3A8769%2Fvideo.html"></iframe>'
        elif path == '/video.html':
            body = b'<video preload="none" src="/fixture.mp4"></video>'
        elif path == '/cross-frame':
            body = b'<iframe src="http://127.0.0.1:8768/video"></iframe>'
        elif path == '/empty':
            body = b'<html><body>No media</body></html>'
        else:
            status, body = 404, b'not found'
        self.send_response(status)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

class Device:
    def __init__(self, adb, serial):
        if not re.fullmatch(r'emulator-\d+', serial):
            raise ValueError('Only an explicitly named emulator is permitted')
        self.adb, self.serial = adb, serial
        if self.call('shell', 'getprop ro.kernel.qemu').strip() != '1':
            raise ValueError('Target is not an Android emulator')

    def call(self, *args, input=None, timeout=15, check=True):
        completed = subprocess.run([self.adb, '-s', self.serial, *args], input=input,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        if check and completed.returncode:
            # Do not include command input (may contain signed URLs) in reports.
            raise RuntimeError(f'ADB failed: {completed.stderr.decode(errors="replace")[:200]}')
        return completed.stdout.decode('utf-8', errors='replace')

    def processes(self):
        rows = self.call('shell', 'ps -A -o PID,NAME').splitlines()[1:]
        return {int(parts[0]): parts[1] for row in rows if len(parts := row.split()) >= 2}

    def memory(self, baseline):
        processes = self.processes()
        targets = {pid: name for pid, name in processes.items()
                   if name == PACKAGE or name.startswith(PACKAGE + ':') or
                   (pid not in baseline and ('webview' in name.lower() and 'sandboxed_process' in name))}
        samples = []
        for pid, name in targets.items():
            data = self.call('shell', f'dumpsys meminfo {pid}', timeout=8, check=False)
            match = re.search(r'TOTAL PSS:\s*(\d+)', data)
            if not match:
                match = re.search(r'^\s*TOTAL\s+(\d+)', data, re.M)
            if match:
                samples.append({'pid': pid, 'name': name, 'pss_kib': int(match[1])})
        return {'at': time.time(), 'processes': samples,
                'sum_pss_kib': sum(p['pss_kib'] for p in samples)}

    def case(self, config, output, key):
        self.call('shell', f'am force-stop {PACKAGE}')
        self.call('shell', f"run-as {PACKAGE} sh -c 'mkdir -p files; rm -f files/result.json; cat > files/case.json'",
                  input=json.dumps(config, ensure_ascii=False).encode())
        baseline = self.processes()
        samples, stop = [], threading.Event()
        def monitor():
            while not stop.is_set():
                try:
                    samples.append(self.memory(baseline))
                except (RuntimeError, subprocess.TimeoutExpired):
                    pass
                stop.wait(1)
        worker = threading.Thread(target=monitor, daemon=True)
        started = time.monotonic()
        worker.start()
        try:
            self.call('shell', f'am start -W -n {PACKAGE}/{ACTIVITY}', timeout=20)
            result = None
            while time.monotonic() - started < 70:
                text = self.call('exec-out', 'run-as', PACKAGE, 'cat', 'files/result.json', check=False)
                try:
                    result = json.loads(text)
                    break
                except json.JSONDecodeError:
                    time.sleep(1)
            if result is None:
                result = {'id': config['id'], 'engine': config['engine'], 'stage': 'host_timeout'}
            result['host_elapsed_ms'] = round((time.monotonic() - started) * 1000)
        finally:
            stop.set()
            worker.join(timeout=30)
            self.call('shell', f'am force-stop {PACKAGE}')
        if worker.is_alive():
            raise RuntimeError('Memory sampler did not stop')
        observed = [s['sum_pss_kib'] for s in samples if s['processes']]
        result['memory'] = {
            'sampled_peak_pss_kib': max(observed) if observed else None,
            'samples': len(observed),
            'coverage': 'app processes plus new named WebView renderers; excludes shared system services; sampled not absolute peak',
            'process_names': sorted({p['name'] for s in samples for p in s['processes']}),
        }
        (output / f'{key}.memory.json').write_text(json.dumps(samples, indent=2), encoding='utf-8')
        return result

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--adb', required=True)
    p.add_argument('--serial', required=True)
    p.add_argument('--apk', type=Path, required=True)
    p.add_argument('--manifest', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--fixture-media', type=Path)
    p.add_argument('--repeats', type=int, default=1)
    p.add_argument('--budget-seconds', type=int, default=1800)
    args = p.parse_args()
    if not 1 <= args.repeats <= 5 or not 1 <= args.budget_seconds <= 1800:
        p.error('repeats 1..5, total budget 1..1800 seconds')
    manifest = json.loads(args.manifest.read_text(encoding='utf-8-sig'))
    cases = manifest['cases']
    if len(cases) * 2 * args.repeats > 24:
        p.error('At most 24 attempts per run')
    for c in cases:
        if 'rule_file' in c:
            rule_path = args.manifest.parent / c.pop('rule_file')
            c['rule'] = json.loads(rule_path.read_text(encoding='utf-8-sig'))
    device = Device(args.adb, args.serial)
    # Installation is a separate, explicit setup step. Verify the installed APK
    # bytes here; never blindly install a supplied APK with an unknown identity.
    remote = device.call('shell', f'pm path {PACKAGE}').strip().removeprefix('package:')
    if not remote.startswith('/data/app/') or '\n' in remote:
        raise RuntimeError('Expected exactly one installed QA APK')
    local_hash = digest(args.apk.read_bytes())
    artifact = json.loads((args.apk.parent / 'artifact.json').read_text(encoding='utf-8-sig'))
    if artifact['apk_sha256'] != local_hash:
        raise RuntimeError('Artifact provenance does not match --apk')
    remote_hash = device.call('shell', f'sha256sum {remote}').split()[0]
    if local_hash != remote_hash:
        raise RuntimeError('Installed QA APK does not match --apk')
    args.output.mkdir(parents=True, exist_ok=True)
    identity = {'apk_sha256': local_hash, 'artifact': artifact,
                'runner_sha256': digest(Path(__file__).read_bytes()),
                'manifest_sha256': digest(json.dumps(cases, sort_keys=True).encode()),
                'serial': args.serial, 'build_fingerprint': device.call('shell', 'getprop ro.build.fingerprint').strip(),
                'ua': UA, 'cache_policy': 'process cold; WebView cache disabled; Gecko private session; OS/DNS warm',
                'repeats': args.repeats}
    identity_hash = digest(json.dumps(identity, sort_keys=True).encode())
    identity_file = args.output / 'identity.json'
    if identity_file.exists() and json.loads(identity_file.read_text()) != identity:
        raise RuntimeError('Output directory belongs to another experiment identity')
    identity_file.write_text(json.dumps(identity, indent=2), encoding='utf-8')
    ledger = args.output / 'results.jsonl'
    rows = [json.loads(line) for line in ledger.read_text(encoding='utf-8').splitlines()] if ledger.exists() else []
    completed = {r['key'] for r in rows}
    attempts = args.output / 'attempts.jsonl'
    started_keys = {json.loads(line)['key'] for line in attempts.read_text().splitlines()} if attempts.exists() else set()
    if started_keys - completed:
        raise RuntimeError('An earlier attempt has unknown outcome; preserve it and use a new output directory')
    server = None
    deadline = time.monotonic() + args.budget_seconds
    try:
        if args.fixture_media:
            FixtureHandler.media = args.fixture_media.read_bytes()
            server = ThreadingHTTPServer(('127.0.0.1', 8769), FixtureHandler)
            threading.Thread(target=server.serve_forever, daemon=True).start()
            device.call('reverse', 'tcp:8769', 'tcp:8769')
            device.call('reverse', 'tcp:8768', 'tcp:8769')
        for config in paired_plan(cases, args.repeats):
            key = digest((identity_hash + json.dumps(config, sort_keys=True)).encode())[:20]
            if key in completed:
                continue
            if (args.output / 'STOP').exists() or time.monotonic() + 70 > deadline:
                break
            with attempts.open('a', encoding='utf-8') as f:
                f.write(json.dumps({'key': key, 'id': config['id'], 'engine': config['engine'],
                                    'repeat': config['repeat'], 'started_epoch': time.time()}) + '\n')
                f.flush()
            row = device.case(config, args.output, key)
            row.update(key=key, group=config['group'], repeat=config['repeat'],
                       rule_version=config.get('rule', {}).get('version'),
                       rule_name=config.get('rule', {}).get('name'),
                       rule_sha256=digest(json.dumps(config['rule'], sort_keys=True).encode()) if 'rule' in config else None,
                       rule_provenance=config.get('rule_provenance', {'overlay': 'none', 'upstream_commit': None}),
                       road=config.get('road', 0), episode=config.get('episode', 0),
                       compatibility='modern shared script; bounded nested HTML fallback; no WebView66 adapter')
            with ledger.open('a', encoding='utf-8') as f:
                f.write(json.dumps(row, ensure_ascii=False) + '\n')
                f.flush()
            rows.append(row)
            print(json.dumps({k: row.get(k) for k in ('id', 'engine', 'stage', 'host_elapsed_ms', 'cleanup')}, ensure_ascii=False), flush=True)
            if row.get('cleanup') == 'unconfirmed' or row['stage'] == 'host_timeout':
                break
    finally:
        device.call('shell', f'am force-stop {PACKAGE}', check=False)
        if server:
            server.shutdown()
            server.server_close()
            device.call('reverse', '--remove', 'tcp:8769', check=False)
            device.call('reverse', '--remove', 'tcp:8768', check=False)
        report = {'planned': len(cases) * 2 * args.repeats, 'completed': len(rows),
                  'unattempted': len(cases) * 2 * args.repeats - len(rows), 'summary': summarize(rows)}
        (args.output / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        (args.output / 'report.html').write_text('<meta charset="utf-8"><title>Parser QA</title><h1>Parser QA</h1><p>Modern emulator exploratory results; no TV compatibility claim. Time medians are successful parses/frames only. Memory is sampled PSS with limited process attribution.</p><pre>' + html.escape(json.dumps(report, ensure_ascii=False, indent=2)) + '</pre>', encoding='utf-8')

if __name__ == '__main__':
    main()
