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

def paired_plan(cases, repeats, engines=('webview', 'gecko')):
    for repeat in range(repeats):
        for index, case in enumerate(cases):
            order = engines if (index + repeat) % 2 == 0 else tuple(reversed(engines))
            for engine in order:
                yield {**case, 'engine': engine, 'repeat': repeat, 'user_agent': UA}

def classified_stage(row):
    # The App service wraps dart:async's timeout in its own exception type.
    # Preserve raw stage/error_type in the ledger; classify it explicitly here.
    if row.get('stage') == 'resolve_error' and row.get('error_type') == 'VideoSourceTimeoutException':
        return 'resolve_timeout'
    return row.get('stage', 'unknown')

def summarize(rows):
    output = []
    for group in sorted({r['group'] for r in rows}):
        for engine in ('app', 'webview', 'gecko'):
            subset = [r for r in rows if r['group'] == group and r['engine'] == engine]
            if not subset:
                continue
            invalid = [r for r in subset if classified_stage(r) == 'environment_invalid']
            infrastructure = [r for r in subset if classified_stage(r) in ('host_error', 'host_timeout', 'interrupted')]
            eligible = [r for r in subset if r not in invalid and r not in infrastructure]
            success = [r for r in eligible if classified_stage(r) == 'first_frame']
            resolved = [r for r in eligible if 'resolve' in r.get('timings_ms', {})]
            memory = [r['memory']['sampled_peak_pss_kib'] / 1024 for r in eligible
                      if r.get('memory', {}).get('sampled_peak_pss_kib') is not None]
            median = lambda values: round(statistics.median(values), 1) if values else None
            output.append(dict(group=group, engine=engine, attempted=len(subset),
                invalid=len(invalid), infrastructure=len(infrastructure), eligible_results=len(eligible),
                resolved=len(resolved), first_frame=len(success),
                resolve_median_ms=median([r['timings_ms']['resolve'] for r in resolved]),
                frame_median_ms=median([r['timings_ms']['first_frame'] for r in success]),
                sampled_peak_pss_median_mib=median(memory),
                outcomes={stage: sum(classified_stage(r) == stage for r in subset)
                          for stage in sorted({classified_stage(r) for r in subset})}))
    return output


def error_record(error):
    # Exceptions can contain request data; retain type/timeout, never commands.
    record = {'error_type': type(error).__name__}
    if isinstance(error, subprocess.TimeoutExpired):
        record['timeout_seconds'] = error.timeout
    return record


def cleanup_step(errors, step, action):
    try:
        return action()
    except BaseException as error:
        errors.append({'step': step, **error_record(error)})
        return None


def read_journal(path, issues):
    if not path.exists():
        return [], False
    records, complete = [], True
    for line_number, raw_line in enumerate(path.read_bytes().splitlines(), 1):
        if not raw_line.strip():
            continue
        try:
            line = raw_line.decode('utf-8-sig')
            value = json.loads(line)
            if not isinstance(value, dict):
                raise ValueError('Journal row must be an object')
            records.append(value)
        except (ValueError, TypeError):
            issues.append({'file': path.name, 'line': line_number, 'issue': 'unreadable_record'})
            complete = False
    return records, complete


def build_report(folder):
    """Derive coverage without modifying either append-only journal."""
    issues = []
    rows, results_intact = read_journal(folder / 'results.jsonl', issues)
    attempts, attempts_intact = read_journal(folder / 'attempts.jsonl', issues)
    identity_path = folder / 'identity.json'
    identity = json.loads(identity_path.read_text(encoding='utf-8-sig')) if identity_path.exists() else {}
    plan_path = folder / 'plan.json'
    plan = json.loads(plan_path.read_text(encoding='utf-8-sig')) if plan_path.exists() else None
    planned = identity.get('planned_attempts')
    planned_source = 'identity' if planned is not None else 'unknown'
    if plan is not None:
        if planned is not None and planned != len(plan):
            issues.append({'file': 'plan.json', 'issue': 'identity_count_mismatch'})
            planned = None
        else:
            planned, planned_source = len(plan), 'plan'
    elif planned is None and (folder / 'summary.json').exists():
        # Older identities did not save a plan/count. Preserve a known old
        # planned count, but never infer it from the number of completed rows.
        old = json.loads((folder / 'summary.json').read_text(encoding='utf-8-sig'))
        planned = old.get('planned')
        if planned is not None:
            planned_source = 'legacy_summary'
    if not isinstance(planned, int) or isinstance(planned, bool) or planned < 0:
        planned, planned_source = None, 'unknown'
    completed_keys = {r['key'] for r in rows if isinstance(r.get('key'), str)}
    started_keys = {r['key'] for r in attempts if isinstance(r.get('key'), str)}
    keyed = len(completed_keys) == len(rows) and len(started_keys) == len(attempts)
    if not keyed:
        issues.append({'issue': 'missing_or_duplicate_journal_keys'})
    known_started = started_keys | completed_keys
    known_unknown = started_keys - completed_keys
    coverage_known = attempts_intact and keyed and (results_intact or not (folder / 'results.jsonl').exists())
    plan_keys = {r['key'] for r in plan} if plan is not None else None
    if plan_keys is not None and (known_started - plan_keys or len(plan_keys) != len(plan)):
        issues.append({'file': 'plan.json', 'issue': 'journal_or_duplicate_plan_key_mismatch'})
        coverage_known = False
    if planned is not None and planned < len(known_started):
        issues.append({'issue': 'observed_attempts_exceed_plan'})
        coverage_known = False
    states = []
    metadata = {r['key']: r for r in (plan or [])}
    for record in attempts + rows:
        if isinstance(record.get('key'), str):
            metadata[record['key']] = {**metadata.get(record['key'], {}), **record}
    keys = plan_keys | known_started if plan_keys is not None else known_started
    for key in sorted(keys):
        source = metadata.get(key, {})
        state = ('completed' if key in completed_keys else 'unknown' if key in started_keys
                 else 'unattempted' if coverage_known else 'unknown')
        states.append({'key': key, 'id': source.get('id'), 'engine': source.get('engine'),
                       'repeat': source.get('repeat'), 'state': state})
    status_path = folder / 'cleanup.json' if (folder / 'cleanup.json').exists() else folder / 'run-status.json'
    status = json.loads(status_path.read_text(encoding='utf-8-sig')) if status_path.exists() else None
    return {'report_schema': 2, 'planned': planned, 'planned_source': planned_source,
            'completed': len(rows), 'started': len(known_started) if coverage_known else None,
            'unknown': len(known_unknown) if coverage_known else None,
            'known_unknown': len(known_unknown),
            'unattempted': planned - len(known_started) if planned is not None and coverage_known else None,
            'remaining_without_result': max(0, planned - len(rows)) if planned is not None else None,
            'coverage_known': coverage_known, 'journal_issues': issues,
            'case_states': states, 'run_status': status, 'summary': summarize(rows)}

class FixtureHandler(BaseHTTPRequestHandler):
    media = b''
    def log_message(self, *_):
        pass
    def do_GET(self):
        path = self.path.split('?')[0]
        status, kind = 200, 'text/html; charset=utf-8'
        content_range = None
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
        if path == '/fixture.mp4' and self.headers.get('Range'):
            length = len(body)
            match = re.fullmatch(r'bytes=(\d*)-(\d*)', self.headers['Range'])
            start, end = 0, length - 1
            if match and (match[1] or match[2]):
                if match[1]:
                    start = int(match[1]); end = min(int(match[2]), end) if match[2] else end
                else:
                    start = max(0, length - int(match[2]))
                valid = start <= end and start < length
            else:
                valid = False
            if valid:
                status, body = 206, body[start:end+1]
                content_range = f'bytes {start}-{end}/{length}'
            else:
                status, body, content_range = 416, b'', f'bytes */{length}'
        self.send_response(status)
        self.send_header('Content-Type', kind)
        if path == '/fixture.mp4':
            self.send_header('Accept-Ranges', 'bytes')
        if content_range is not None:
            self.send_header('Content-Range', content_range)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        if self.command == 'HEAD':
            return
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    do_HEAD = do_GET

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
        lines = self.call('shell', 'ps -A -o PID,NAME').splitlines()
        if not lines or lines[0].split() != ['PID', 'NAME'] or len(lines) < 2:
            raise RuntimeError('Process inventory is missing or invalid')
        rows = lines[1:]
        return {int(parts[0]): parts[1] for row in rows if len(parts := row.split()) >= 2}

    def stop_and_verify(self, baseline=None):
        errors = []
        cleanup_step(errors, 'force_stop', lambda: self.call('shell', f'am force-stop {PACKAGE}', timeout=8))
        processes = cleanup_step(errors, 'process_inventory', self.processes)
        remaining = None if processes is None else {
            pid: name for pid, name in processes.items()
            if name == PACKAGE or name.startswith(PACKAGE + ':') or
            (baseline is not None and pid not in baseline and
             'webview' in name.lower() and 'sandboxed_process' in name)}
        if remaining:
            errors.append({'step': 'process_exit', 'error_type': 'ProcessesStillPresent'})
        return {'status': 'confirmed' if not errors and remaining == {} else 'unconfirmed',
                'process_exit': 'confirmed' if remaining == {} else 'unconfirmed',
                'coverage': 'named QA processes and, when baseline exists, new named WebView renderers',
                'remaining_processes': remaining, 'errors': errors}

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
        baseline = None
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
        worker_started = False
        result, primary_error = None, None
        cleanup_errors = []
        try:
            initial = self.stop_and_verify()
            if initial['status'] != 'confirmed':
                cleanup_errors.append({'step': 'cold_start', 'details': initial})
                raise RuntimeError('QA cold-start process exit was not confirmed')
            self.call('shell', f"run-as {PACKAGE} sh -c 'mkdir -p files; rm -f files/result.json; cat > files/case.json'",
                      input=json.dumps(config, ensure_ascii=False).encode())
            baseline = self.processes()
            worker.start()
            worker_started = True
            self.call('shell', f'am start -W -n {PACKAGE}/{ACTIVITY}', timeout=20)
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
        except BaseException as error:
            primary_error = error
        finally:
            stop.set()
            host_cleanup = cleanup_step(cleanup_errors, 'case_stop', lambda: self.stop_and_verify(baseline))
            if worker_started:
                cleanup_step(cleanup_errors, 'sampler_join', lambda: worker.join(timeout=30))
                if worker.is_alive():
                    cleanup_errors.append({'step': 'sampler_exit', 'error_type': 'SamplerStillRunning'})
        observed = [s['sum_pss_kib'] for s in samples if s['processes']]
        memory = {
            'sampled_peak_pss_kib': max(observed) if observed else None,
            'samples': len(observed),
            'coverage': 'app processes plus new named WebView renderers; excludes shared system services; sampled not absolute peak',
            'process_names': sorted({p['name'] for s in samples for p in s['processes']}),
        }
        cleanup_step(cleanup_errors, 'memory_evidence', lambda:
            (output / f'{key}.memory.json').write_text(json.dumps(samples, indent=2), encoding='utf-8'))
        host_cleanup = host_cleanup or {'status': 'unconfirmed', 'process_exit': 'unconfirmed', 'errors': []}
        host_cleanup['errors'].extend(cleanup_errors)
        if host_cleanup['errors']:
            host_cleanup['status'] = 'unconfirmed'
        if primary_error is not None:
            primary_error.qa_cleanup = host_cleanup
            cleanup_step(host_cleanup['errors'], 'host_error_evidence', lambda:
                (output / f'{key}.host-error.json').write_text(json.dumps({
                    'id': config['id'], 'engine': config['engine'], 'key': key,
                    'primary_error': error_record(primary_error), 'host_cleanup': host_cleanup,
                }, indent=2), encoding='utf-8'))
            if host_cleanup['errors']:
                host_cleanup['status'] = 'unconfirmed'
            raise primary_error.with_traceback(primary_error.__traceback__)
        result['memory'] = memory
        result['host_cleanup'] = host_cleanup
        return result

class BatchCleanupError(RuntimeError):
    pass


def run_batch(device, plan, output, rows, *, fixture_media=None, budget_seconds=1800,
              server_factory=ThreadingHTTPServer):
    """Execute a preflighted plan; every teardown action has its own guard."""
    public_plan = [{k: item[k] for k in ('key', 'id', 'engine', 'group', 'repeat')} for item in plan]
    (output / 'plan.json').write_text(json.dumps(public_plan, indent=2), encoding='utf-8')
    attempts, ledger = output / 'attempts.jsonl', output / 'results.jsonl'
    attempts.touch(exist_ok=True)
    completed = {r['key'] for r in rows}
    server, server_thread = None, None
    reverse_ports = []
    primary_error, final_stop = None, None
    cleanup_errors = []
    stop_reason = 'completed'
    deadline = time.monotonic() + budget_seconds
    try:
        if fixture_media is not None:
            FixtureHandler.media = fixture_media.read_bytes()
            server = server_factory(('127.0.0.1', 8769), FixtureHandler)
            server_thread = threading.Thread(target=server.serve_forever, daemon=True)
            server_thread.start()
            for port in ('8769', '8768'):
                reverse_ports.append(port)  # A timed-out setup has unknown outcome.
                device.call('reverse', f'tcp:{port}', 'tcp:8769')
        for item in plan:
            key, config = item['key'], item['config']
            if key in completed:
                continue
            if (output / 'STOP').exists() or time.monotonic() + 70 > deadline:
                stop_reason = 'stop_requested' if (output / 'STOP').exists() else 'budget'
                break
            with attempts.open('a', encoding='utf-8') as f:
                f.write(json.dumps({'key': key, 'id': item['id'], 'engine': item['engine'],
                                    'group': item['group'], 'repeat': item['repeat'],
                                    'started_epoch': time.time()}) + '\n')
                f.flush()
            row = device.case(config, output, key)
            environment, expected = row.get('environment', {}), item['expected_environment']
            if environment and (environment.get('sdk') != expected['sdk'] or environment.get('webview') != expected['provider']):
                row['observed_stage'] = row.get('stage')
                row['stage'] = 'environment_invalid'
            row.update(key=key, group=item['group'], repeat=item['repeat'],
                       rule_version=config.get('rule', {}).get('version'),
                       rule_name=config.get('rule', {}).get('name'),
                       rule_sha256=digest(json.dumps(config['rule'], sort_keys=True).encode()) if 'rule' in config else None,
                       rule_provenance=config.get('rule_provenance', {'overlay': 'none', 'upstream_commit': None}),
                       road=config.get('road', 0), episode=config.get('episode', 0),
                       compatibility=('production capability factory and default headers/player controller'
                           if config['engine'] == 'app' else 'controlled shared script; bounded nested HTML fallback; no WebView66 adapter'))
            with ledger.open('a', encoding='utf-8') as f:
                f.write(json.dumps(row, ensure_ascii=False) + '\n')
                f.flush()
            rows.append(row)
            print(json.dumps({k: row.get(k) for k in ('id', 'engine', 'stage', 'host_elapsed_ms', 'cleanup')}, ensure_ascii=False), flush=True)
            if row.get('cleanup') == 'unconfirmed' or row.get('host_cleanup', {}).get('status') == 'unconfirmed':
                stop_reason = 'case_cleanup_unconfirmed'
                cleanup_errors.append({'step': 'case_cleanup', 'key': key,
                                       'app_cleanup': row.get('cleanup'), 'host_cleanup': row.get('host_cleanup')})
                break
            if row['stage'] in ('host_timeout', 'environment_invalid'):
                stop_reason = row['stage']
                break
    except BaseException as error:
        primary_error = error
        stop_reason = 'interrupted' if isinstance(error, KeyboardInterrupt) else 'host_error'
    finally:
        final_stop = cleanup_step(cleanup_errors, 'final_force_stop', device.stop_and_verify)
        if final_stop is not None and final_stop['status'] != 'confirmed':
            cleanup_errors.append({'step': 'final_process_exit', 'details': final_stop})
        if server is not None:
            if server_thread is not None and server_thread.ident is not None:
                cleanup_step(cleanup_errors, 'fixture_shutdown', server.shutdown)
            cleanup_step(cleanup_errors, 'fixture_close', server.server_close)
        for port in reverse_ports:
            cleanup_step(cleanup_errors, f'reverse_remove_{port}', lambda port=port:
                         device.call('reverse', '--remove', f'tcp:{port}'))
        if server_thread is not None and server_thread.ident is not None:
            cleanup_step(cleanup_errors, 'fixture_thread_join', lambda: server_thread.join(timeout=2))
            if server_thread.is_alive():
                cleanup_errors.append({'step': 'fixture_thread_exit', 'error_type': 'FixtureThreadStillRunning'})
        status = {'stop_reason': stop_reason,
                  'primary_error': error_record(primary_error) if primary_error is not None else None,
                  'case_host_cleanup': getattr(primary_error, 'qa_cleanup', None),
                  'final_host_cleanup': final_stop, 'cleanup_errors': cleanup_errors}
        cleanup_step(cleanup_errors, 'run_status_write', lambda:
            (output / 'run-status.json').write_text(json.dumps(status, indent=2), encoding='utf-8'))
        report = cleanup_step(cleanup_errors, 'report_rebuild', lambda: build_report(output))
        if report is not None:
            report['run_status'] = status
            cleanup_step(cleanup_errors, 'summary_write', lambda:
                (output / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8'))
            cleanup_step(cleanup_errors, 'html_write', lambda:
                (output / 'report.html').write_text('<meta charset="utf-8"><title>Parser QA</title><h1>Parser QA</h1><p>Emulator exploratory results. Environment-invalid results are excluded from product metrics; null coverage means unknown.</p><pre>' + html.escape(json.dumps(report, ensure_ascii=False, indent=2)) + '</pre>', encoding='utf-8'))
        cleanup_step(cleanup_errors, 'cleanup_receipt_write', lambda:
            (output / 'cleanup.json').write_text(json.dumps(status, indent=2), encoding='utf-8'))
    if primary_error is not None:
        raise primary_error.with_traceback(primary_error.__traceback__)
    if cleanup_errors:
        raise BatchCleanupError('Batch stopped with unconfirmed cleanup; see cleanup.json')
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--adb', required=True)
    p.add_argument('--serial', required=True)
    p.add_argument('--apk', type=Path, required=True)
    p.add_argument('--manifest', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--fixture-media', type=Path)
    p.add_argument('--repeats', type=int, default=1)
    p.add_argument('--engines', default='app', help='app (production service path) or webview,gecko (controlled A/B)')
    p.add_argument('--expect-sdk', type=int)
    p.add_argument('--expect-webview')
    p.add_argument('--budget-seconds', type=int, default=1800)
    args = p.parse_args()
    engines = tuple(args.engines.split(','))
    if not engines or len(set(engines)) != len(engines) or not set(engines) <= {'app', 'webview', 'gecko'}:
        p.error('Engines must be unique values from app,webview,gecko')
    if not 1 <= args.repeats <= 5 or not 1 <= args.budget_seconds <= 1800:
        p.error('repeats 1..5, total budget 1..1800 seconds')
    manifest = json.loads(args.manifest.read_text(encoding='utf-8-sig'))
    cases = manifest['cases']
    if len(cases) * len(engines) * args.repeats > 24:
        p.error('At most 24 attempts per run')
    for c in cases:
        if 'rule_file' in c:
            rule_path = args.manifest.parent / c.pop('rule_file')
            c['rule'] = json.loads(rule_path.read_text(encoding='utf-8-sig'))
    device = Device(args.adb, args.serial)
    sdk = int(device.call('shell', 'getprop ro.build.version.sdk').strip())
    provider_state = device.call('shell', 'dumpsys webviewupdate')
    match = re.search(r'Current WebView package \(name, version\): \(([^,]+), ([^)]+)\)', provider_state)
    provider = '/'.join(match.groups()) if match else None
    if args.expect_sdk is not None and sdk != args.expect_sdk:
        raise RuntimeError('Android SDK does not match the requested test environment')
    if args.expect_webview is not None and (not match or match[2] != args.expect_webview):
        raise RuntimeError('Actual selected WebView does not match the requested version')
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
                'sdk': sdk, 'selected_provider': provider,
                'ua': UA, 'cache_policy': 'process cold; WebView cache disabled; Gecko private session; OS/DNS warm',
                'engines': list(engines), 'repeats': args.repeats,
                'planned_attempts': len(cases) * len(engines) * args.repeats}
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
    plan = []
    for config in paired_plan(cases, args.repeats, engines):
        key = digest((identity_hash + json.dumps(config, sort_keys=True)).encode())[:20]
        plan.append({'key': key, 'config': config, 'id': config['id'], 'engine': config['engine'],
                     'group': config['group'], 'repeat': config['repeat'],
                     'expected_environment': {'sdk': sdk, 'provider': provider}})
    run_batch(device, plan, args.output, rows, fixture_media=args.fixture_media,
              budget_seconds=args.budget_seconds)


if __name__ == '__main__':
    main()
