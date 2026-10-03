"""Verify a freshly built TV APK without installing or publishing it."""
import argparse
import hashlib
import json
import re
import subprocess
import zipfile
from pathlib import Path

def main():
    p = argparse.ArgumentParser()
    p.add_argument('apk', type=Path)
    p.add_argument('--aapt', type=Path, required=True)
    p.add_argument('--apksigner', type=Path, required=True)
    p.add_argument('--application-id', required=True)
    p.add_argument('--abi', choices=['armeabi-v7a', 'arm64-v8a', 'x86_64'], required=True)
    p.add_argument('--build-number', type=int, required=True)
    p.add_argument('--version-name', required=True)
    p.add_argument('--source-sha', required=True)
    p.add_argument('--certificate-sha256')
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    a.apk = a.apk.resolve()
    def run(*argv):
        return subprocess.check_output(argv, text=True, encoding='utf-8', errors='replace')
    assert re.fullmatch(r'[0-9a-f]{40}', a.source_sha), 'Use the exact source commit'
    badging = run(str(a.aapt.resolve()), 'dump', 'badging', str(a.apk))
    manifest = run(str(a.aapt.resolve()), 'dump', 'xmltree', str(a.apk), 'AndroidManifest.xml')
    signature = run(str(a.apksigner.resolve()), 'verify', '--print-certs', str(a.apk))
    package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging)
    assert package and package.group(1) == a.application_id
    expected_code = a.build_number * 10 + {'armeabi-v7a': 1, 'arm64-v8a': 2, 'x86_64': 4}[a.abi]
    assert int(package.group(2)) == expected_code and package.group(3) == a.version_name
    assert "native-code: '" + a.abi + "'" in badging
    assert 'android.intent.category.LEANBACK_LAUNCHER' in manifest
    assert 'android.software.leanback' in manifest
    assert 'android:debuggable' not in manifest or not re.search(r'android:debuggable.*0xffffffff', manifest)
    certs = re.findall(r'certificate SHA-256 digest: ([0-9a-f]+)', signature)
    assert len(certs) == 1
    if a.certificate_sha256:
        assert certs[0] == a.certificate_sha256.lower().replace(':', ''), 'Unexpected signing certificate'
    with zipfile.ZipFile(a.apk) as z:
        app = z.read('lib/' + a.abi + '/libapp.so')
        assert b'KAZUMI_TV_PERF' not in app, 'Diagnostic probe marker present'
        mpv = z.read('lib/' + a.abi + '/libmpv.so')
    receipt = dict(source_sha=a.source_sha, apk=a.apk.name, sha256=hashlib.sha256(a.apk.read_bytes()).hexdigest(),
                   bytes=a.apk.stat().st_size, application_id=a.application_id, version_code=expected_code,
                   version_name=a.version_name, abi=a.abi, certificate_sha256=certs[0],
                   libmpv_sha256=hashlib.sha256(mpv).hexdigest(), probe_marker_absent=True,
                   installed=False, published=False)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt))

if __name__ == '__main__':
    main()
