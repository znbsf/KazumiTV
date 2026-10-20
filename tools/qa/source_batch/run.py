"""Bounded QA runner; physical targets require explicit, exact identity binding."""
import argparse
from contextlib import contextmanager
import hashlib
import html
import json
import os
from pathlib import Path
import re
import statistics
import sys
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PACKAGE = 'com.znbsf.kazumi.fluttertv.parserqa'
ACTIVITY = 'com.example.kazumi.ParserQaActivity'
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'
RESULT_BYTE_LIMIT = 256 * 1024


class HostBudgetExpired(TimeoutError):
    """Infrastructure unknown, never a parser timeout or permission to retry."""


class HostDeadline:
    def __init__(self, seconds=None, *, started=None, end=None):
        self.started = time.monotonic() if started is None else started
        self.end = self.started + seconds if end is None else end

    def remaining(self):
        return max(0.0, self.end - time.monotonic())

    def check(self):
        if self.remaining() <= 0:
            error = HostBudgetExpired('QA host deadline exhausted')
            error.qa_output = getattr(self, 'output', None)
            error.preflight_planned = getattr(self, 'planned_count', None)
            error.host_budget = self.receipt()
            raise error

    def cap(self, seconds):
        self.check()
        return min(seconds, self.remaining())

    def child(self, end, *, started=None):
        child = HostDeadline(started=self.started if started is None else started,
                             end=min(end, self.end))
        for name in ('output', 'planned_count'):
            if hasattr(self, name):
                setattr(child, name, getattr(self, name))
        return child

    def receipt(self):
        now = time.monotonic()
        return {'elapsed_ms': round((now-self.started)*1000),
                'started_monotonic':self.started, 'deadline_monotonic':self.end,
                'limit_ms': round((self.end-self.started)*1000),
                'overrun_ms': max(0, round((now-self.end)*1000)),
                'within_deadline': now < self.end,
                'hard_realtime_guarantee': False}


def atomic_json(path, value, budget=None):
    if budget is not None:
        budget.check()
    temporary = path.with_name(path.name + '.tmp')
    with temporary.open('w', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, ensure_ascii=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    if budget is not None:
        budget.check()
LAUNCH_ID = 'qa-offline-launch-only-v1'
LAUNCH_KEYS = {'id', 'group', 'engine', 'launch_only', 'repeat', 'user_agent', 'launch_attempt_key'}
LAUNCH_DART_ORDER = ['dart_binding'] + [f'dart_{s}_{edge}' for s in
    ('identity', 'config', 'tvmode', 'webview', 'mediakit', 'path', 'hive', 'storage', 'shaders', 'dio_guard')
    for edge in ('enter', 'exit')] + ['dart_runapp', 'dart_first_frame']
LAUNCH_STAGES = set(LAUNCH_DART_ORDER) | {'native_create_enter', 'native_create_exit', 'native_engine_enter',
    'native_super_engine_exit', 'native_channel_ready', 'native_resume', 'native_window_focus',
    'native_destroy', 'native_uncaught', 'native_first_frame', 'dart_failure', 'probe_result'}

def launch_only_spec(config):
    if 'launch_only' not in config and config.get('id') != LAUNCH_ID:
        return False
    if (set(config) - LAUNCH_KEYS or config.get('launch_only') is not True or
        config.get('id') != LAUNCH_ID or config.get('group') != 'offline-launch' or
        config.get('engine', 'app') != 'app' or type(config.get('repeat', 0)) is not int or config.get('repeat', 0) != 0 or
        not isinstance(config.get('user_agent', UA), str) or len(config.get('user_agent', UA)) > 256 or
        ('launch_attempt_key' in config and not re.fullmatch(r'[a-f0-9]{20}', str(config['launch_attempt_key'])))):
        raise ValueError('Invalid fixed launch-only configuration')
    return True

def console_only_batch_spec(cases, artifact, engines, repeats, fixture_media, physical):
    for case in cases:
        if 'console_hint_observer' in case and type(case['console_hint_observer']) is not bool:
            raise ValueError('QA console opt-in must be boolean')
    if not any(c.get('console_hint_observer') is True for c in cases):
        return False
    if (len(cases) != 1 or cases[0].get('id') != 'qa-mgnacg-console-hints-v1' or
        cases[0].get('group') != 'console-hints' or engines != ('app',) or repeats != 1 or
        fixture_media is not None or physical or artifact.get('launch_only_build') is not False or
        artifact.get('internet_permission') is not True or
        type(artifact.get('console_hint_observer_schema')) is not int or artifact['console_hint_observer_schema'] != 1):
        raise ValueError('Fixed console-only case and newly built capable ordinary QA required')
    return True

def launch_am_fields(raw):
    if isinstance(raw, bytes):
        raw = raw.decode('utf-8', 'replace')
    output = {}
    for line in (raw or '').splitlines():
        match = re.fullmatch(r'\s*(ThisTime|TotalTime|WaitTime):\s*(\d+)\s*', line)
        if match:
            output[match[1]] = int(match[2])
        elif line.strip() in ('Status: ok', 'Status: timeout', 'Complete'):
            output[line.strip().split(':')[0]] = line.strip().partition(':')[2].strip() or True
        elif line.strip() == f'Activity: {PACKAGE}/{ACTIVITY}':
            output['expected_activity'] = True
    return output

def launch_file_decode(raw, declared):
    meta = {'declared_bytes': declared, 'read_bytes': len(raw), 'raw_sha256': digest(raw)}
    if len(raw) != declared or len(raw) > 32768:
        return {**meta, 'type': 'size_mismatch_or_limit'}, None
    if not raw:
        return {**meta, 'type': 'empty'}, None
    try:
        value = json.loads(raw.decode('utf-8'))
    except UnicodeDecodeError:
        return {**meta, 'type': 'invalid_utf8'}, None
    except json.JSONDecodeError as error:
        return {**meta, 'type': 'invalid_json', 'error_type': 'JSONDecodeError', 'error_position': error.pos}, None
    return {**meta, 'type': 'json_object' if isinstance(value, dict) else 'json_other'}, value

def validate_launch_journal(value, key):
    if (not isinstance(value, dict) or set(value) != {'schema', 'id', 'attempt_key',
        'network_permission_denied', 'package_info_registered', 'events'} or type(value['schema']) is not int or value['schema'] != 1 or
        value['id'] != LAUNCH_ID or value['attempt_key'] not in (key, None) or
        type(value['network_permission_denied']) is not bool or
        (value['package_info_registered'] is not None and type(value['package_info_registered']) is not bool) or
        not isinstance(value['events'], list) or not 1 <= len(value['events']) <= 64):
        return False
    last = -1
    for index, event in enumerate(value['events']):
        if (not isinstance(event, dict) or set(event) - {'seq', 'stage', 'elapsed_ms', 'pid', 'error_type'} or
            type(event.get('seq')) is not int or event.get('seq') != index or event.get('stage') not in LAUNCH_STAGES or
            type(event.get('elapsed_ms')) is not int or event['elapsed_ms'] < max(0, last) or
            type(event.get('pid')) is not int or event['pid'] <= 0):
            return False
        if 'error_type' in event and (event['stage'] not in ('native_uncaught', 'dart_failure') or
            not isinstance(event['error_type'], str) or not re.fullmatch(r'[A-Za-z_$][A-Za-z0-9_.$]{0,159}', event['error_type'])):
            return False
        last = event['elapsed_ms']
    return True

def validate_launch_result(value, key):
    expected = {'id': LAUNCH_ID, 'engine': 'app', 'launch_only': True, 'attempt_key': key, 'stage': 'launch_ready',
        'parser': 'not_run', 'media': 'not_run', 'player_release': 'not_created', 'resolver_release': 'not_created',
        'cleanup': 'confirmed', 'cleanup_coverage': 'no parser/player created; host verifies process exit',
        'network_permission_denied': True, 'package_info_registered': True, 'native_first_frame': True}
    if not isinstance(value, dict) or set(value) != set(expected) | {'environment'} or any(value.get(k) != v for k,v in expected.items()):
        return False
    env = value['environment']
    return (isinstance(env, dict) and set(env) == {'sdk', 'webview', 'package'} and
        env.get('package') == PACKAGE and type(env.get('sdk')) is int and 26 <= env['sdk'] <= 40 and
        isinstance(env.get('webview'), str) and bool(re.fullmatch(r'[A-Za-z0-9_.]+/[A-Za-z0-9_.-]+', env['webview'])))

def launch_ready_observed(journal, key):
    if not validate_launch_journal(journal, key) or journal['attempt_key'] != key or journal['network_permission_denied'] is not True or journal['package_info_registered'] is not True:
        return False
    stages = [e['stage'] for e in journal['events']]
    return ([s for s in stages if s.startswith('dart_')] == LAUNCH_DART_ORDER and
        stages.count('probe_result') == 1 and 'native_uncaught' not in stages and
        stages.count('native_first_frame') == 1 and
        all(s in stages for s in ('native_create_enter','native_engine_enter','native_super_engine_exit','native_channel_ready')))

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
            infrastructure = [r for r in subset if classified_stage(r) in ('host_error', 'host_timeout', 'interrupted', 'unknown')]
            selection = [r for r in subset if r.get('selection_only') is True and r not in invalid and r not in infrastructure]
            launch = [r for r in subset if r.get('launch_only') is True and r not in invalid and r not in infrastructure]
            console = [r for r in subset if r.get('console_only') is True and r not in invalid and r not in infrastructure]
            eligible = [r for r in subset if r not in invalid and r not in infrastructure and r not in selection and r not in launch and r not in console]
            success = [r for r in eligible if classified_stage(r) == 'first_frame']
            resolved = [r for r in eligible if 'resolve' in r.get('timings_ms', {})]
            memory = [r['memory']['sampled_peak_pss_kib'] / 1024 for r in eligible
                      if r.get('memory', {}).get('sampled_peak_pss_kib') is not None]
            median = lambda values: round(statistics.median(values), 1) if values else None
            output.append(dict(group=group, engine=engine, attempted=len(subset),
                invalid=len(invalid), infrastructure=len(infrastructure), selection_only_results=len(selection),
                launch_only_results=len(launch), launch_ready=sum(r.get('stage') == 'launch_ready' for r in launch),
                console_only_results=len(console),
                selection_completed=sum(r.get('stage') == 'selection_only' for r in selection), eligible_results=len(eligible),
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


def read_receipt(path, issues=None):
    if not path.exists():
        return None
    try:
        value = json.loads(path.read_text(encoding='utf-8-sig'))
        if not isinstance(value, dict):
            raise ValueError('Receipt must be an object')
        return value
    except (OSError, UnicodeError, ValueError) as error:
        if issues is not None:
            issues.append({'file':path.name, 'issue':'invalid_receipt',
                           'error_type':type(error).__name__})
        return None


def terminal_record_digest(row):
    return digest(json.dumps(row, sort_keys=True, ensure_ascii=False).encode())


def final_receipt_confirms(row, receipt):
    if not isinstance(receipt, dict):
        return False
    records = receipt.get('terminal_records')
    final = receipt.get('final_host_cleanup')
    budget, host = row.get('host_budget'), row.get('host_cleanup')
    if (not isinstance(records, dict) or not isinstance(final, dict) or
            final.get('status') != 'confirmed' or
            not isinstance(receipt.get('cleanup_errors'), list) or
            not isinstance(budget, dict) or budget.get('within_deadline') is not True or
            row.get('cleanup') != 'confirmed' or not isinstance(host, dict) or
            host.get('status') != 'confirmed'):
        return False
    for name in ('budget_unknown_keys', 'unconfirmed_terminal_keys'):
        keys = receipt.get(name, [])
        if not isinstance(keys, list) or not all(isinstance(k, str) for k in keys) or row.get('key') in keys:
            return False
    return isinstance(row.get('key'), str) and records.get(row['key']) == terminal_record_digest(row)


def build_report(folder):
    """Derive coverage without modifying either append-only journal."""
    issues = []
    rows, results_intact = read_journal(folder / 'results.jsonl', issues)
    raw_rows = rows
    raw_result_records = len(rows)
    checkpoint = read_receipt(folder / 'run-status.json', issues)
    final_receipt = read_receipt(folder / 'cleanup.json', issues)
    budget_unknown = set()
    for receipt in (checkpoint, final_receipt):
        for name in ('budget_unknown_keys', 'unconfirmed_terminal_keys'):
            keys = (receipt or {}).get(name, [])
            if isinstance(keys, list) and all(isinstance(k, str) for k in keys):
                budget_unknown.update(keys)
    rows = []
    for row in raw_rows:
        if row.get('key') in budget_unknown:
            continue
        if 'host_budget' in row and not final_receipt_confirms(row, final_receipt):
            issues.append({'file':'cleanup.json', 'key':row.get('key'),
                           'issue':'final_receipt_missing_or_unmatched'})
            continue
        rows.append(row)
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
    observed_keys = {r['key'] for r in raw_rows if isinstance(r.get('key'), str)}
    started_keys = {r['key'] for r in attempts if isinstance(r.get('key'), str)}
    keyed = len(observed_keys) == len(raw_rows) and len(started_keys) == len(attempts)
    if not keyed:
        issues.append({'issue': 'missing_or_duplicate_journal_keys'})
    known_started = started_keys | observed_keys
    known_unknown = known_started - completed_keys
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
    for record in attempts + raw_rows:
        if isinstance(record.get('key'), str):
            metadata[record['key']] = {**metadata.get(record['key'], {}), **record}
    keys = plan_keys | known_started if plan_keys is not None else known_started
    for key in sorted(keys):
        source = metadata.get(key, {})
        state = ('completed' if key in completed_keys else 'unknown' if key in started_keys
                 else 'unattempted' if coverage_known else 'unknown')
        states.append({'key': key, 'id': source.get('id'), 'engine': source.get('engine'),
                       'repeat': source.get('repeat'), 'state': state})
    status = final_receipt if (folder / 'cleanup.json').exists() else checkpoint
    return {'report_schema': 2, 'planned': planned, 'planned_source': planned_source,
            'raw_result_records': raw_result_records,
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
        elif path == '/video-next':
            body = b'<video preload="none" src="/fixture.mp4?episode=next"></video>'
        elif path == '/lifecycle-slow':
            body = b'<script>setTimeout(()=>{document.body.innerHTML=\'<video preload="none" src="/fixture.mp4?episode=old"></video>\'},8000)</script>'
        elif path == '/modern-syntax-slow':
            body = b'<script>var state={};var required=state?.value;setTimeout(()=>{document.body.innerHTML=\'<video preload="none" src="/fixture.mp4?episode=old"></video>\'},8000)</script>'
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
        elif path == '/modern-syntax':
            body = b'<html><body><script>var state={};var required=state?.value;document.body.innerHTML=\'<video preload="none" src="/fixture.mp4"></video>\';</script></body></html>'
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

def lifecycle_spec(config):
    spec = config.get('qa_lifecycle')
    if spec is None:
        return None
    def local(url):
        return isinstance(url, str) and url.startswith('http://127.0.0.1:8769/')
    if (not isinstance(spec, dict) or config.get('engine') != 'app' or
            config.get('app_gecko_fallback') is not True or 'rule' in config or
            'rule_file' in config or not local(config.get('url')) or
            spec.get('action') not in ('exit', 'switch') or
            spec.get('trigger_phase') not in ('primary', 'fallback')):
        raise ValueError('Lifecycle actions require an explicit local App fixture')
    if spec['action'] == 'switch':
        target = spec.get('target')
        if (not isinstance(target, dict) or not local(target.get('url')) or
                not isinstance(target.get('id'), str) or not target['id'] or
                target.get('id') == config.get('id') or
                target.get('url') == config.get('url') or
                set(target) - {'id', 'url', 'observe_playback_seconds'}):
            raise ValueError('Switch target must be a different local fixture')
    return spec


def lifecycle_result_observed(config, row, driver):
    spec = lifecycle_spec(config)
    if spec is None:
        return True
    state = row.get('lifecycle')
    if not driver or not isinstance(state, dict) or state.get('actual_page_disposals', 0) < 1:
        return False
    events, children = state.get('events', []), state.get('children', [])
    if (not any(e.get('stage') == 'ui_transition' and e.get('generation') == 1 for e in events) or
            not any(e.get('stage') == 'native_stale_result_probe' and e.get('accepted') is False for e in events) or
            not children or children[0].get('cancelled_by_ui') is not True or
            children[0].get('normal_publication_allowed') is not False):
        return False
    if spec['action'] == 'switch':
        return (row.get('qa_case_id') == spec['target']['id'] and
                row.get('episode_page_sha256') == digest(spec['target']['url'].encode()) and
                len(children) == 2 and children[-1].get('normal_publication_allowed') is True)
    return row.get('stage') == 'lifecycle_cancelled' and row.get('old_result_suppressed') is True


def expected_qa_foreground(text):
    components = set()
    for line in text.splitlines():
        if not re.match(r'^\s*(?:mResumedActivity|topResumedActivity)\s*[:=]', line):
            continue
        component = re.search(r'\b([A-Za-z_][\w.]*)/([A-Za-z_.$][\w.$]*)\b', line)
        if component is None:
            return False
        package, activity = component.groups()
        if activity.startswith('.'):
            activity = package + activity
        components.add(f'{package}/{activity}')
    return components == {f'{PACKAGE}/{ACTIVITY}'}


class Device:
    def __init__(self, adb, serial, *, allow_physical=False,
                 expected_serial=None, expected_fingerprint=None,
                 package=PACKAGE, budget=None):
        if package != PACKAGE:
            raise ValueError('Only the fixed parserqa package is permitted')
        if allow_physical:
            if (not expected_serial or serial != expected_serial or
                    not expected_fingerprint or
                    not re.fullmatch(r'[A-Za-z0-9_.:-]+', serial) or
                    serial.startswith('emulator-')):
                raise ValueError('Physical QA requires exact serial and fingerprint')
        elif not re.fullmatch(r'emulator-\d+', serial):
            raise ValueError('Only an explicitly named emulator is permitted')
        self.adb, self.serial = adb, serial
        self._budget_local = threading.local()
        self._parent_budget = budget
        self.physical = allow_physical
        qemu = self.call('shell', 'getprop ro.kernel.qemu').strip()
        if allow_physical:
            actual = self.call('shell', 'getprop ro.build.fingerprint').strip()
            self.fingerprint = actual
            if qemu == '1' or actual != expected_fingerprint:
                raise ValueError('Physical QA target identity mismatch')
        elif qemu != '1':
            raise ValueError('Target is not an Android emulator')

    def budget(self):
        local = getattr(self, '_budget_local', None)
        return getattr(local, 'value', None) or getattr(self, '_parent_budget', None)

    @contextmanager
    def deadline_scope(self, budget):
        if not hasattr(self, '_budget_local'):
            self._budget_local = threading.local()
        previous = getattr(self._budget_local, 'value', None)
        self._budget_local.value = budget
        try:
            yield
        finally:
            self._budget_local.value = previous

    def call(self, *args, input=None, timeout=15, check=True, binary=False, return_completed=False):
        budget = self.budget()
        if budget is not None:
            timeout = budget.cap(timeout)
        try:
            completed = subprocess.run([self.adb, '-s', self.serial, *args], input=input,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            if budget is not None:
                error.qa_output = getattr(budget, 'output', None)
                error.preflight_planned = getattr(budget, 'planned_count', None)
                error.host_budget = budget.receipt()
            raise
        if budget is not None:
            budget.check()
        if check and completed.returncode:
            # Do not include command input (may contain signed URLs) in reports.
            raise RuntimeError(f'ADB failed: {completed.stderr.decode(errors="replace")[:200]}')
        if return_completed:
            return completed
        return completed.stdout if binary else completed.stdout.decode('utf-8', errors='replace')

    def result_file(self):
        # One fixed-file roundtrip. Native publication uses atomic rename.
        script = (f'if [ -f files/result.json ]; then printf "QA_FILE:"; '
                  f'wc -c < files/result.json; head -c {RESULT_BYTE_LIMIT+1} files/result.json; '
                  'else printf QA_MISSING; fi')
        # exec-out's client escapes every arg after the command. Pass the raw
        # sh -c body; quoting it here would add a second literal quote layer.
        completed = self.call('exec-out', 'run-as', PACKAGE, 'sh', '-c', script,
                             timeout=3, check=False, return_completed=True)
        raw = completed.stdout
        transport = {'transport_returncode': completed.returncode}
        if completed.returncode != 0:
            return {**transport, 'exists': None, 'type': 'transport_error',
                    'read_bytes': len(raw), 'raw_sha256': digest(raw)}, None
        if raw == b'QA_MISSING':
            return {**transport, 'exists': False}, None
        header, separator, body = raw.partition(b'\n')
        match = re.fullmatch(rb'QA_FILE:\s*(\d+)\s*', header)
        if not separator or not match:
            return {**transport, 'exists': None, 'type': 'invalid_file_marker',
                    'read_bytes': len(raw), 'raw_sha256': digest(raw)}, None
        size = int(match[1])
        metadata = {**transport, 'exists': True, 'declared_bytes': size, 'read_bytes': len(body),
                    'raw_sha256': digest(body)}
        if size > RESULT_BYTE_LIMIT or len(body) > RESULT_BYTE_LIMIT:
            return {**metadata, 'type': 'size_limit'}, None
        if size != len(body):
            return {**metadata, 'type': 'size_mismatch'}, None
        if not body:
            return {**metadata, 'type': 'empty'}, None
        try:
            value = json.loads(body.decode('utf-8'))
        except UnicodeDecodeError:
            return {**metadata, 'type': 'invalid_utf8'}, None
        except json.JSONDecodeError:
            return {**metadata, 'type': 'invalid_json'}, None
        return {**metadata, 'type': 'json_object' if isinstance(value, dict) else 'json_other'}, value

    def processes(self):
        lines = self.call('shell', 'ps -A -o PID,NAME').splitlines()
        if not lines or lines[0].split() != ['PID', 'NAME'] or len(lines) < 2:
            raise RuntimeError('Process inventory is missing or invalid')
        rows = lines[1:]
        return {int(parts[0]): parts[1] for row in rows if len(parts := row.split()) >= 2}

    def protected_packages(self):
        """Read APK identities only, never app data; parserqa is the sole mutation target."""
        names = self.call('shell', 'pm list packages kazumi').splitlines()
        snapshot = {}
        for line in names:
            name = line.removeprefix('package:').strip()
            if name == PACKAGE:
                continue
            if not re.fullmatch(r'[A-Za-z0-9_.]+', name):
                raise RuntimeError('Invalid protected package inventory')
            remote = self.call('shell', f'pm path {name}').strip().removeprefix('package:')
            if not re.fullmatch(r'/data/app/[A-Za-z0-9_./+=~-]+\.apk', remote):
                raise RuntimeError('Protected package requires one known APK path')
            apk_hash = self.call('shell', f'sha256sum {remote}').split()[0]
            if not re.fullmatch(r'[a-fA-F0-9]{64}', apk_hash):
                raise RuntimeError('Invalid protected package APK digest')
            snapshot[name] = {'apk_path': remote, 'sha256': apk_hash.lower()}
        return snapshot

    def send_lifecycle_key(self, keycode):
        if keycode not in ('4', '23'):
            raise ValueError('Unsupported QA lifecycle key')
        try:
            foreground = self.call('shell', 'dumpsys', 'activity', 'activities', timeout=8)
        except (RuntimeError, subprocess.TimeoutExpired):
            return False
        if not expected_qa_foreground(foreground):
            return False
        self.call('shell', 'input', 'keyevent', keycode)
        return True

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

    def qa_file(self, name):
        if name not in ('qa-launch-probe.json', 'launch-only-result.json', 'result.json'):
            raise ValueError('Unknown fixed QA evidence file')
        state = self.call('shell', f"run-as {PACKAGE} sh -c 'if [ -f files/{name} ]; then printf FILE:; wc -c < files/{name}; else printf MISSING; fi'", timeout=3).strip()
        if state == 'MISSING':
            return {'exists': False}, None
        match = re.fullmatch(r'FILE:\s*(\d+)', state)
        if not match:
            return {'exists': None, 'type': 'stat_unconfirmed'}, None
        size = int(match[1])
        if size > 32768:
            return {'exists': True, 'declared_bytes': size, 'type': 'size_limit'}, None
        budget = self.budget()
        completed = subprocess.run([self.adb, '-s', self.serial, 'exec-out', 'run-as', PACKAGE,
            'head', '-c', '32769', f'files/{name}'], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=3 if budget is None else budget.cap(3))
        if budget is not None:
            budget.check()
        meta, value = launch_file_decode(completed.stdout, size)
        meta.update(exists=True, transport_returncode=completed.returncode)
        return meta, value if completed.returncode == 0 else None

    def launch_file(self, name, key):
        if name not in ('qa-launch-probe.json', 'launch-only-result.json'):
            raise ValueError('Unknown fixed QA launch file')
        meta, value = self.qa_file(name)
        if meta.get('exists') is not True:
            return meta, None
        validator = validate_launch_journal if name == 'qa-launch-probe.json' else validate_launch_result
        valid = validator(value, key)
        meta['schema_valid'] = valid
        return meta, value if valid else None

    def case(self, config, output, key):
        self._last_case_stop = self._last_protected_after = None
        budget = getattr(self, '_next_case_budget', None)
        if budget is None:
            now = time.monotonic()
            parent = getattr(self, '_parent_budget', None)
            budget = HostDeadline(started=now, end=min(now+70, parent.end) if parent else now+70)
        self._next_case_budget = None
        work = budget.child(budget.end-15)  # Reserve only, not a cleanup guarantee.
        with self.deadline_scope(work):
            return self._case(config, output, key, budget, work)

    def _case(self, config, output, key, budget, work):
        launch = launch_only_spec(config)
        if launch and (not getattr(self, 'launch_allowed', False) or getattr(self, 'physical', False)):
            raise ValueError('Offline launch-only artifact gate required')
        lifecycle = lifecycle_spec(config)
        startup_evidence = {'am': {}, 'files': {}}
        launch_evidence = startup_evidence if launch else None
        launch_journal = launch_candidate = None
        driver, phase_seen = None, None
        baseline = None
        samples, stop = [], threading.Event()
        def monitor():
            # This thread keeps this generation's immutable deadline even if
            # another case is later admitted on the main thread.
            with self.deadline_scope(work):
                while not stop.is_set() and work.remaining() > 0:
                    try:
                        samples.append(self.memory(baseline))
                    except (RuntimeError, subprocess.TimeoutExpired, HostBudgetExpired):
                        pass
                    stop.wait(min(1, work.remaining()))
        worker = threading.Thread(target=monitor, daemon=True)
        started = budget.started
        worker_started = False
        result, primary_error = None, None
        cleanup_errors = []
        try:
            work.check()
            initial = self.stop_and_verify()
            if initial['status'] != 'confirmed':
                cleanup_errors.append({'step': 'cold_start', 'details': initial})
                raise RuntimeError('QA cold-start process exit was not confirmed')
            launch_files = ' files/qa-launch-probe.json files/qa-launch-probe.json.tmp files/launch-only-result.json files/launch-only-result.json.tmp' if launch else ''
            sent_config = {**config, 'launch_attempt_key': key} if launch else config
            self.call('shell', f"run-as {PACKAGE} sh -c 'mkdir -p files; rm -f files/result.json files/lifecycle-state.json{launch_files}; cat > files/case.json'",
                      input=json.dumps(sent_config, ensure_ascii=False).encode())
            if launch:
                for name in ('qa-launch-probe.json', 'launch-only-result.json'):
                    meta, _ = self.launch_file(name, key)
                    if meta.get('exists') is not False:
                        raise RuntimeError('QA launch journal cold-start precondition failed')
            baseline = self.processes()
            worker.start()
            worker_started = True
            try:
                am_timeout = work.cap(20)
                am = self.call('shell', f'am start -W -n {PACKAGE}/{ACTIVITY}', timeout=am_timeout)
                startup_evidence['am'] = {'host_wait_seconds': am_timeout, 'timed_out': False, **launch_am_fields(am)}
                if config.get('selection_tail1') is True and (startup_evidence['am'].get('Status') != 'ok' or startup_evidence['am'].get('expected_activity') is not True):
                    raise RuntimeError('QA discovery activity start not confirmed')
            except subprocess.TimeoutExpired as error:
                startup_evidence['am'] = {'host_wait_seconds': am_timeout, 'timed_out': True,
                    **launch_am_fields(error.stdout), **launch_am_fields(error.stderr)}
                raise
            while work.remaining() > 0:
                if config.get('selection_tail1') is True and not any(n == PACKAGE or n.startswith(PACKAGE + ':') for n in self.processes().values()):
                    startup_evidence['process_exit_observed'] = True
                    raise RuntimeError('QA discovery process exited before receipt')
                if launch:
                    if not any(n == PACKAGE or n.startswith(PACKAGE + ':') for n in self.processes().values()):
                        launch_evidence['process_exit_observed'] = True
                        raise RuntimeError('QA launch process exited before receipt')
                    meta, candidate = self.launch_file('launch-only-result.json', key)
                    launch_evidence['files']['launch-only-result.json'] = meta
                    if candidate is not None:
                        launch_candidate = candidate
                        result = dict(candidate)
                        break
                    time.sleep(min(1, work.remaining()))
                    continue
                metadata, candidate = self.result_file()
                work.check()
                startup_evidence['files']['result.json'] = metadata
                if isinstance(candidate, dict):
                    ids = {config['id']}
                    if lifecycle and lifecycle['action'] == 'switch':
                        ids.add(lifecycle['target']['id'])
                    if candidate.get('id') not in ids or candidate.get('engine') != config['engine']:
                        raise RuntimeError('QA result case identity mismatch')
                    result = candidate
                    break
                if metadata.get('exists') is not False:
                    raise RuntimeError('QA result file protocol invalid')
                if candidate is None:
                    if lifecycle is not None and driver is None:
                        state_text = self.call('exec-out', 'run-as', PACKAGE, 'cat',
                                               'files/lifecycle-state.json', check=False)
                        try:
                            state = json.loads(state_text)
                        except json.JSONDecodeError:
                            state = {}
                        if (state.get('generation') == 1 and state.get('case_id') == config['id'] and
                                state.get('phase') == lifecycle['trigger_phase'] and state.get('stage') == 'started'):
                            phase_seen = phase_seen or time.monotonic()
                            if time.monotonic() - phase_seen >= 0.8:
                                keycode = '4' if lifecycle['action'] == 'exit' else '23'
                                if not self.send_lifecycle_key(keycode):
                                    driver = {'status': 'not_sent_foreground_mismatch',
                                              'expected_component': f'{PACKAGE}/{ACTIVITY}'}
                                    result = {'id': config['id'], 'engine': config['engine'],
                                              'stage': 'environment_invalid',
                                              'reason': 'QA foreground activity not confirmed'}
                                    break
                                driver = {'status': 'triggered', 'action': lifecycle['action'],
                                          'keycode': int(keycode), 'phase': state['phase'],
                                          'generation': 1, 'triggered_epoch': time.time()}
                    time.sleep(min(1, work.remaining()))
            if result is None:
                raise HostBudgetExpired('QA result not received before cleanup reserve')
            work.check()
            result_metadata = (launch_evidence['files']['launch-only-result.json'] if launch else
                               startup_evidence['files'].get('result.json'))
            atomic_json(output / f'{key}.provisional.json',
                        {'key':key, 'metadata':result_metadata, 'result':result,
                         'budget':budget.receipt(), 'work_budget':work.receipt(),
                         'terminal':False}, work)
            if lifecycle is not None:
                result['lifecycle_driver'] = driver or {'status': 'not_triggered'}
                if not lifecycle_result_observed(config, result, driver):
                    result['observed_stage'] = result['stage']
                    result['stage'] = 'environment_invalid'
                    result['lifecycle_driver']['observation'] = 'UI transition or generation guard not confirmed'
            result['host_elapsed_ms'] = round((time.monotonic() - started) * 1000)
        except BaseException as error:
            primary_error = error
        finally:
            self._budget_local.value = budget
            stop.set()
            host_cleanup = cleanup_step(cleanup_errors, 'case_stop', lambda: self.stop_and_verify(baseline))
            if not launch:
                if (primary_error is not None and 'result.json' not in startup_evidence['files'] and
                        budget.remaining() > 0):
                    try:
                        metadata, _ = self.qa_file('result.json')
                        startup_evidence['files']['result.json'] = metadata
                    except Exception as error:
                        startup_evidence['files']['result.json'] = {'exists': None, **error_record(error)}
                cleanup_step(cleanup_errors, 'startup_evidence_write', lambda:
                    (output / f'{key}.startup-evidence.json').write_text(json.dumps(startup_evidence, indent=2), encoding='utf-8'))
            if launch:
                for name in ('qa-launch-probe.json', 'launch-only-result.json'):
                    try:
                        if name == 'launch-only-result.json' and launch_candidate is not None:
                            meta, value = launch_evidence['files'][name], launch_candidate
                        else:
                            meta, value = self.launch_file(name, key)
                        launch_evidence['files'][name] = meta
                        if value is not None:
                            (output / f'{key}.{name}').write_text(json.dumps(value, indent=2), encoding='utf-8')
                            if name == 'qa-launch-probe.json':
                                launch_journal = value
                    except Exception as error:
                        launch_evidence['files'][name] = {'exists': None, **error_record(error)}
                cleanup_step(cleanup_errors, 'launch_evidence_write', lambda:
                    (output / f'{key}.launch-evidence.json').write_text(json.dumps(launch_evidence, indent=2), encoding='utf-8'))
                if primary_error is None and result is not None and result.get('stage') == 'launch_ready' and not launch_ready_observed(launch_journal, key):
                    result.update(observed_stage='launch_ready', stage='environment_invalid', reason='offline_launch_checkpoints_not_confirmed')
            if worker_started:
                cleanup_step(cleanup_errors, 'sampler_join', lambda: worker.join(timeout=budget.cap(30)))
                if worker.is_alive():
                    cleanup_errors.append({'step': 'sampler_exit', 'error_type': 'SamplerStillRunning'})
            if getattr(self, '_protected_baseline', None) is not None:
                try:
                    measured = self.protected_packages()
                    budget.check()
                    receipt = {'before':self._protected_baseline, 'after':measured,
                               'unchanged':self._protected_baseline == measured,
                               'measured_budget':budget.receipt()}
                    atomic_json(output / f'{key}.protected-after.json', receipt, budget)
                    self._last_protected_after = receipt
                    if receipt['unchanged'] is not True:
                        raise RuntimeError('Protected APK identity changed')
                except BaseException as error:
                    cleanup_errors.append({'step':'protected_after', **error_record(error)})
            try:
                budget.check()
            except HostBudgetExpired as error:
                primary_error = primary_error or error
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
            primary_error.qa_host_budget = budget.receipt()
            primary_error.qa_work_budget = work.receipt()
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
        result['host_budget'] = budget.receipt()
        budget.check()
        if host_cleanup['status'] == 'confirmed':
            self._last_case_stop = host_cleanup
        return result

class BatchCleanupError(RuntimeError):
    pass


def run_batch(device, plan, output, rows, *, fixture_media=None, budget_seconds=1800,
              server_factory=ThreadingHTTPServer, budget=None):
    """Execute a preflighted plan; every teardown action has its own guard."""
    prior_final = read_receipt(output / 'cleanup.json')
    terminal_records = {r['key']:terminal_record_digest(r) for r in rows
                        if 'host_budget' in r and final_receipt_confirms(r, prior_final)}
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
    pending = [p for p in plan if p['key'] not in completed]
    budget = budget or HostDeadline(min(budget_seconds, 70) if len(pending) <= 1 else budget_seconds)
    reserve = 60 if len(pending) > 1 else 0
    budget_unknown_keys, active_key = [], None
    if isinstance(device, Device):
        device._parent_budget = budget
    try:
        budget.check()
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
            origin = budget.started if active_key is None else time.monotonic()
            case_budget = budget.child(min(origin+70, budget.end-reserve), started=origin)
            if ((output / 'STOP').exists() or case_budget.remaining() <= 15 or
                    (reserve and budget.remaining() < 70+reserve)):
                stop_reason = 'stop_requested' if (output / 'STOP').exists() else 'budget'
                break
            active_key = key
            if isinstance(device, Device):
                device._next_case_budget = case_budget
            with attempts.open('a', encoding='utf-8') as f:
                f.write(json.dumps({'key': key, 'id': item['id'], 'engine': item['engine'],
                                    'group': item['group'], 'repeat': item['repeat'],
                                    'started_epoch': time.time()}) + '\n')
                f.flush()
            row = device.case(config, output, key)
            case_budget.check()
            if row.get('stage') in ('sample_identity_mismatch', 'console_observation_not_run'):
                row.update(observed_stage=row['stage'], stage='environment_invalid',
                           reason='fixed QA observation or episode identity precondition failed')
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
                       compatibility=('console hints only; no native media player' if config.get('console_hint_observer') is True else
                           'offline startup only; network denied; no search/parser/player' if config.get('launch_only') is True else
                           'production capability factory and default headers/player controller'
                           if config['engine'] == 'app' else 'controlled shared script; bounded nested HTML fallback; no WebView66 adapter'))
            if config.get('selection_only') is True:
                row['selection_only'] = True
            if config.get('launch_only') is True:
                row['launch_only'] = True
            if config.get('console_hint_observer') is True:
                row['console_only'] = True
            if row.get('cleanup') != 'confirmed' or row.get('host_cleanup', {}).get('status') != 'confirmed':
                stop_reason = 'case_cleanup_unconfirmed'
                cleanup_errors.append({'step': 'case_cleanup', 'key': key,
                                       'app_cleanup': row.get('cleanup'), 'host_cleanup': row.get('host_cleanup')})
                atomic_json(output / f'{key}.unconfirmed.json', row)
                break  # Preserve observation, never publish an unconfirmed terminal.
            row['host_budget'] = case_budget.receipt()
            atomic_json(output / f'{key}.terminal.json', row, case_budget)
            with ledger.open('a', encoding='utf-8') as f:
                f.write(json.dumps(row, ensure_ascii=False) + '\n')
                f.flush()
                os.fsync(f.fileno())
            case_budget.check()
            terminal_records[key] = terminal_record_digest(row)
            rows.append(row)
            print(json.dumps({k: row.get(k) for k in ('id', 'engine', 'stage', 'host_elapsed_ms', 'cleanup')}, ensure_ascii=False), flush=True)
            if row['stage'] in ('host_timeout', 'environment_invalid', 'unknown'):
                stop_reason = row['stage']
                break
            if row['stage'] == 'console_hint_pending_review':
                stop_reason = 'console_hint_pending_review'
                break
            if row['stage'] == 'captcha':
                stop_reason = 'selection_challenge' if row.get('selection_only') is True else 'challenge'
                break
    except BaseException as error:
        primary_error = error
        stop_reason = ('budget' if isinstance(error, HostBudgetExpired) else
                       'interrupted' if isinstance(error, KeyboardInterrupt) else 'host_error')
        if isinstance(error, HostBudgetExpired) and active_key is not None:
            budget_unknown_keys.append(active_key)
    finally:
        cached_stop = getattr(device, '_last_case_stop', None) if isinstance(device, Device) else None
        final_stop = ({**cached_stop, 'reused_confirmed_case_stop':True} if cached_stop is not None
                      else cleanup_step(cleanup_errors, 'final_force_stop', device.stop_and_verify))
        if final_stop is not None and final_stop['status'] != 'confirmed':
            cleanup_errors.append({'step': 'final_process_exit', 'details': final_stop})
        if server is not None:
            if server_thread is not None and server_thread.ident is not None:
                def shutdown_fixture():
                    errors = []
                    def close():
                        try:
                            server.shutdown()
                        except BaseException as error:
                            errors.append(error)
                    budget.check()
                    shutdown = threading.Thread(target=close, daemon=True)
                    shutdown.start()
                    shutdown.join(timeout=budget.cap(2))
                    if shutdown.is_alive():
                        raise HostBudgetExpired('Owned fixture shutdown unconfirmed')
                    if errors:
                        raise errors[0]
                    budget.check()
                cleanup_step(cleanup_errors, 'fixture_shutdown', shutdown_fixture)
            cleanup_step(cleanup_errors, 'fixture_close', server.server_close)
        for port in reverse_ports:
            cleanup_step(cleanup_errors, f'reverse_remove_{port}', lambda port=port:
                         device.call('reverse', '--remove', f'tcp:{port}'))
        if server_thread is not None and server_thread.ident is not None:
            cleanup_step(cleanup_errors, 'fixture_thread_join', lambda: server_thread.join(timeout=budget.cap(2)))
            if server_thread.is_alive():
                cleanup_errors.append({'step': 'fixture_thread_exit', 'error_type': 'FixtureThreadStillRunning'})
        status = {'stop_reason': stop_reason,
                  'terminal_records':terminal_records,
                  'host_budget':budget.receipt(), 'budget_unknown_keys':budget_unknown_keys,
                  'unconfirmed_terminal_keys': [r['key'] for r in rows if r['key'] not in completed] if cleanup_errors else [],
                  'case_budget':getattr(primary_error, 'qa_host_budget', None),
                  'case_work_budget':getattr(primary_error, 'qa_work_budget', None),
                  'primary_error': error_record(primary_error) if primary_error is not None else None,
                  'case_host_cleanup': getattr(primary_error, 'qa_cleanup', None),
                  'final_host_cleanup': final_stop, 'cleanup_errors': cleanup_errors}
        cleanup_step(cleanup_errors, 'run_status_write', lambda: atomic_json(output / 'run-status.json', status))
        cleanup_step(cleanup_errors, 'cleanup_receipt_write', lambda:
            atomic_json(output / 'cleanup.json', status))
        report = cleanup_step(cleanup_errors, 'report_rebuild', lambda: build_report(output))
        if report is not None:
            report['run_status'] = status
            cleanup_step(cleanup_errors, 'summary_write', lambda:
                (output / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8'))
            if budget.remaining() > 0.25:
                cleanup_step(cleanup_errors, 'html_write', lambda:
                    (output / 'report.html').write_text('<meta charset="utf-8"><title>Parser QA</title><h1>Parser QA</h1><p>QA results. Environment-invalid and infrastructure results are excluded from product metrics; null coverage means unknown.</p><pre>' + html.escape(json.dumps(report, ensure_ascii=False, indent=2)) + '</pre>', encoding='utf-8'))
        status['host_budget'] = budget.receipt()
        if not status['host_budget']['within_deadline']:
            status['stop_reason'] = 'budget'
            if active_key is not None and active_key not in budget_unknown_keys:
                budget_unknown_keys.append(active_key)
            atomic_json(output / 'run-status.json', status)
            atomic_json(output / 'cleanup.json', status)
            report = build_report(output)
            atomic_json(output / 'summary.json', report)
            primary_error = primary_error or HostBudgetExpired('QA batch final deadline exhausted')
    if primary_error is not None:
        raise primary_error.with_traceback(primary_error.__traceback__)
    if cleanup_errors:
        raise BatchCleanupError('Batch stopped with unconfirmed cleanup; see cleanup.json')
    return report


def _main():
    cli_started = time.monotonic()
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--adb', required=True)
    p.add_argument('--serial', required=True)
    p.add_argument('--allow-physical-qa', action='store_true')
    p.add_argument('--expect-serial')
    p.add_argument('--expect-fingerprint')
    p.add_argument('--apk', type=Path, required=True)
    p.add_argument('--manifest', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--fixture-media', type=Path)
    p.add_argument('--aapt', type=Path, help='Required for offline launch-only APK permission verification')
    p.add_argument('--repeats', type=int, default=1)
    p.add_argument('--engines', default='app', help='app (production service path) or webview,gecko (controlled A/B)')
    p.add_argument('--expect-sdk', type=int)
    p.add_argument('--expect-webview')
    p.add_argument('--budget-seconds', type=int, default=1800)
    args = p.parse_args()
    budget = HostDeadline(args.budget_seconds, started=cli_started)
    budget.output = args.output
    engines = tuple(args.engines.split(','))
    if not engines or len(set(engines)) != len(engines) or not set(engines) <= {'app', 'webview', 'gecko'}:
        p.error('Engines must be unique values from app,webview,gecko')
    if not 1 <= args.repeats <= 5 or not 1 <= args.budget_seconds <= 1800:
        p.error('repeats 1..5, total budget 1..1800 seconds')
    manifest = json.loads(args.manifest.read_text(encoding='utf-8-sig'))
    cases = manifest['cases']
    if len(cases) * len(engines) * args.repeats == 1:
        budget = budget.child(cli_started+70)
    budget.planned_count = len(cases) * len(engines) * args.repeats
    launch = any(launch_only_spec(c) for c in cases)
    artifact = json.loads((args.apk.parent / 'artifact.json').read_text(encoding='utf-8-sig'))
    try:
        console = console_only_batch_spec(cases, artifact, engines, args.repeats, args.fixture_media, args.allow_physical_qa)
    except ValueError as error:
        p.error(str(error)) # Only our fixed messages, never request data.
    if console:
        if args.aapt is None:
            p.error('Console-only QA requires APK permission verification')
        permissions = subprocess.run([str(args.aapt), 'dump', 'permissions', str(args.apk)], capture_output=True, timeout=budget.cap(10))
        budget.check()
        if permissions.returncode != 0 or b'android.permission.INTERNET' not in permissions.stdout or f'package: {PACKAGE}'.encode() not in permissions.stdout:
            p.error('Console-only ordinary QA APK verification failed')
    tail = any(c.get('selection_tail1') is True for c in cases)
    if tail:
        if (engines != ('app',) or args.repeats != 1 or args.fixture_media is not None or
            any(c.get('selection_only') is not True for c in cases) or
            artifact.get('launch_only_build') is not False or artifact.get('internet_permission') is not True or args.aapt is None):
            p.error('Tail discovery requires ordinary network QA artifact and selection-only App plan')
        permissions = subprocess.run([str(args.aapt), 'dump', 'permissions', str(args.apk)], capture_output=True, timeout=budget.cap(10))
        budget.check()
        if (permissions.returncode != 0 or b'android.permission.INTERNET' not in permissions.stdout or
            f'package: {PACKAGE}'.encode() not in permissions.stdout):
            p.error('Network QA APK permission verification failed')
    if launch or artifact.get('launch_only_build') is True:
        if (not launch or len(cases) != 1 or engines != ('app',) or args.repeats != 1 or args.fixture_media is not None or
            args.allow_physical_qa or artifact.get('launch_only_build') is not True or
            artifact.get('no_internet_permission') is not True or args.aapt is None):
            p.error('Exactly one fixed offline launch case and verified offline artifact required')
        permissions = subprocess.run([str(args.aapt), 'dump', 'permissions', str(args.apk)], capture_output=True, timeout=budget.cap(10))
        budget.check()
        if (permissions.returncode != 0 or b'android.permission.INTERNET' in permissions.stdout or
            f'package: {PACKAGE}'.encode() not in permissions.stdout):
            p.error('Offline APK permission verification failed')
    if len(cases) * len(engines) * args.repeats > 24:
        p.error('At most 24 attempts per run')
    for c in cases:
        if 'rule_file' in c:
            rule_path = args.manifest.parent / c.pop('rule_file')
            c['rule'] = json.loads(rule_path.read_text(encoding='utf-8-sig'))
    device = Device(args.adb, args.serial,
                    allow_physical=args.allow_physical_qa,
                    expected_serial=args.expect_serial,
                    expected_fingerprint=args.expect_fingerprint, budget=budget)
    device.launch_allowed = launch
    sdk = int(device.call('shell', 'getprop ro.build.version.sdk').strip())
    provider_state = device.call('shell', 'dumpsys webviewupdate')
    match = re.search(r'Current WebView package \(name, version\): \(([^,]+), ([^)]+)\)', provider_state)
    provider = '/'.join(match.groups()) if match else None
    if args.expect_sdk is not None and sdk != args.expect_sdk:
        raise RuntimeError('Android SDK does not match the requested test environment')
    if args.expect_webview is not None and (not match or match[2] != args.expect_webview):
        raise RuntimeError('Actual selected WebView does not match the requested version')
    if console and (sdk != 28 or provider != 'com.android.webview/66.0.3359.158'):
        raise RuntimeError('Fixed console observation environment does not match')
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
                'serial': args.serial, 'physical_qa': args.allow_physical_qa,
                'expected_fingerprint': args.expect_fingerprint,
                'build_fingerprint': device.fingerprint if device.physical else device.call('shell', 'getprop ro.build.fingerprint').strip(),
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
    protected_before = device.protected_packages() if device.physical else None
    device._protected_baseline = protected_before
    if device.physical:
        (args.output / 'protected-packages-before.json').write_text(
            json.dumps(protected_before, indent=2), encoding='utf-8')
    try:
        run_batch(device, plan, args.output, rows, fixture_media=args.fixture_media,
                  budget_seconds=args.budget_seconds, budget=budget)
    finally:
        if device.physical:
            original_error = sys.exc_info()[0]
            try:
                receipt = getattr(device, '_last_protected_after', None)
                if receipt is None:
                    protected_after = device.protected_packages()
                    budget.check()
                    receipt = {'before': protected_before, 'after': protected_after,
                               'unchanged': protected_before == protected_after}
                else:
                    receipt = {**receipt, 'reused_same_CLI_last_case_measurement':True}
            except Exception as error:
                receipt = {'unchanged': None, **error_record(error)}
            atomic_json(args.output / 'protected-packages-after.json', receipt)
            if budget.remaining() <= 0:
                status_path = args.output / 'run-status.json'
                status = json.loads(status_path.read_text()) if status_path.exists() else {}
                unknown_keys = set(status.get('budget_unknown_keys', [])) | {
                    r['key'] for r in rows if r['key'] not in completed}
                status.update(stop_reason='budget', host_budget=budget.receipt(),
                              budget_unknown_keys=sorted(unknown_keys))
                atomic_json(status_path, status)
                atomic_json(args.output / 'summary.json', build_report(args.output))
                if original_error is None:
                    raise HostBudgetExpired('QA CLI deadline exhausted')
            if receipt['unchanged'] is not True and original_error is None:
                raise RuntimeError('Protected APK identity not confirmed unchanged')


def main():
    try:
        return _main()
    except (HostBudgetExpired, subprocess.TimeoutExpired) as error:
        output = getattr(error, 'qa_output', None)
        if output is not None and not (output / 'attempts.jsonl').exists():
            output.mkdir(parents=True, exist_ok=True)
            atomic_json(output / 'preflight-budget.json', {
                'stage':'preflight_budget', 'started':0, 'unknown':0,
                'unattempted':getattr(error, 'preflight_planned', None),
                'host_budget':getattr(error, 'host_budget', None),
                'device_launch_attempted':False})
        raise


if __name__ == '__main__':
    main()
