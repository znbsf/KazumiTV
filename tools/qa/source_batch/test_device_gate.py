import unittest
from unittest.mock import patch
from run import Device, PACKAGE


class DeviceGateTests(unittest.TestCase):
    serial = '192.0.2.1:5555'
    fingerprint = 'fixture/vendor/device:9/release-keys'

    def device(self, **kwargs):
        return Device('never-execute', self.serial, allow_physical=True,
                      expected_serial=self.serial,
                      expected_fingerprint=self.fingerprint, **kwargs)

    def test_default_physical_denied_before_adb(self):
        with patch.object(Device, 'call') as call:
            with self.assertRaises(ValueError):
                Device('never-execute', self.serial)
            call.assert_not_called()

    def test_missing_binding_or_wrong_serial_denied_before_adb(self):
        for kwargs in [{}, {'expected_serial': 'another',
                            'expected_fingerprint': self.fingerprint},
                       {'expected_serial': self.serial}]:
            with patch.object(Device, 'call') as call:
                with self.assertRaises(ValueError):
                    Device('never-execute', self.serial, allow_physical=True, **kwargs)
                call.assert_not_called()

    def test_wrong_fingerprint_and_emulator_masquerade_denied(self):
        for values in [('0', 'different'), ('1', self.fingerprint)]:
            with patch.object(Device, 'call', side_effect=values):
                with self.assertRaises(ValueError):
                    self.device()

    def test_other_package_denied_before_adb(self):
        with patch.object(Device, 'call') as call:
            with self.assertRaises(ValueError):
                self.device(package=PACKAGE.removesuffix('.parserqa'))
            call.assert_not_called()

    def test_bound_physical_cleanup_only_stops_fixed_qa(self):
        with patch.object(Device, 'call', side_effect=['0', self.fingerprint]):
            device = self.device()
        with patch.object(device, 'call', return_value='') as call, \
                patch.object(device, 'processes', return_value={1: 'init'}):
            self.assertEqual(device.stop_and_verify()['status'], 'confirmed')
            call.assert_called_once_with('shell', f'am force-stop {PACKAGE}', timeout=8)
        self.assertTrue(device.physical)

    def test_emulator_path_still_checks_qemu(self):
        with patch.object(Device, 'call', return_value='1'):
            self.assertFalse(Device('never-execute', 'emulator-5582').physical)
        with patch.object(Device, 'call', return_value='0'):
            with self.assertRaises(ValueError):
                Device('never-execute', 'emulator-5582')

    def test_protected_snapshot_excludes_qa_and_reads_only_apk_identity(self):
        with patch.object(Device, 'call', side_effect=['0', self.fingerprint]):
            device = self.device()
        formal = PACKAGE.removesuffix('.parserqa')
        with patch.object(device, 'call', side_effect=[
                f'package:{PACKAGE}\npackage:{formal}\n',
                '/data/app/formal/base.apk', 'a' * 64 + '  /data/app/formal/base.apk',
        ]) as call:
            self.assertEqual(device.protected_packages(), {
                formal: {'apk_path': '/data/app/formal/base.apk', 'sha256': 'a' * 64}})
            self.assertEqual(len(call.call_args_list), 3)
            self.assertTrue(all(c.args[0] == 'shell' for c in call.call_args_list))

    def test_untrusted_protected_package_inventory_stops(self):
        with patch.object(Device, 'call', side_effect=['0', self.fingerprint]):
            device = self.device()
        with patch.object(device, 'call', return_value='package:bad;command') as call:
            with self.assertRaises(RuntimeError):
                device.protected_packages()
            self.assertEqual(call.call_count, 1)


if __name__ == '__main__':
    unittest.main()
