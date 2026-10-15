"""Adapt the existing bounded capture engine without duplicating it."""
import argparse
import importlib.util
import runpy
import sys
from pathlib import Path

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--tool-root', type=Path, required=True)
    p.add_argument('--serial', required=True)
    p.add_argument('--model', required=True)
    p.add_argument('--device', required=True)
    p.add_argument('--package', required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--seconds', type=int, choices=range(2, 16), default=15)
    a = p.parse_args()
    root = a.tool_root.resolve()
    if not all((root / name).is_file() for name in ('capture.py', 'latest_frame.py')):
        raise SystemExit('Existing capture engine missing; no device action performed')
    spec = importlib.util.spec_from_file_location('capture', root / 'capture.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.SERIAL = a.serial
    module.PACKAGE = a.package
    for prop, expected in [('ro.product.model', a.model), ('ro.product.device', a.device)]:
        actual = module.adb('shell', 'getprop', prop).strip()
        if actual != expected:
            raise SystemExit(f'Device identity mismatch: {prop}')
    if not module.foreground():
        raise SystemExit('Expected package is not focused; no capture started')
    sys.modules['capture'] = module
    sys.argv = [str(root / 'latest_frame.py'), '--seconds', str(a.seconds), '--out', str(a.out.resolve())]
    runpy.run_path(str(root / 'latest_frame.py'), run_name='__main__')

if __name__ == '__main__':
    main()
