"""Generate Gecko's MAIN-world script from the production parser, not a fork."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]

def prepare():
    source = (ROOT / 'lib/webview/video/legacy_parser_scripts.dart').read_text(encoding='utf-8')
    script = source.split("const _script = r'''", 1)[1].split("''';", 1)[0]
    script = script.replace('__SESSION__', '1').replace('__IFRAME_ONLY__', 'false')
    bridge = """// Generated from legacy_parser_scripts.dart by tools/qa/source_batch/prepare.py.
window.flutter_inappwebview = {callHandler: function(handler, url) {
  window.postMessage({type: 'kazumi-parser-qa', handler: handler, url: url}, location.origin);
}};
"""
    target = ROOT / 'android/app/src/parserQa/assets/parserqa/parser.generated.js'
    target.write_text(bridge + script, encoding='utf-8')
    print(json.dumps({'parser_sha256': hashlib.sha256(script.encode()).hexdigest()}))

if __name__ == '__main__':
    prepare()
