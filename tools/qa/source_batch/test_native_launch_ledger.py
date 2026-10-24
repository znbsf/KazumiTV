"""Exercise the actual pure Java ledger on the pinned local JDK; no Android/Gradle launch."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

HARNESS = r'''
package com.example.kazumi;
import java.util.*;
public class LedgerProbeTest {
  static void require(boolean value) { if (!value) throw new AssertionError("ledger_contract"); }
  static void rejects(Runnable action) {
    try { action.run(); throw new AssertionError("expected_rejection"); }
    catch (IllegalArgumentException expected) {}
  }
  public static void main(String[] args) {
    QaLaunchLedger ready = new QaLaunchLedger(); long tick=0;
    ready.record("native_create_enter", tick++, 7, null);
    for (String stage : QaLaunchLedger.DART_ORDER) ready.record(stage, tick++, 7, null);
    require(ready.ready());
    ready.snapshot().get(0).put("stage", "untrusted"); require(ready.ready());
    ready.record("dart_failure", tick++, 7, "StateError"); require(!ready.ready());
    QaLaunchLedger incomplete=new QaLaunchLedger(); incomplete.record("dart_first_frame",0,7,null);
    require(!incomplete.ready());
    QaLaunchLedger bounded=new QaLaunchLedger();
    for (int i=0;i<64;i++) require(bounded.record("native_resume",i,7,null));
    require(!bounded.record("native_resume",64,7,null)); require(bounded.snapshot().size()==64);
    QaLaunchLedger safe=new QaLaunchLedger();
    rejects(()->safe.record("https://invalid.test/PRIVATE_SENTINEL",0,7,null));
    rejects(()->safe.record("dart_failure",0,7,"Error https://invalid.test/PRIVATE_SENTINEL"));
    rejects(()->safe.record("dart_binding",0,7,"StateError"));
    rejects(()->safe.record("native_resume",-1,7,null));
    safe.record("native_resume",5,7,null);
    rejects(()->safe.record("native_resume",4,7,null));
    require(safe.snapshot().size()==1);
    System.out.println("native_ledger_bounds_order_privacy_pass");
  }
}'''

class NativeLaunchLedgerTests(unittest.TestCase):
    def test_actual_native_ledger_bounds_order_privacy_and_snapshot_isolation(self):
        repo=Path(__file__).resolve().parents[3]
        source=repo/'android/app/src/parserQa/kotlin/com/example/kazumi/QaLaunchLedger.java'
        jdk=Path(os.environ.get('JAVA_HOME',r'C:\Program Files\Java\jdk-21'))/'bin'
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); fixture=root/'LedgerProbeTest.java';fixture.write_text(HARNESS,encoding='utf-8')
            build=subprocess.run([str(jdk/'javac.exe'),'-d',str(root),str(source),str(fixture)],capture_output=True,timeout=20)
            self.assertEqual(build.returncode,0,build.stderr.decode('utf-8','replace'))
            run=subprocess.run([str(jdk/'java.exe'),'-cp',str(root),'com.example.kazumi.LedgerProbeTest'],capture_output=True,timeout=5)
            self.assertEqual(run.returncode,0,run.stderr.decode('utf-8','replace'))
            self.assertEqual(run.stdout.strip(),b'native_ledger_bounds_order_privacy_pass')

if __name__=='__main__':unittest.main()
