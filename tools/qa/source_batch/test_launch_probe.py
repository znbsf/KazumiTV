import json
import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
from run import (Device, LAUNCH_ID, PACKAGE, launch_only_spec, launch_am_fields,
    launch_file_decode, validate_launch_journal, validate_launch_result, summarize,
    launch_ready_observed, LAUNCH_DART_ORDER, run_batch)

def config():
    return dict(id=LAUNCH_ID,group='offline-launch',engine='app',launch_only=True,repeat=0,user_agent='QA')

def journal():
    return dict(schema=1,id=LAUNCH_ID,attempt_key='a'*20,network_permission_denied=True,
        package_info_registered=True,events=[dict(seq=0,stage='native_create_enter',elapsed_ms=0,pid=7)])

class LaunchProbeTests(unittest.TestCase):
    def test_input_is_fixed_and_never_source_capable(self):
        self.assertTrue(launch_only_spec(config()))
        self.assertFalse(launch_only_spec({'id':'ordinary'}))
        for change in [{'rule':{}},{'keyword':'secret'},{'url':'secret'},{'fallback':True},{'observer':True},
                {'engine':'gecko'},{'repeat':1},{'repeat':False},{'launch_only':False},{'user_agent':None}]:
            with self.subTest(change=change),self.assertRaises(ValueError): launch_only_spec({**config(),**change})

    def test_am_output_only_retains_fixed_fields(self):
        output=launch_am_fields(b'Status: ok\nThisTime: 47\nWaitTime: 80\nComplete\nhttps://secret.invalid/PRIVATE_SENTINEL\nError: PRIVATE_SENTINEL\n')
        self.assertEqual(output,{'Status':'ok','ThisTime':47,'WaitTime':80,'Complete':True})
        self.assertNotIn('PRIVATE_SENTINEL',json.dumps(output))

    def test_empty_invalid_utf8_invalid_json_are_distinct_without_saving_text(self):
        for raw,kind in [(b'','empty'),(b'\xff','invalid_utf8'),(b'{"incomplete":','invalid_json'),(b'cat: PRIVATE_SENTINEL','invalid_json')]:
            meta,value=launch_file_decode(raw,len(raw)); self.assertEqual(meta['type'],kind)
            self.assertIsNone(value); self.assertNotIn('PRIVATE_SENTINEL',json.dumps(meta))
        self.assertEqual(launch_file_decode(b'{}',1)[0]['type'],'size_mismatch_or_limit')

    def test_transport_success_does_not_imply_file_exists_or_schema_valid(self):
        d=object.__new__(Device);d.adb='never';d.serial='emulator-5582';d.call=Mock(return_value='run-as failure')
        with patch('run.subprocess.run') as raw:
            meta,value=d.launch_file('qa-launch-probe.json','a'*20)
            self.assertIsNone(meta['exists']);raw.assert_not_called()
        d.call.return_value='MISSING'
        self.assertEqual(d.launch_file('qa-launch-probe.json','a'*20),({'exists':False},None))
        d.call.return_value='FILE:20'
        with patch('run.subprocess.run',return_value=subprocess.CompletedProcess([],0,b'cat: PRIVATE_SENTINEL',b'')):
            meta,value=d.launch_file('qa-launch-probe.json','a'*20)
        self.assertIsNone(value);self.assertFalse(meta['schema_valid']);self.assertNotIn('PRIVATE_SENTINEL',json.dumps(meta))

    def test_journal_schema_rejects_extra_fields_sensitive_errors_and_other_attempts(self):
        self.assertTrue(validate_launch_journal(journal(),'a'*20))
        for delta in [{'raw':'secret'},{'attempt_key':'b'*20},{'schema':True},{'package_info_registered':0}]:
            self.assertFalse(validate_launch_journal({**journal(),**delta},'a'*20))
        for delta in [{'error_type':'https://secret.invalid'},{'stage':'secret'},{'seq':False},{'elapsed_ms':-1}]:
            value=journal();value['events'][0].update(delta)
            self.assertFalse(validate_launch_journal(value,'a'*20))

    def test_launch_results_are_excluded_from_product_playback_denominators(self):
        row=dict(id=LAUNCH_ID,group='offline-launch',engine='app',stage='launch_ready',launch_only=True)
        result=summarize([row])[0]
        self.assertEqual((result['launch_only_results'],result['launch_ready'],result['eligible_results'],result['first_frame']),(1,1,0,0))

    def test_batch_preserves_launch_intent_and_does_not_claim_playback_coverage(self):
        d=Mock();d.case.return_value={'id':LAUNCH_ID,'engine':'app','stage':'launch_ready','cleanup':'confirmed','host_cleanup':{'status':'confirmed'}}
        d.stop_and_verify.return_value={'status':'confirmed'}
        plan=[dict(key='a'*20,id=LAUNCH_ID,group='offline-launch',engine='app',repeat=0,config=config(),expected_environment={'sdk':28,'provider':'provider/66'})]
        with tempfile.TemporaryDirectory() as t,contextlib.redirect_stdout(io.StringIO()):
            report=run_batch(d,plan,Path(t),[])
            saved=json.loads((Path(t)/'results.jsonl').read_text())
            self.assertTrue(saved['launch_only']);self.assertNotIn('headers/player controller',saved['compatibility'])
            self.assertEqual(report['summary'][0]['eligible_results'],0)

    def test_success_requires_same_attempt_full_order_and_native_checkpoints(self):
        value=journal();stages=['native_create_enter','native_engine_enter','native_super_engine_exit','native_channel_ready']+LAUNCH_DART_ORDER+['native_first_frame','probe_result']
        value['events']=[dict(seq=i,stage=s,elapsed_ms=i,pid=7) for i,s in enumerate(stages)]
        self.assertTrue(launch_ready_observed(value,'a'*20))
        value['events'][6]['stage']='dart_failure'
        self.assertFalse(launch_ready_observed(value,'a'*20))
        self.assertFalse(launch_ready_observed(None,'a'*20))

    def test_timeout_keeps_primary_failure_and_collects_only_safe_offline_evidence(self):
        d=object.__new__(Device);d.launch_allowed=True;d.physical=False
        d.stop_and_verify=Mock(return_value={'status':'confirmed','errors':[]})
        d.processes=Mock(return_value={1:'init'});d.memory=Mock(return_value={'processes':[],'sum_pss_kib':0})
        d.launch_file=Mock(side_effect=lambda n,k: ({'exists':False},None))
        def call(*args,**kwargs):
            if args[0]=='shell' and args[1].startswith('am start'):
                raise subprocess.TimeoutExpired('fixed-launch',20,output=b'WaitTime: 20\nPRIVATE_SENTINEL')
            return ''
        d.call=call
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaises(subprocess.TimeoutExpired):d.case(config(),Path(t),'a'*20)
            saved=json.loads((Path(t)/('a'*20+'.launch-evidence.json')).read_text())
            self.assertTrue(saved['am']['timed_out']);self.assertEqual(saved['am']['host_wait_seconds'],20)
            self.assertNotIn('PRIVATE_SENTINEL',json.dumps(saved));self.assertEqual(d.stop_and_verify.call_count,2)

if __name__=='__main__':unittest.main()
