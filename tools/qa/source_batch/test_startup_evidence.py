import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock
from run import PACKAGE, ACTIVITY
from test_runner_integrity import CaseDevice

class OrdinaryStartupEvidenceTests(unittest.TestCase):
    def test_normal_qa_timeout_preserves_primary_and_only_records_file_metadata(self):
        failure=subprocess.TimeoutExpired('fixed-activity-start',20,
            output=b'Status: timeout\nWaitTime: 20\nhttps://invalid.test/PRIVATE_SENTINEL',stderr=b'PRIVATE_SENTINEL')
        d=CaseDevice(primary=failure)
        d.qa_file=Mock(return_value=({'exists':True,'declared_bytes':31,'read_bytes':31,'type':'json_object'},
            {'untrusted':'PRIVATE_SENTINEL'}))
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaises(subprocess.TimeoutExpired) as caught:
                d.case({'id':'ordinary-discovery','engine':'app','selection_only':True,'selection_tail1':True},Path(t),'key')
            self.assertIs(caught.exception,failure)
            evidence=json.loads((Path(t)/'key.startup-evidence.json').read_text())
            self.assertEqual(evidence['am']['host_wait_seconds'],20)
            self.assertTrue(evidence['am']['timed_out'])
            self.assertEqual(evidence['files']['result.json']['type'],'json_object')
            self.assertNotIn('PRIVATE_SENTINEL',json.dumps(evidence))
            self.assertFalse((Path(t)/'results.jsonl').exists())
            d.qa_file.assert_called_once_with('result.json')

    def test_success_retains_only_allowlisted_start_fields_without_extra_file_reads(self):
        d=CaseDevice();original=d.call
        def call(*args,**kw):
            value=original(*args,**kw)
            if args[0]=='shell' and args[1].startswith('am start'):
                return f'Status: ok\nActivity: {PACKAGE}/{ACTIVITY}\nWaitTime: 3\nPRIVATE_SENTINEL\n'
            return value
        d.call=call;d.qa_file=Mock()
        with tempfile.TemporaryDirectory() as t:
            row=d.case({'id':'ordinary','engine':'app'},Path(t),'key')
            evidence=json.loads((Path(t)/'key.startup-evidence.json').read_text())
            self.assertEqual(row['stage'],'first_frame')
            self.assertTrue(evidence['am']['expected_activity'])
            self.assertFalse(evidence['am']['timed_out'])
            self.assertNotIn('PRIVATE_SENTINEL',json.dumps(evidence));d.qa_file.assert_not_called()

    def test_tail_discovery_refuses_unconfirmed_activity_start(self):
        d=CaseDevice();d.qa_file=Mock(return_value=({'exists':False},None))
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaisesRegex(RuntimeError,'activity start not confirmed'):
                d.case({'id':'discovery','engine':'app','selection_only':True,'selection_tail1':True},Path(t),'key')
            evidence=json.loads((Path(t)/'key.startup-evidence.json').read_text())
            self.assertFalse(evidence['files']['result.json']['exists'])
            self.assertEqual(d.stop_calls,2)

    def test_tail_process_disappearance_stops_before_polling_more_case_data(self):
        d=CaseDevice();original=d.call;polled=[]
        def call(*args,**kw):
            value=original(*args,**kw)
            if args[0]=='exec-out':polled.append(args)
            if args[0]=='shell' and args[1].startswith('am start'):
                d.alive=False
                return f'Status: ok\nActivity: {PACKAGE}/{ACTIVITY}\n'
            return value
        d.call=call;d.qa_file=Mock(return_value=({'exists':False},None))
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaisesRegex(RuntimeError,'process exited before receipt'):
                d.case({'id':'discovery','engine':'app','selection_only':True,'selection_tail1':True},Path(t),'key')
            self.assertFalse(polled)
            evidence=json.loads((Path(t)/'key.startup-evidence.json').read_text())
            self.assertTrue(evidence['process_exit_observed'])

if __name__=='__main__':unittest.main()
