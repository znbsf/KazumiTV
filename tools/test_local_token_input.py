import importlib.util
import json
import threading
import unittest
from http.client import HTTPConnection
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("token_input", Path(__file__).with_name("local_token_input.py"))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class LocalInputTest(unittest.TestCase):
    def test_http_write_only_one_shot_and_origin(self):
        server = bridge.LocalInputServer(("127.0.0.1", 0), bridge.make_handler("adb", "tv", "/test", "unused"))
        port = server.server_port
        origin = f"http://127.0.0.1:{port}"
        server.RequestHandlerClass = bridge.make_handler("adb", "tv", "/test", origin)
        server.sent = False
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with patch.object(bridge, "check_editor") as check, patch.object(bridge, "adb_run", return_value="") as run:
                def post(value, request_origin=origin):
                    connection = HTTPConnection("127.0.0.1", port, timeout=3)
                    connection.request("POST", "/test", json.dumps({"token": value}), {"Content-Type": "application/json", "Origin": request_origin})
                    response = connection.getresponse()
                    status, body = response.status, response.read()
                    connection.close()
                    return status, body

                self.assertEqual(post("new-token-123", "https://foreign.invalid")[0], 403)
                self.assertEqual(post("$(invalid)")[0], 400)
                run.assert_not_called()
                check.side_effect = RuntimeError("editor not empty")
                self.assertEqual(post("new-token-123")[0], 409)
                run.assert_not_called()
                check.side_effect = None
                status, body = post("new-token-123")
                self.assertEqual(status, 200)
                self.assertNotIn(b"new-token-123", body)
                run.assert_called_once_with("adb", "tv", "shell", "input", "text", "new-token-123")
                self.assertEqual(post("another-token-456")[0], 400)
                self.assertEqual(run.call_count, 1)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_editor_must_be_empty_focused_password_in_authorized_app(self):
        def outputs(text="", description="", password="true", focused="true", app=bridge.PACKAGE):
            return ["mulan", f"mCurrentFocus=Window{{ {app}/MainActivity }}", f'''<?xml version="1.0"?><hierarchy><node content-desc="Access Token"/><node class="android.widget.EditText" focused="{focused}" password="{password}" text="{text}" content-desc="{description}"/></hierarchy>''']

        for changes in [{"text": "previous-value"}, {"description": "previous-value"}, {"password": "false"}, {"focused": "false"}, {"app": "other.app"}]:
            with self.subTest(changes=changes), patch.object(bridge, "adb_run", side_effect=outputs(**changes)):
                with self.assertRaises(RuntimeError):
                    bridge.check_editor("adb", "tv")
        with patch.object(bridge, "adb_run", side_effect=outputs()):
            bridge.check_editor("adb", "tv")


if __name__ == "__main__":
    unittest.main()
