"""Replay the actual Kotlin callback bodies on the JVM; no Android/Gradle/device."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


def callback(source, name):
    start = source.index(f'override fun {name}(')
    opening = source.index('{', start)
    depth = 1
    for index in range(opening + 1, len(source)):
        if source[index] == '{':
            depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError('Unclosed native callback')


class GeckoStopDiagnosticTests(unittest.TestCase):
    def test_actual_callbacks_never_guess_stop_uri_from_requested_or_last_start(self):
        repo = Path(__file__).resolve().parents[3]
        native = repo / 'android/app/src/parserQa/kotlin/com/example/kazumi'
        source = (native / 'ParserQaActivity.kt').read_text(encoding='utf-8')
        methods = callback(source, 'onPageStart') + '\n' + callback(source, 'onPageStop')
        cache = Path(os.environ.get('KAZUMI_QA_MAVEN_CACHE', r'C:\Users\hentai\Documents\Codex\2026-10-02\task\toolchain\gradle-user-home\caches\modules-2\files-2.1'))

        def jar(group, name, version):
            return next((cache / group / name / version).glob(f'*/{name}-{version}.jar'))

        stdlib = jar('org.jetbrains.kotlin', 'kotlin-stdlib', '2.2.21')
        annotations = jar('org.jetbrains', 'annotations', '13.0')
        compiler = [jar('org.jetbrains.kotlin', name, version) for name, version in (
            ('kotlin-compiler-embeddable', '2.2.21'), ('kotlin-script-runtime', '2.2.21'),
            ('kotlin-reflect', '1.6.10'), ('kotlin-daemon-embeddable', '2.2.21'))]
        compiler += [stdlib, annotations, jar('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.0')]
        jdk = Path(os.environ.get('JAVA_HOME', r'C:\Program Files\Java\jdk-21')) / 'bin'
        harness = r'''
package com.example.kazumi
class GeckoSession {
    interface ProgressDelegate {
        fun onPageStart(session: GeckoSession, uri: String) {}
        fun onPageStop(session: GeckoSession, success: Boolean) {}
    }
}
fun main() {
    val emitted = mutableListOf<List<String>>()
    // The real producer closes over the requested URL. A stop callback itself
    // supplies no URI, even if a previous start had a plausible one.
    var url = "https://requested.test/episode/3"
    fun diagnostic(stage: String, uri: String, detail: String) {
        emitted.add(listOf(stage, uri, detail))
    }
    val delegate = object : GeckoSession.ProgressDelegate {
        __ACTUAL_CALLBACKS__
    }
    val session = GeckoSession()
    delegate.onPageStart(session, "about:blank")
    delegate.onPageStop(session, true)
    check(emitted[0] == listOf("load_start", "about:blank", ""))
    check(emitted[1] == listOf("load_stop", "", "success=true uri=unattributed")) {
        "blank stop before target start must not be attributed to requested page"
    }
    for (actualStart in listOf(url, "https://redirect.test/changed", "about:blank")) {
        delegate.onPageStart(session, actualStart)
        for (success in listOf(true, false)) {
            delegate.onPageStop(session, success)
            check(emitted.last() == listOf("load_stop", "", "success=$success uri=unattributed")) {
                "a last start URI is not a URI supplied by this stop callback"
            }
        }
        check(emitted[emitted.size-3] == listOf("load_start", actualStart, ""))
        url = "https://requested.test/replacement"
    }
    check(emitted.count { it[0] == "load_stop" } == 7)
    check(emitted.filter { it[0] == "load_stop" }.all { it[1].isEmpty() })
    println("actual_kotlin_blank_target_redirect_stop_attribution_pass")
}
'''.replace('__ACTUAL_CALLBACKS__', methods)
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            classes = work / 'classes'
            classes.mkdir()
            helper = native / 'QaGeckoPageStop.java'
            if helper.exists():
                compiled = subprocess.run([str(jdk / 'javac.exe'), '-d', str(classes), str(helper)], capture_output=True, timeout=15)
                self.assertEqual(compiled.returncode, 0, compiled.stderr.decode('utf-8', 'replace'))
            fixture = work / 'StopReplay.kt'
            fixture.write_text(harness, encoding='utf-8')
            compiled = subprocess.run([str(jdk / 'java.exe'), '-cp', os.pathsep.join(map(str, compiler)),
                'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect', '-jvm-target', '17',
                '-classpath', os.pathsep.join(map(str, [classes, stdlib, annotations])),
                '-d', str(classes), str(fixture)], capture_output=True, timeout=25)
            self.assertEqual(compiled.returncode, 0, compiled.stderr.decode('utf-8', 'replace'))
            executed = subprocess.run([str(jdk / 'java.exe'), '-cp', os.pathsep.join(map(str, [classes, stdlib])),
                'com.example.kazumi.StopReplayKt'], capture_output=True, timeout=5)
        self.assertEqual(executed.returncode, 0, executed.stderr.decode('utf-8', 'replace'))
        self.assertIn(b'actual_kotlin_blank_target_redirect_stop_attribution_pass', executed.stdout)


if __name__ == '__main__':
    unittest.main()
