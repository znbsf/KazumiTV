import unittest
import subprocess
from unittest.mock import Mock, call
from run import ACTIVITY, PACKAGE, Device, expected_qa_foreground


class LifecycleForegroundTests(unittest.TestCase):
    android9 = f'  mResumedActivity: ActivityRecord{{42abc u0 {PACKAGE}/{ACTIVITY} t2}}'

    def test_android9_exact_activity_and_newer_top_resumed_shape(self):
        self.assertTrue(expected_qa_foreground(self.android9))
        self.assertTrue(expected_qa_foreground(self.android9.replace('mResumedActivity:', 'topResumedActivity=')))
        self.assertTrue(expected_qa_foreground(self.android9 + '\n' + self.android9))

    def test_other_empty_malformed_ambiguous_foregrounds_are_rejected(self):
        for state in ['', 'unrelated output', 'mResumedActivity: null',
                      'mResumedActivity: ActivityRecord{broken}',
                      self.android9.replace(PACKAGE, 'com.other.app'),
                      self.android9.replace(ACTIVITY, 'com.example.kazumi.MainActivity'),
                      self.android9 + '\n mResumedActivity: ActivityRecord{4 u0 com.other/.Other t3}']:
            with self.subTest(state=state):
                self.assertFalse(expected_qa_foreground(state))

    def test_only_confirmed_qa_can_receive_input(self):
        for key in ('4', '23'):
            device = Device.__new__(Device)
            device.call = Mock(return_value=self.android9)
            self.assertTrue(device.send_lifecycle_key(key))
            self.assertEqual(device.call.call_args_list, [
                call('shell', 'dumpsys', 'activity', 'activities', timeout=8),
                call('shell', 'input', 'keyevent', key)])

    def test_other_or_unknown_foreground_sends_zero_input_and_never_refocuses(self):
        for state in ['', 'mResumedActivity: null',
                      'mResumedActivity: ActivityRecord{4 u0 com.other/.Other t3}']:
            device = Device.__new__(Device)
            device.call = Mock(return_value=state)
            self.assertFalse(device.send_lifecycle_key('4'))
            device.call.assert_called_once_with('shell', 'dumpsys', 'activity', 'activities', timeout=8)

    def test_failed_foreground_query_also_sends_no_key(self):
        for error in [RuntimeError('unavailable'), subprocess.TimeoutExpired('fake-adb', 8)]:
            device = Device.__new__(Device)
            device.call = Mock(side_effect=error)
            self.assertFalse(device.send_lifecycle_key('23'))
            self.assertEqual(device.call.call_count, 1)


if __name__ == '__main__':
    unittest.main()
