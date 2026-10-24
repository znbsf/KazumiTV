import unittest
from run import lifecycle_spec, lifecycle_result_observed


class LifecycleDriverTests(unittest.TestCase):
    def config(self):
        return {'id': 'old', 'engine': 'app', 'app_gecko_fallback': True,
                'url': 'http://127.0.0.1:8769/lifecycle-slow',
                'qa_lifecycle': {'action': 'exit', 'trigger_phase': 'primary'}}

    def test_disabled_and_explicit_fixture(self):
        self.assertIsNone(lifecycle_spec({'engine': 'app'}))
        self.assertEqual(lifecycle_spec(self.config())['action'], 'exit')

    def test_real_sources_or_arbitrary_actions_rejected_before_device_work(self):
        for changes in [{'url': 'https://example.invalid/page'}, {'rule': {}},
                        {'rule_file': 'rule.json'}, {'engine': 'gecko'},
                        {'app_gecko_fallback': 'yes'},
                        {'qa_lifecycle': {'action': 'shell', 'trigger_phase': 'primary'}}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                lifecycle_spec({**self.config(), **changes})

    def test_switch_requires_distinct_local_page_and_identity(self):
        config = self.config()
        config['qa_lifecycle'] = {'action': 'switch', 'trigger_phase': 'primary',
                                 'target': {'id': 'next', 'url': 'http://127.0.0.1:8769/video-next'}}
        self.assertEqual(lifecycle_spec(config)['target']['id'], 'next')
        for bad in [{'id': 'old'}, {'url': config['url']}, {'url': 'https://example.invalid'},
                    {'rule': {}}, {'id': 4}]:
            target = {**config['qa_lifecycle']['target'], **bad}
            with self.subTest(target=target), self.assertRaises(ValueError):
                lifecycle_spec({**config, 'qa_lifecycle': {**config['qa_lifecycle'], 'target': target}})

    def test_sent_key_is_not_evidence_that_the_page_actually_exited(self):
        self.assertFalse(lifecycle_result_observed(self.config(), {'stage': 'first_frame'}, {'status': 'triggered'}))
        self.assertFalse(lifecycle_result_observed(self.config(), {'stage': 'lifecycle_cancelled',
                         'lifecycle': {'actual_page_disposals': 0}}, {'status': 'triggered'}))

    def test_actual_disposal_suppression_and_native_stale_rejection_are_required(self):
        row = {'stage': 'lifecycle_cancelled', 'old_result_suppressed': True,
               'lifecycle': {'actual_page_disposals': 1,
                             'events': [{'stage': 'ui_transition', 'generation': 1},
                                        {'stage': 'native_stale_result_probe', 'accepted': False}],
                             'children': [{'cancelled_by_ui': True, 'normal_publication_allowed': False}]}}
        self.assertTrue(lifecycle_result_observed(self.config(), row, {'status': 'triggered'}))
        row['lifecycle']['events'][1]['accepted'] = True
        self.assertFalse(lifecycle_result_observed(self.config(), row, {'status': 'triggered'}))


if __name__ == '__main__':
    unittest.main()
