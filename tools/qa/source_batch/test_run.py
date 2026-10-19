import unittest
from run import paired_plan, summarize, classified_stage, Device

class ReportingTests(unittest.TestCase):
    def test_counterbalanced_pairs_use_same_case(self):
        cases = [{'id': 'a', 'url': 'https://example.test/a'}, {'id': 'b', 'url': 'https://example.test/b'}]
        plan = list(paired_plan(cases, 2))
        self.assertEqual([p['engine'] for p in plan],
            ['webview', 'gecko', 'gecko', 'webview', 'gecko', 'webview', 'webview', 'gecko'])
        self.assertEqual(plan[0]['url'], plan[1]['url'])
        self.assertEqual(plan[0]['user_agent'], plan[1]['user_agent'])

    def test_missing_memory_is_not_zero_and_no_match_not_parse_success(self):
        rows = [dict(group='live', engine='gecko', stage='no_match', memory={'sampled_peak_pss_kib': None}),
                dict(group='live', engine='gecko', stage='first_frame',
                     timings_ms={'resolve': 400, 'first_frame': 200}, memory={'sampled_peak_pss_kib': 2048})]
        report = summarize(rows)[0]
        self.assertEqual(report['attempted'], 2)
        self.assertEqual(report['resolved'], 1)
        self.assertEqual(report['first_frame'], 1)
        self.assertEqual(report['sampled_peak_pss_median_mib'], 2)
        self.assertEqual(report['resolve_median_ms'], 400)

    def test_refuses_real_device_before_invoking_adb(self):
        for serial in ['192.168.123.217:5555', '2G97C5ZJ0Y058Q', 'emulator-5580;echo bad']:
            with self.assertRaises(ValueError):
                Device('must-not-execute', serial)

    def test_service_timeout_is_distinct_from_generic_parser_failure(self):
        self.assertEqual(classified_stage({'stage': 'resolve_error',
            'error_type': 'VideoSourceTimeoutException'}), 'resolve_timeout')
        self.assertEqual(classified_stage({'stage': 'resolve_error',
            'error_type': 'PlatformException'}), 'resolve_error')

if __name__ == '__main__':
    unittest.main()
