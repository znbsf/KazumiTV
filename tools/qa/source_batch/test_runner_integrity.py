import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

from report import render
from run import (BatchCleanupError, Device, PACKAGE, build_report,
                 classified_stage, run_batch, summarize)


def result(key='k0', **changes):
    row = dict(key=key, id=key, group='live', engine='app', repeat=0,
               stage='first_frame', cleanup='confirmed',
               environment={'sdk': 28, 'webview': 'provider/66'},
               timings_ms={'resolve': 400, 'first_frame': 200},
               memory={'sampled_peak_pss_kib': 2048})
    row.update(changes)
    return row


def plan(count):
    return [dict(key=f'k{i}', id=f'case-{i}', engine='app', group='live', repeat=0,
                 config={'id': f'case-{i}', 'engine': 'app', 'group': 'live', 'repeat': 0},
                 expected_environment={'sdk': 28, 'provider': 'provider/66'})
            for i in range(count)]


def write_json(path, value):
    path.write_text(json.dumps(value), encoding='utf-8')


def journal(path, rows):
    path.write_text(''.join(json.dumps(r) + '\n' for r in rows), encoding='utf-8')


class CaseDevice(Device):
    """No ADB executable: faults occur at the same interface as subprocesses."""
    def __init__(self, primary=None, stop_timeout=False, stays_alive=False):
        self.primary = primary
        self.stop_timeout = stop_timeout
        self.stays_alive = stays_alive
        self.stop_calls = self.inventory_calls = 0
        self.alive = False

    def call(self, *args, **kwargs):
        if args[0] == 'shell' and args[1].startswith('am force-stop'):
            self.stop_calls += 1
            if self.stop_calls > 1 and self.stop_timeout:
                raise subprocess.TimeoutExpired('fake-adb', 8)
            if not self.stays_alive:
                self.alive = False
        if args[0] == 'shell' and args[1].startswith('am start'):
            if self.primary is not None:
                raise self.primary
            self.alive = True
        if args[0] == 'exec-out':
            return json.dumps(result())
        return ''

    def processes(self):
        self.inventory_calls += 1
        return {1: 'init', **({77: PACKAGE} if self.alive else {})}

    def memory(self, _):
        return {'processes': [], 'sum_pss_kib': 0}


class IntegrityTests(unittest.TestCase):
    def test_environment_failure_precedes_timeout_and_is_excluded_from_metrics(self):
        invalid = result('bad', stage='environment_invalid',
                         error_type='VideoSourceTimeoutException',
                         timings_ms={'resolve': 99999, 'first_frame': 88888},
                         memory={'sampled_peak_pss_kib': 999999})
        before = json.dumps(invalid, sort_keys=True)
        report = summarize([invalid, result()])[0]
        self.assertEqual(classified_stage(invalid), 'environment_invalid')
        self.assertEqual((report['attempted'], report['invalid'], report['eligible_results']), (2, 1, 1))
        self.assertEqual((report['resolved'], report['first_frame']), (1, 1))
        self.assertEqual(report['resolve_median_ms'], 400)
        self.assertEqual(report['frame_median_ms'], 200)
        self.assertEqual(report['sampled_peak_pss_median_mib'], 2)
        self.assertNotIn('resolve_timeout', report['outcomes'])
        self.assertEqual(json.dumps(invalid, sort_keys=True), before)

    def test_case_cleanup_timeout_preserves_original_exception_and_inventory(self):
        primary = ValueError('original failure')
        device = CaseDevice(primary=primary, stop_timeout=True)
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError) as caught:
                device.case({'id': 'one', 'engine': 'app'}, Path(temp), 'k0')
            self.assertIs(caught.exception, primary)
            receipt = json.loads((Path(temp) / 'k0.host-error.json').read_text())
            self.assertEqual(receipt['primary_error']['error_type'], 'ValueError')
            self.assertEqual(receipt['host_cleanup']['status'], 'unconfirmed')
            self.assertEqual(receipt['host_cleanup']['process_exit'], 'confirmed')
            self.assertEqual(receipt['host_cleanup']['errors'][0]['error_type'], 'TimeoutExpired')
            self.assertGreaterEqual(device.inventory_calls, 3)

    def test_force_stop_success_does_not_prove_process_exit(self):
        device = CaseDevice(stays_alive=True)
        with tempfile.TemporaryDirectory() as temp:
            row = device.case({'id': 'one', 'engine': 'app'}, Path(temp), 'k0')
        self.assertEqual(row['stage'], 'first_frame')
        self.assertEqual(row['host_cleanup']['status'], 'unconfirmed')
        self.assertEqual(row['host_cleanup']['remaining_processes'], {77: PACKAGE})

    def test_batch_interrupt_still_attempts_every_cleanup_and_writes_unknown_scope(self):
        primary = KeyboardInterrupt()
        device = Mock()
        device.case.side_effect = primary
        device.stop_and_verify.side_effect = subprocess.TimeoutExpired('fake-adb', 8)
        def call(*args, **kwargs):
            if args == ('reverse', '--remove', 'tcp:8769'):
                raise subprocess.TimeoutExpired('fake-adb', 8)
            return ''
        device.call.side_effect = call
        server = Mock()
        server.shutdown.side_effect = RuntimeError('fake shutdown failure')
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            write_json(folder / 'identity.json', {'planned_attempts': 2})
            (folder / 'fixture.mp4').write_bytes(b'fake')
            with self.assertRaises(KeyboardInterrupt) as caught:
                run_batch(device, plan(2), folder, [], fixture_media=folder / 'fixture.mp4',
                          server_factory=lambda *_: server)
            self.assertIs(caught.exception, primary)
            server.server_close.assert_called_once()
            self.assertIn((('reverse', '--remove', 'tcp:8768'), {}), device.call.call_args_list)
            report = json.loads((folder / 'summary.json').read_text())
            self.assertEqual([report[k] for k in ('planned', 'completed', 'unknown', 'unattempted')], [2, 0, 1, 1])
            self.assertEqual(report['run_status']['primary_error']['error_type'], 'KeyboardInterrupt')
            steps = {r['step'] for r in report['run_status']['cleanup_errors']}
            self.assertTrue({'final_force_stop', 'fixture_shutdown', 'reverse_remove_8769'} <= steps)
            self.assertTrue((folder / 'cleanup.json').exists())
            self.assertTrue((folder / 'report.html').exists())

    def test_batch_stops_after_case_cleanup_is_unconfirmed(self):
        device = Mock()
        device.case.return_value = result(host_cleanup={'status': 'unconfirmed'})
        device.stop_and_verify.return_value = {'status': 'confirmed'}
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()):
            folder = Path(temp)
            write_json(folder / 'identity.json', {'planned_attempts': 2})
            with self.assertRaises(BatchCleanupError):
                run_batch(device, plan(2), folder, [])
            device.case.assert_called_once()
            report = json.loads((folder / 'summary.json').read_text())
            self.assertEqual([report[k] for k in ('completed', 'unknown', 'unattempted')], [1, 0, 1])
            self.assertEqual(report['run_status']['stop_reason'], 'case_cleanup_unconfirmed')

    def test_batch_retains_observed_stage_but_does_not_count_invalid_environment(self):
        device = Mock()
        device.case.return_value = result(stage='resolve_error', error_type='VideoSourceTimeoutException',
                                          environment={'sdk': 36, 'webview': 'provider/143'})
        device.stop_and_verify.return_value = {'status': 'confirmed'}
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()):
            folder = Path(temp)
            write_json(folder / 'identity.json', {'planned_attempts': 2})
            report = run_batch(device, plan(2), folder, [])
            row = json.loads((folder / 'results.jsonl').read_text())
            self.assertEqual(row['observed_stage'], 'resolve_error')
            self.assertEqual(row['error_type'], 'VideoSourceTimeoutException')
            self.assertEqual(report['summary'][0]['invalid'], 1)
            self.assertEqual(report['summary'][0]['resolved'], 0)
            self.assertEqual(report['summary'][0]['resolve_median_ms'], None)
            device.case.assert_called_once()

    def test_final_stop_failure_is_nonzero_even_after_completed_results(self):
        device = Mock()
        device.case.return_value = result()
        device.stop_and_verify.side_effect = subprocess.TimeoutExpired('fake-adb', 8)
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()):
            folder = Path(temp)
            write_json(folder / 'identity.json', {'planned_attempts': 1})
            with self.assertRaises(BatchCleanupError):
                run_batch(device, plan(1), folder, [])
            report = json.loads((folder / 'summary.json').read_text())
            self.assertEqual(report['completed'], 1)
            self.assertIsNone(report['run_status']['primary_error'])
            self.assertEqual(report['run_status']['cleanup_errors'][0]['error_type'], 'TimeoutExpired')


class CoverageTests(unittest.TestCase):
    def test_rebuild_exposes_completed_unknown_and_unattempted_without_changing_journals(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            write_json(folder / 'identity.json', {'planned_attempts': 4})
            write_json(folder / 'plan.json', [{k: r[k] for k in ('key', 'id', 'engine', 'group', 'repeat')} for r in plan(4)])
            journal(folder / 'attempts.jsonl', [{'key': 'k0'}, {'key': 'k1'}])
            journal(folder / 'results.jsonl', [result()])
            before = {p.name: p.read_bytes() for p in folder.glob('*.jsonl')}
            report = render(folder)
            self.assertEqual([report[k] for k in ('planned', 'started', 'completed', 'unknown', 'unattempted')], [4, 2, 1, 1, 2])
            self.assertEqual({r['key']: r['state'] for r in report['case_states']},
                             {'k0': 'completed', 'k1': 'unknown', 'k2': 'unattempted', 'k3': 'unattempted'})
            self.assertEqual(next(r for r in report['case_states'] if r['key'] == 'k1')['id'], 'case-1')
            self.assertIn('unknown=1', (folder / 'comparison.md').read_text())
            self.assertIn('case-2', (folder / 'report.html').read_text())
            self.assertEqual(render(folder)['unattempted'], 2)
            self.assertEqual(before, {p.name: p.read_bytes() for p in folder.glob('*.jsonl')})

    def test_old_format_without_start_journal_does_not_guess_zero(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            write_json(folder / 'identity.json', {'repeats': 2, 'engines': ['app']})
            journal(folder / 'results.jsonl', [result()])
            report = render(folder)
            self.assertEqual(report['completed'], 1)
            for field in ('planned', 'started', 'unknown', 'unattempted'):
                self.assertIsNone(report[field])
            self.assertIn('unknown=unknown', (folder / 'comparison.md').read_text())

    def test_legacy_planned_count_does_not_invent_unattempted_without_start_journal(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            write_json(folder / 'summary.json', {'planned': 8, 'completed': 1})
            journal(folder / 'results.jsonl', [result()])
            report = build_report(folder)
            self.assertEqual(report['planned'], 8)
            self.assertEqual(report['remaining_without_result'], 7)
            self.assertIsNone(report['unknown'])
            self.assertIsNone(report['unattempted'])

    def test_old_start_journal_can_identify_unknown_but_not_unsaved_plan(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            journal(folder / 'results.jsonl', [result()])
            journal(folder / 'attempts.jsonl', [{'key': 'k0'}, {'key': 'k1', 'id': 'interrupted-case'}])
            report = build_report(folder)
            self.assertEqual((report['completed'], report['unknown']), (1, 1))
            self.assertIsNone(report['planned'])
            self.assertIsNone(report['unattempted'])

    def test_truncated_start_journal_preserves_uncertainty(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            write_json(folder / 'identity.json', {'planned_attempts': 3})
            journal(folder / 'results.jsonl', [result()])
            (folder / 'attempts.jsonl').write_text('{"key":"k0"}\n{"key":', encoding='utf-8')
            report = build_report(folder)
            self.assertIsNone(report['unknown'])
            self.assertIsNone(report['unattempted'])
            self.assertEqual(report['completed'], 1)
            self.assertEqual(report['journal_issues'][0]['line'], 2)

    def test_interruption_inside_utf8_character_keeps_earlier_records(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            write_json(folder / 'identity.json', {'planned_attempts': 2})
            journal(folder / 'results.jsonl', [result()])
            broken = b'{"key":"k0"}\n{"key":"' + '未'.encode('utf-8')[:1]
            (folder / 'attempts.jsonl').write_bytes(broken)
            report = render(folder)
            self.assertEqual(report['completed'], 1)
            self.assertIsNone(report['unknown'])
            self.assertEqual(report['journal_issues'][0]['line'], 2)
            self.assertEqual((folder / 'attempts.jsonl').read_bytes(), broken)


if __name__ == '__main__':
    unittest.main()
