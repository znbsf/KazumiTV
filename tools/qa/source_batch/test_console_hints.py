"""Offline host contracts; mock device only, no APK, ADB or source requests."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

from run import console_only_batch_spec, run_batch, summarize
from test_runner_integrity import plan, result


class ConsoleHintsTests(unittest.TestCase):
    def case(self):
        return {'id': 'qa-mgnacg-console-hints-v1', 'group': 'console-hints',
                'console_hint_observer': True}

    def artifact(self):
        return {'launch_only_build': False, 'internet_permission': True,
                'console_hint_observer_schema': 1}

    def check(self, cases=None, artifact=None, engines=('app',), repeats=1,
              fixture_media=None, physical=False):
        return console_only_batch_spec(cases if cases is not None else [self.case()],
            artifact if artifact is not None else self.artifact(), engines,
            repeats, fixture_media, physical)

    def test_default_off_keeps_ordinary_batch_and_nonboolean_rejected(self):
        self.assertFalse(self.check(cases=[{'id': 'ordinary'}], artifact={}))
        self.assertFalse(self.check(cases=[{'console_hint_observer': False}], artifact={}))
        for value in (None, 0, 1, 'true', [], {}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.check(cases=[{'console_hint_observer': value}])

    def test_old_artifact_and_every_host_scope_expansion_fail_closed(self):
        self.assertTrue(self.check())
        for key in self.artifact():
            artifact = self.artifact()
            artifact.pop(key)
            with self.subTest(missing=key), self.assertRaises(ValueError):
                self.check(artifact=artifact)
        for value in (True, 0, 2, '1'):
            with self.subTest(schema=value), self.assertRaises(ValueError):
                self.check(artifact={**self.artifact(), 'console_hint_observer_schema': value})
        for changes in ({'engines': ('gecko',)}, {'repeats': 2}, {'physical': True},
                        {'fixture_media': Path('synthetic.mp4')},
                        {'cases': [self.case(), self.case()]},
                        {'cases': [{**self.case(), 'id': 'other'}]},
                        {'cases': [{**self.case(), 'group': 'other'}]}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.check(**changes)

    def test_console_rows_never_enter_playback_metrics_even_if_parser_resolved(self):
        for stage in ('resolve_timeout', 'console_observation_complete',
                      'console_hint_pending_review', 'first_frame'):
            summary = summarize([result(console_only=True, stage=stage), result('playback')])[0]
            self.assertEqual(summary['attempted'], 2)
            self.assertEqual(summary['console_only_results'], 1)
            self.assertEqual(summary['eligible_results'], 1)
            self.assertEqual(summary['resolved'], 1)
            self.assertEqual(summary['first_frame'], 1)

    def test_challenge_hint_stops_without_claiming_captcha_and_preserves_cleanup(self):
        self.run_mock('console_hint_pending_review', 'console_hint_pending_review', 0)

    def test_unavailable_observer_is_invalid_and_stops_without_playback_failure(self):
        self.run_mock('console_observation_not_run', 'environment_invalid', 1)

    def run_mock(self, stage, stop_reason, invalid):
        device = Mock()
        device.case.return_value = result(stage=stage, challenge_confirmed=False)
        device.stop_and_verify.return_value = {'status': 'confirmed'}
        pending = plan(2)
        for item in pending:
            item['config']['console_hint_observer'] = True
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()):
            report = run_batch(device, pending, Path(temp), [])
            row = json.loads((Path(temp) / 'results.jsonl').read_text())
        self.assertEqual(device.case.call_count, 1)
        device.stop_and_verify.assert_called_once()
        self.assertEqual(report['run_status']['stop_reason'], stop_reason)
        self.assertEqual(report['summary'][0]['invalid'], invalid)
        self.assertEqual(report['summary'][0]['eligible_results'], 0)
        self.assertTrue(row['console_only'])
        self.assertFalse(row['challenge_confirmed'])
        self.assertNotEqual(row['stage'], 'captcha')
        if invalid:
            self.assertEqual(row['observed_stage'], stage)


if __name__ == '__main__':
    unittest.main()
