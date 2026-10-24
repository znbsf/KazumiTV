"""Real runner/transport paths with fake time; no ADB or source requests."""
import contextlib
import inspect
import io
import json
from pathlib import Path
import subprocess
import shutil
import shlex
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

import run as r


class Clock:
    now = 0.0
    def monotonic(self): return self.now
    def epoch(self): return 1800000000+self.now
    def advance(self, seconds): self.now += seconds


class Sampler:
    def __init__(self, clock, target, cost=0):
        self.clock, self.target, self.cost = clock, target, cost
        self.ident, self.alive, self.join_timeout = None, False, None
    def start(self): self.ident, self.alive = 1, True
    def join(self, timeout):
        self.join_timeout = timeout
        self.clock.advance(min(timeout,self.cost))
        self.alive = self.cost > timeout
    def is_alive(self): return self.alive


def frame(raw):
    return b'QA_FILE:'+str(len(raw)).encode()+b'\n'+raw


class Transport:
    def __init__(self, clock, *, ready=0, read_cost=0, am_cost=0, stops=(0,0),
                 config_cost=0, process_cost=0, value=None):
        self.clock, self.ready, self.read_cost, self.am_cost = clock, ready, read_cost, am_cost
        self.config_cost, self.process_cost = config_cost, process_cost
        self.stops, self.calls, self.value = list(stops), [], value
        self.primary = None
        self.qemu_cost = 0
        self.qemu = b'1'
        self.apk_sha = ''
    def spend(self, cost, timeout):
        self.clock.advance(min(cost,timeout))
        if cost > timeout: raise subprocess.TimeoutExpired('fixed fake transport',timeout)
    def __call__(self, argv, **kw):
        args, timeout = argv[3:], kw['timeout']
        self.calls.append((args,timeout,self.clock.now))
        data = b''
        if args[0]=='shell':
            command=args[1]
            if command.startswith('getprop ro.kernel.qemu'):
                self.spend(self.qemu_cost,timeout);data=self.qemu
            elif command=='getprop ro.build.fingerprint':data=b'fixture/fingerprint'
            elif command=='getprop ro.build.version.sdk':data=b'28'
            elif command=='dumpsys webviewupdate':data=b'Current WebView package (name, version): (provider, 66)'
            elif command.startswith('pm path '):data=b'package:/data/app/qa/base.apk'
            elif command.startswith('sha256sum '):data=(self.apk_sha+'  /data/app/qa/base.apk').encode()
            elif command=='pm list packages kazumi':data=('package:'+r.PACKAGE).encode()
            elif command.startswith('am force-stop'):
                self.spend(self.stops.pop(0) if self.stops else 0,timeout)
            elif command.startswith('ps -A'):
                self.spend(self.process_cost,timeout);data=b'PID NAME\n1 init\n'
            elif command.startswith('am start'):
                self.spend(self.am_cost,timeout)
                if self.primary: raise self.primary
                data=b'Status: ok\n'
            elif command.startswith('run-as'):
                if kw.get('input') is not None:
                    self.spend(self.config_cost,timeout)
                else: data=b'MISSING'
        elif args[0]=='exec-out':
            if self.clock.now >= self.ready:
                self.spend(self.read_cost,timeout)
                value=self.value or {'id':'synthetic','engine':'app','stage':'first_frame',
                    'cleanup':'confirmed','timings_ms':{'resolve':1,'first_frame':2}}
                data=frame(json.dumps(value).encode())
            else: data=b'QA_MISSING'
        return subprocess.CompletedProcess(argv,0,data,b'')


def plan(count):
    return [{'key':f'{i:020x}','id':'synthetic','engine':'app','group':'fake','repeat':0,
        'config':{'id':'synthetic','engine':'app'},'expected_environment':{}} for i in range(count)]


class DeadlineTests(unittest.TestCase):
    def receipt_fixture(self, folder, *, legacy=False):
        item=plan(1)[0]
        row={'key':item['key'],'id':item['id'],'engine':'app','group':'fake','repeat':0,
             'stage':'first_frame','cleanup':'confirmed','host_cleanup':{'status':'confirmed'},
             'timings_ms':{'resolve':1,'first_frame':2}}
        if not legacy:row['host_budget']={'within_deadline':True}
        (folder/'plan.json').write_text(json.dumps([{k:item[k] for k in ('key','id','engine','group','repeat')}]))
        (folder/'attempts.jsonl').write_text(json.dumps({'key':item['key']})+'\n')
        (folder/'results.jsonl').write_text(json.dumps(row)+'\n')
        receipt={'final_host_cleanup':{'status':'confirmed'},'cleanup_errors':[],
                 'budget_unknown_keys':[],'unconfirmed_terminal_keys':[],
                 'terminal_records':{row['key']:r.digest(json.dumps(row,sort_keys=True,ensure_ascii=False).encode())}}
        return row,receipt

    def test_new_row_requires_final_matching_receipt_and_keeps_raw(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);_,receipt=self.receipt_fixture(folder)
            raw=(folder/'results.jsonl').read_bytes()
            for checkpoint in (False,True):
                if checkpoint:(folder/'run-status.json').write_text(json.dumps(receipt))
                report=r.build_report(folder)
                self.assertEqual((report['raw_result_records'],report['completed'],report['unknown']),(1,0,1))
                self.assertFalse(report['summary'])
            # A completed case and a parent package protocol failure are distinct.
            receipt['host_budget']={'within_deadline':False};receipt['stop_reason']='budget'
            (folder/'cleanup.json').write_text(json.dumps(receipt))
            report=r.build_report(folder)
            self.assertEqual((report['completed'],report['unknown']),(1,0))
            self.assertFalse(report['run_status']['host_budget']['within_deadline'])
            self.assertEqual((folder/'results.jsonl').read_bytes(),raw)

    def test_bad_final_receipts_never_restore_new_row_completion(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);row,receipt=self.receipt_fixture(folder)
            (folder/'run-status.json').write_text(json.dumps(receipt))
            variants=[b'{PRIVATE_SENTINEL',b'\xff',b'[]',json.dumps({**receipt,'terminal_records':{'other':receipt['terminal_records'][row['key']]}}).encode(),
                json.dumps({**receipt,'terminal_records':{row['key']:'0'*64}}).encode(),
                json.dumps({**receipt,'terminal_records':[]}).encode(),
                json.dumps({**receipt,'cleanup_errors':None}).encode(),
                json.dumps({**receipt,'final_host_cleanup':{'status':'unconfirmed'}}).encode()]
            for data in variants:
                with self.subTest(receipt_bytes=len(data)):
                    (folder/'cleanup.json').write_bytes(data)
                    report=r.build_report(folder)
                    self.assertEqual((report['completed'],report['unknown']),(0,1))
                    self.assertNotIn('PRIVATE_SENTINEL',json.dumps(report))

    def test_legacy_row_stays_compatible_with_missing_or_invalid_final(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);self.receipt_fixture(folder,legacy=True)
            self.assertEqual(r.build_report(folder)['completed'],1)
            (folder/'cleanup.json').write_bytes(b'{bad')
            self.assertEqual(r.build_report(folder)['completed'],1)

    def test_final_receipt_preserves_prior_certified_keys_on_resume(self):
        clock=Clock()
        with self.setup_device(clock,Transport(clock)) as (d,_), tempfile.TemporaryDirectory() as tmp,contextlib.redirect_stdout(io.StringIO()):
            folder=Path(tmp);rows=[]
            r.run_batch(d,plan(1),folder,rows)
            prefix=(folder/'results.jsonl').read_bytes()
            r.run_batch(d,plan(2),folder,rows)
            report=r.build_report(folder)
            self.assertEqual((report['completed'],report['unknown']),(2,0))
            self.assertTrue((folder/'results.jsonl').read_bytes().startswith(prefix))

    @contextlib.contextmanager
    def setup_device(self, clock, transport, *, budget=None, sampler_cost=0):
        d=object.__new__(r.Device)
        d.adb, d.serial, d.physical, d.launch_allowed='never','emulator-5582',False,False
        d._parent_budget=budget
        d._budget_local=threading.local()
        samplers=[]
        def thread_factory(target, **_):
            sampler=Sampler(clock,target,sampler_cost);samplers.append(sampler);return sampler
        with patch.object(r.time,'monotonic',clock.monotonic), \
                patch.object(r.time,'time',clock.epoch), \
                patch.object(r.time,'sleep',clock.advance), \
                patch.object(r.subprocess,'run',side_effect=transport), \
                patch.object(r.threading,'Thread',side_effect=thread_factory):
            yield d,samplers

    def test_preflight_and_case_share_origin_without_new_70(self):
        clock=Clock();clock.advance(20)
        budget=r.HostDeadline(started=0,end=70)
        with self.setup_device(clock,Transport(clock,ready=80),budget=budget) as (d,_), tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(r.HostBudgetExpired):
                r.run_batch(d,plan(1),Path(tmp),[],budget=budget)
            self.assertLessEqual(clock.now,70)
            self.assertFalse((Path(tmp)/'results.jsonl').exists())
            self.assertEqual(r.build_report(Path(tmp))['unknown'],1)

    def test_read_entering_at_work_cutoff_cannot_accept_late_reply(self):
        clock=Clock();clock.advance(53)
        budget=r.HostDeadline(started=0,end=70)
        transport=Transport(clock,read_cost=3)
        with self.setup_device(clock,transport,budget=budget) as (d,_), tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(subprocess.TimeoutExpired):
                r.run_batch(d,plan(1),Path(tmp),[],budget=budget)
            reads=[c for c in transport.calls if c[0][0]=='exec-out']
            self.assertEqual(reads[0][1],2)
            self.assertFalse((Path(tmp)/('0'*20+'.provisional.json')).exists())
            self.assertEqual(r.build_report(Path(tmp))['unknown'],1)

    def test_am_initialization_timeout_is_remaining_not_new_20(self):
        clock=Clock();budget=r.HostDeadline(started=0,end=70)
        transport=Transport(clock,am_cost=20,stops=(8,0),config_cost=15,process_cost=15)
        with self.setup_device(clock,transport,budget=budget) as (d,_), tempfile.TemporaryDirectory() as tmp:
            d._next_case_budget=budget
            with self.assertRaises(subprocess.TimeoutExpired) as caught:
                d.case({'id':'synthetic','engine':'app'},Path(tmp),'k')
            am=next(c for c in transport.calls if c[0][0]=='shell' and c[0][1].startswith('am start'))
            self.assertEqual(am[1],2)  # 55 work cutoff - 53 spent in preparation.
            evidence=json.loads((Path(tmp)/'k.startup-evidence.json').read_text())
            self.assertEqual(evidence['am']['host_wait_seconds'],2)
            self.assertEqual(caught.exception.timeout,2)
            self.assertLessEqual(clock.now,70)

    def test_near_cutoff_success_is_atomic_and_cleanup_is_in_budget(self):
        clock=Clock();clock.advance(54.9);budget=r.HostDeadline(started=0,end=70)
        with self.setup_device(clock,Transport(clock,read_cost=.05),budget=budget) as (d,_), tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            report=r.run_batch(d,plan(1),Path(tmp),[],budget=budget)
            provisional=json.loads((Path(tmp)/('0'*20+'.provisional.json')).read_text())
            terminal=json.loads((Path(tmp)/('0'*20+'.terminal.json')).read_text())
            self.assertFalse(provisional['terminal'])
            self.assertEqual(terminal['stage'],'first_frame')
            self.assertEqual(report['completed'],1)
            self.assertFalse(list(Path(tmp).glob('*.tmp')))

    def test_slow_cleanup_keeps_provisional_but_never_terminal_pass(self):
        clock=Clock();clock.advance(54);budget=r.HostDeadline(started=0,end=70)
        with self.setup_device(clock,Transport(clock,stops=(0,3)),budget=budget,sampler_cost=30) as (d,samplers), tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(r.HostBudgetExpired):
                r.run_batch(d,plan(1),Path(tmp),[],budget=budget)
            self.assertEqual(samplers[0].join_timeout,13)
            self.assertTrue((Path(tmp)/('0'*20+'.provisional.json')).exists())
            self.assertFalse((Path(tmp)/('0'*20+'.terminal.json')).exists())
            self.assertEqual(r.build_report(Path(tmp))['unknown'],1)
            self.assertLessEqual(clock.now,70)

    def test_atomic_provisional_write_that_finishes_late_is_not_pass(self):
        clock=Clock();clock.advance(54.9);budget=r.HostDeadline(started=0,end=70)
        replace=r.os.replace
        def delayed_replace(source,target):
            replace(source,target)
            if str(target).endswith('.provisional.json'): clock.advance(.2)
        with self.setup_device(clock,Transport(clock),budget=budget) as (d,_), tempfile.TemporaryDirectory() as tmp, patch.object(r.os,'replace',side_effect=delayed_replace):
            with self.assertRaises(r.HostBudgetExpired):
                r.run_batch(d,plan(1),Path(tmp),[],budget=budget)
            self.assertTrue((Path(tmp)/('0'*20+'.provisional.json')).exists())
            self.assertFalse((Path(tmp)/'results.jsonl').exists())
            self.assertEqual(r.build_report(Path(tmp))['unknown'],1)

    def test_cancel_primary_error_survives_cleanup_timeout(self):
        clock=Clock();primary=KeyboardInterrupt()
        transport=Transport(clock,stops=(0,20));transport.primary=primary
        with self.setup_device(clock,transport) as (d,_), tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(KeyboardInterrupt) as caught:
                d.case({'id':'synthetic','engine':'app'},Path(tmp),'k')
            self.assertIs(caught.exception,primary)
            self.assertEqual(primary.qa_cleanup['status'],'unconfirmed')

    def test_sampler_cannot_borrow_the_next_generation_deadline(self):
        clock=Clock();budget=r.HostDeadline(started=0,end=70)
        with self.setup_device(clock,Transport(clock),budget=budget) as (d,samplers), tempfile.TemporaryDirectory() as tmp:
            d._next_case_budget=budget
            d.case({'id':'synthetic','engine':'app'},Path(tmp),'k')
            stop=inspect.getclosurevars(samplers[0].target).nonlocals['stop'];stop.clear()
            clock.advance(80);d._parent_budget=r.HostDeadline(started=80,end=300)
            d.memory=Mock(side_effect=lambda *_:stop.set())
            samplers[0].target()
            d.memory.assert_not_called()

    def test_parent_200_300_reserves_final_window_without_clock_reset(self):
        for limit in (200,300):
            clock=Clock()
            class BatchDevice:
                def case(self,config,output,key):
                    clock.advance(60)
                    return {'id':'synthetic','engine':'app','stage':'first_frame',
                        'timings_ms':{'resolve':1,'first_frame':2},'cleanup':'confirmed',
                        'host_cleanup':{'status':'confirmed'}}
                def stop_and_verify(self):
                    clock.advance(23);return {'status':'confirmed'}
            with patch.object(r.time,'monotonic',clock.monotonic),patch.object(r.time,'time',clock.epoch),tempfile.TemporaryDirectory() as tmp,contextlib.redirect_stdout(io.StringIO()):
                report=r.run_batch(BatchDevice(),plan(5),Path(tmp),[],budget_seconds=limit)
                self.assertEqual(report['completed'],2 if limit==200 else 3)
                self.assertLess(clock.now,limit)
                self.assertGreater(report['unattempted'],0)

    def test_single_120_does_not_require_130_seconds_to_admit(self):
        clock=Clock()
        with self.setup_device(clock,Transport(clock)) as (d,_), tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            report=r.run_batch(d,plan(1),Path(tmp),[],budget_seconds=120)
            self.assertEqual(report['completed'],1)

    def test_second_actual_case_has_its_own_70s_receipt_origin(self):
        clock=Clock()
        with self.setup_device(clock,Transport(clock,am_cost=10)) as (d,_), tempfile.TemporaryDirectory() as tmp,contextlib.redirect_stdout(io.StringIO()):
            rows=[];r.run_batch(d,plan(2),Path(tmp),rows,budget_seconds=200)
            self.assertEqual([row['host_elapsed_ms'] for row in rows],[10000,10000])
            self.assertEqual([row['host_budget']['limit_ms'] for row in rows],[70000,70000])
            self.assertEqual([row['host_budget']['elapsed_ms'] for row in rows],[10000,10000])

    def test_late_ledger_fsync_keeps_raw_row_but_coverage_unknown(self):
        clock=Clock();calls=0
        def delayed_fsync(_):
            nonlocal calls
            calls+=1
            if calls==3:clock.advance(71)
        with self.setup_device(clock,Transport(clock)) as (d,_),tempfile.TemporaryDirectory() as tmp,patch.object(r.os,'fsync',side_effect=delayed_fsync):
            with self.assertRaises(r.HostBudgetExpired):
                r.run_batch(d,plan(1),Path(tmp),[])
            raw=json.loads((Path(tmp)/'results.jsonl').read_text())
            self.assertEqual(raw['stage'],'first_frame')
            report=r.build_report(Path(tmp))
            self.assertEqual((report['raw_result_records'],report['completed'],report['unknown']),(1,0,1))

    def test_protection_readback_is_required_and_late_check_is_not_pass(self):
        clock=Clock();clock.advance(54);budget=r.HostDeadline(started=0,end=70)
        with self.setup_device(clock,Transport(clock),budget=budget) as (d,_),tempfile.TemporaryDirectory() as tmp:
            d._protected_baseline={'formal':{'sha256':'a'*64}}
            def delayed_protection():
                clock.advance(20)
                return d._protected_baseline
            d.protected_packages=Mock(side_effect=delayed_protection)
            with self.assertRaises(r.HostBudgetExpired):r.run_batch(d,plan(1),Path(tmp),[],budget=budget)
            d.protected_packages.assert_called_once()
            self.assertEqual(r.build_report(Path(tmp))['unknown'],1)

    def test_exhausted_work_before_case_is_unattempted_not_unknown(self):
        clock=Clock();clock.advance(60);budget=r.HostDeadline(started=0,end=70)
        with self.setup_device(clock,Transport(clock),budget=budget) as (d,_), tempfile.TemporaryDirectory() as tmp:
            report=r.run_batch(d,plan(1),Path(tmp),[],budget=budget)
            self.assertEqual((report['started'],report['unknown'],report['unattempted']),(0,0,1))

    def test_main_initialization_timeout_records_no_launch_and_unattempted(self):
        clock=Clock();transport=Transport(clock);transport.qemu_cost=100
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);apk=folder/'fake.apk';apk.write_bytes(b'not installed')
            (folder/'artifact.json').write_text(json.dumps({'apk_sha256':r.digest(apk.read_bytes())}))
            manifest=folder/'input.json';manifest.write_text(json.dumps({'cases':[{'id':'synthetic','group':'fake','url':'https://example.invalid'}]}))
            output=folder/'out';args=['run.py','--adb','never','--serial','emulator-5582','--apk',str(apk),'--manifest',str(manifest),'--output',str(output),'--budget-seconds','120']
            with self.setup_device(clock,transport),patch.object(r.sys,'argv',args):
                with self.assertRaises(subprocess.TimeoutExpired):r.main()
            receipt=json.loads((output/'preflight-budget.json').read_text())
            self.assertEqual((receipt['started'],receipt['unknown'],receipt['unattempted']),(0,0,1))
            self.assertFalse(any(c[0][0]=='shell' and c[0][1].startswith('am start') for c in transport.calls))

    def test_physical_main_final_receipt_cannot_erase_late_ledger_unknown(self):
        clock=Clock();transport=Transport(clock);transport.qemu=b'0';calls=0
        def delayed_fsync(_):
            nonlocal calls
            calls+=1
            if calls==4:clock.advance(71)  # provisional/protection/terminal/ledger
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);apk=folder/'fake.apk';apk.write_bytes(b'not installed')
            transport.apk_sha=r.digest(apk.read_bytes())
            (folder/'artifact.json').write_text(json.dumps({'apk_sha256':transport.apk_sha}))
            manifest=folder/'input.json';manifest.write_text(json.dumps({'cases':[{'id':'synthetic','group':'fake','url':'https://example.invalid'}]}))
            output=folder/'out';args=['run.py','--adb','never','--serial','192.0.2.1:5555',
                '--allow-physical-qa','--expect-serial','192.0.2.1:5555',
                '--expect-fingerprint','fixture/fingerprint','--apk',str(apk),
                '--manifest',str(manifest),'--output',str(output),'--budget-seconds','120']
            with self.setup_device(clock,transport),patch.object(r.sys,'argv',args),patch.object(r.os,'fsync',side_effect=delayed_fsync):
                with self.assertRaises(r.HostBudgetExpired):r.main()
            report=r.build_report(output)
            self.assertEqual((report['raw_result_records'],report['completed'],report['unknown']),(1,0,1))
            receipt=json.loads((output/'protected-packages-after.json').read_text())
            self.assertTrue(receipt['reused_same_CLI_last_case_measurement'])

    def test_real_call_checks_both_sides_even_if_OS_returns_after_timeout(self):
        clock=Clock();budget=r.HostDeadline(started=0,end=2)
        def stalled_OS(argv,**kw):
            self.assertEqual(kw['timeout'],2)
            clock.advance(3)
            return subprocess.CompletedProcess(argv,0,b'PRIVATE_SENTINEL',b'')
        with self.setup_device(clock,Transport(clock),budget=budget) as (d,_),patch.object(r.subprocess,'run',side_effect=stalled_OS):
            with self.assertRaises(r.HostBudgetExpired):d.call('shell','fixed')
            self.assertEqual(budget.receipt()['overrun_ms'],1000)
            with self.assertRaises(r.HostBudgetExpired):d.call('shell','fixed')

    def test_fixed_file_metadata_not_exit0_controls_existence_and_type(self):
        cases=[(b'', 'invalid_file_marker'),(b'QA_MISSING',None),
            (b'QA_FILE:0\n','empty'),(b'QA_FILE:3\n{}','size_mismatch'),
            (b'QA_FILE:1\n\xff','invalid_utf8'),(b'QA_FILE:1\nx','invalid_json'),
            (b'QA_FILE:2\n[]','json_other'),
            (f'QA_FILE:{r.RESULT_BYTE_LIMIT+1}\n'.encode()+b'x','size_limit')]
        d=object.__new__(r.Device)
        for raw,kind in cases:
            with self.subTest(kind=kind):
                d.call=Mock(return_value=subprocess.CompletedProcess([],0,raw,b''))
                meta,value=d.result_file()
                self.assertEqual(meta.get('type'),kind)
                if raw==b'QA_MISSING':self.assertFalse(meta['exists'])
                elif kind!='json_other':self.assertIsNone(value)
        raw=b'x'*r.RESULT_BYTE_LIMIT
        d.call=Mock(return_value=subprocess.CompletedProcess([],0,frame(raw),b''))
        self.assertEqual(d.result_file()[0]['type'],'invalid_json')
        d.call=Mock(return_value=subprocess.CompletedProcess([],1,frame(b'{}'),b''))
        self.assertEqual(d.result_file()[0]['type'],'transport_error')

    def test_valid_json_at_exact_byte_cap_is_not_truncated(self):
        value={'id':'synthetic','engine':'app','pad':''}
        length=len(json.dumps(value).encode());value['pad']='x'*(r.RESULT_BYTE_LIMIT-length)
        raw=json.dumps(value).encode();self.assertEqual(len(raw),r.RESULT_BYTE_LIMIT)
        d=object.__new__(r.Device);d.call=Mock(return_value=subprocess.CompletedProcess([],0,frame(raw),b''))
        meta,parsed=d.result_file()
        self.assertEqual(meta['read_bytes'],r.RESULT_BYTE_LIMIT)
        self.assertEqual(parsed,value)

    def test_exec_out_client_escape_model_with_real_local_shell(self):
        shell=Path(r'C:\Program Files\Git\bin\bash.exe')
        if not shell.exists():
            found=shutil.which('bash')
            if not found:self.skipTest('Local POSIX shell unavailable')
            shell=Path(found)
        d=object.__new__(r.Device);d.call=Mock(return_value=subprocess.CompletedProcess([],0,b'QA_MISSING',b''));d.result_file()
        args=d.call.call_args.args
        self.assertEqual(args[:5],('exec-out','run-as',r.PACKAGE,'sh','-c'))
        # Official exec-out client: argv[1] is the command, every later arg
        # passes escape_arg. The old bare-join model was wrong.
        def escape_arg(value):
            return "'"+value.replace("'", "'\\''")+"'"
        def wire(argv):
            return argv[1]+''.join(' '+escape_arg(arg) for arg in argv[2:])
        remote=wire(args)
        # Reproduce the pre-fix manual quote in memory, then the client's
        # second escaping layer. Never infer the real TV's156 error bytes.
        raw_script=shlex.split(args[-1])[0] if args[-1].startswith("'") else args[-1]
        manual_quote=wire((*args[:-1],shlex.quote(raw_script)))
        prefix='run-as() { shift; "$@"; }\n'
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp);(directory/'files').mkdir()
            raw=json.dumps({'id':'synthetic','title':'合成'},ensure_ascii=False).encode()
            (directory/'files/result.json').write_bytes(raw)
            def execute(command):
                return subprocess.run([str(shell),'--noprofile','--norc','-c',prefix+command],
                    cwd=directory,capture_output=True,timeout=5)
            valid=execute(remote)
            self.assertEqual(valid.returncode,0,valid.stderr)
            self.assertEqual(valid.stdout,frame(raw))
            invalid=execute(manual_quote)
            self.assertFalse(invalid.returncode==0 and invalid.stdout==frame(raw))
            # exec-out's locally successful transport is not a file marker.
            # Only simulated error bytes enter this decoder, never TV raw data.
            d.call=Mock(return_value=subprocess.CompletedProcess([],0,invalid.stdout+invalid.stderr,b''))
            self.assertEqual(d.result_file()[0]['type'],'invalid_file_marker')
            (directory/'files/result.json').unlink()
            self.assertEqual(execute(remote).stdout,b'QA_MISSING')

    def test_valid_but_stale_case_or_engine_is_not_provisional(self):
        for value in [{'id':'other','engine':'app'},{'id':'synthetic','engine':'gecko'}]:
            clock=Clock()
            with self.setup_device(clock,Transport(clock,value=value)) as (d,_),tempfile.TemporaryDirectory() as tmp:
                with self.assertRaisesRegex(RuntimeError,'case identity'):
                    d.case({'id':'synthetic','engine':'app'},Path(tmp),'k')
                self.assertFalse((Path(tmp)/'k.provisional.json').exists())


if __name__=='__main__':unittest.main()
