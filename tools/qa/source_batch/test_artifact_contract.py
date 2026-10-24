import tempfile
import unittest
import warnings
from pathlib import Path
import zipfile

from artifact_contract import ELF, PACKAGE, REQUIRED, verify_artifact


def header(abi):
    klass, machine = ELF[abi]
    data = bytearray(20)
    data[:4] = b'\x7fELF'
    data[4:6] = bytes([klass, 1])
    data[18:20] = machine.to_bytes(2, 'little')
    return bytes(data)


def badging(abi, version=20591, name='0.4.5-parserqa.arm.3', package=PACKAGE, sdk=26):
    return (f"package: name='{package}' versionCode='{version}' versionName='{name}'\n"
            f"sdkVersion:'{sdk}'\napplication-debuggable\nnative-code: '{abi}'\n")


class ArtifactContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.apk = Path(self.temp.name) / 'qa.apk'

    def write(self, abi='armeabi-v7a', *, missing=None, extra=None, wrong=None, duplicate=False):
        with zipfile.ZipFile(self.apk, 'w') as archive:
            for library in REQUIRED:
                if library != missing:
                    archive.writestr(f'lib/{abi}/{library}', header(wrong if library == 'libxul.so' and wrong else abi))
            if extra:
                archive.writestr(f'lib/{extra}/wrap.sh', b'other native payload')
            if duplicate:
                with warnings.catch_warnings():
                    warnings.simplefilter('ignore', UserWarning)
                    archive.writestr(f'lib/{abi}/libflutter.so', header(abi))
            archive.writestr('assets/flutter_assets/kernel_blob.bin', b'local fixture only')

    def verify(self, abi='armeabi-v7a', *, offline=False, text=None, permissions=None):
        if permissions is None:
            permissions = '' if offline else "uses-permission: name='android.permission.INTERNET'\n"
        return verify_artifact(self.apk, text or badging(abi), permissions, abi=abi,
                               build_number=20591, build_name='0.4.5-parserqa.arm.3', offline=offline)

    def test_all_three_targets_and_both_network_modes_keep_exact_base_version(self):
        for abi in ELF:
            for offline in (False, True):
                with self.subTest(abi=abi, offline=offline):
                    self.write(abi)
                    row = self.verify(abi, offline=offline)
                    self.assertEqual(row['native_abi'], abi)
                    self.assertEqual(row['actual_version_code'], 20591)
                    self.assertEqual(row['launch_only_build'], offline)

    def test_zip_rejects_fat_payload_even_when_aapt_claims_one_abi(self):
        for extra in ('arm64-v8a', 'x86_64', 'x86', 'unknown'):
            with self.subTest(extra=extra):
                self.write(extra=extra)
                with self.assertRaisesRegex(ValueError, 'non-target native ABI'):
                    self.verify()

    def test_all_required_runtimes_must_exist(self):
        for library in REQUIRED:
            self.write(missing=library)
            with self.assertRaisesRegex(ValueError, 'incomplete'):
                self.verify()

    def test_elf_machine_and_class_must_match_the_directory(self):
        self.write(wrong='arm64-v8a')
        with self.assertRaisesRegex(ValueError, 'ELF architecture'):
            self.verify()

    def test_actual_version_overrides_wrong_identity_and_min_sdk_are_rejected(self):
        self.write()
        for text in (badging('armeabi-v7a', version=205911),  # Existing repo split override.
                     badging('armeabi-v7a', version=21591),  # Flutter split override.
                     badging('armeabi-v7a', package='com.znbsf.kazumi.fluttertv'),
                     badging('armeabi-v7a', name='0.4.4'),
                     badging('armeabi-v7a', sdk=29),
                     badging('armeabi-v7a').replace('application-debuggable', ''),
                     badging('armeabi-v7a').replace("versionName=", "split='config.arm' versionName=")):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.verify(text=text)

    def test_internet_is_required_for_ordinary_and_forbidden_for_launch_only(self):
        self.write()
        for offline, permissions in ((True, "uses-permission: name='android.permission.INTERNET'"),
                                     (False, "application: label='android.permission.INTERNET'")):
            with self.assertRaisesRegex(ValueError, 'INTERNET'):
                self.verify(offline=offline, permissions=permissions)

    def test_aapt_native_declaration_must_match_zip_target(self):
        self.write()
        for text in (badging('x86_64'), badging('armeabi-v7a').replace("native-code: 'armeabi-v7a'", "native-code: 'armeabi-v7a' 'x86_64'")):
            with self.assertRaisesRegex(ValueError, 'ABI declaration'):
                self.verify(text=text)

    def test_duplicate_zip_entries_are_rejected(self):
        self.write(duplicate=True)
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.verify()


if __name__ == '__main__':
    unittest.main()
