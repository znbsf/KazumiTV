"""Offline single-ABI QA artifact gate; no build, transport or device access."""
import argparse
import json
from pathlib import Path
import re
import zipfile

PACKAGE = 'com.znbsf.kazumi.fluttertv.parserqa'
ELF = {'armeabi-v7a': (1, 40), 'arm64-v8a': (2, 183), 'x86_64': (2, 62)}
REQUIRED = ('libflutter.so', 'libmpv.so', 'libxul.so')


def verify_artifact(apk, badging, permissions, *, abi, build_number, build_name, offline):
    if abi not in ELF or type(build_number) is not int or not 1 <= build_number <= 2100000000:
        raise ValueError('Invalid QA artifact expectation')
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'", badging, re.M)
    sdk = re.search(r"^sdkVersion:'(\d+)'", badging, re.M)
    if (not package or package.group(1) != PACKAGE or int(package.group(2)) != build_number or
            package.group(3) != build_name or not sdk or int(sdk.group(1)) != 26 or
            'application-debuggable' not in badging or ' split=' in badging):
        raise ValueError('QA package, actual version, minSDK or debug identity differs')
    internet = "uses-permission: name='android.permission.INTERNET'" in permissions
    if internet == offline:
        raise ValueError('QA APK INTERNET does not match selected mode')
    declared = re.search(r'^native-code: (.+)$', badging, re.M)
    if not declared or re.findall(r"'([^']+)'", declared.group(1)) != [abi]:
        raise ValueError('AAPT native ABI declaration differs from single QA target')
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate QA APK ZIP entry')
        native = [p for p in names if p.startswith('lib/') and not p.endswith('/')]
        if not native or any(len(p.split('/')) < 3 or p.split('/')[1] != abi for p in native):
            raise ValueError('QA APK contains a non-target native ABI')
        for library in REQUIRED:
            path = f'lib/{abi}/{library}'
            if path not in names:
                raise ValueError('QA target native runtime is incomplete')
            with archive.open(path) as stream:
                header = stream.read(20)
            klass, machine = ELF[abi]
            if (len(header) != 20 or header[:4] != b'\x7fELF' or header[4] != klass or
                    header[5] != 1 or int.from_bytes(header[18:20], 'little') != machine):
                raise ValueError('QA native ELF architecture differs from target')
    return {'package': PACKAGE, 'actual_version_code': int(package.group(2)),
            'actual_version_name': package.group(3), 'min_sdk': int(sdk.group(1)),
            'native_abi': abi, 'native_entries': len(native), 'internet_permission': internet,
            'launch_only_build': offline, 'abi_packaging': 'qa-single-abi-no-splits',
            'required_native_elf_verified': list(REQUIRED)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('apk', 'badging', 'permissions', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--abi', choices=ELF, required=True)
    parser.add_argument('--build-number', type=int, required=True)
    parser.add_argument('--build-name', required=True)
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    result = verify_artifact(args.apk, args.badging.read_text(encoding='utf-8-sig'),
        args.permissions.read_text(encoding='utf-8-sig'), abi=args.abi,
        build_number=args.build_number, build_name=args.build_name, offline=args.offline)
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
