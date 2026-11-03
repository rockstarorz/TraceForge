import http.client
import json
import threading
import unittest

from server import BridgeServer


class ServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = BridgeServer(("127.0.0.1", 0))
        cls.server.run_job = lambda *_: None
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def request(self, method, path, payload=None, token=True):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        headers = {"Content-Type": "application/json"}
        if token:
            headers["X-Bridge-Token"] = self.server.token
        connection.request(method, path, json.dumps(payload) if payload is not None else None, headers)
        response = connection.getresponse()
        result = response.status, response.read()
        connection.close()
        return result

    def test_local_token_required(self):
        self.assertEqual(self.request("GET", "/api/status", token=False)[0], 403)
        self.assertEqual(self.request("GET", "/api/status")[0], 200)

    def test_arbitrary_text_has_no_trn_or_length_gate(self):
        seen = []
        self.server.run_job = lambda _, text, protocol, mode: seen.append((text, protocol, mode))
        self.server.busy = False
        status, _ = self.request("POST", "/api/jobs", {
            "text": "x" * 1_000_001, "protocol": "concox", "window_mode": "background",
        })
        self.assertEqual(status, 202)
        self.assertEqual(seen[-1][0], "x" * 1_000_001)
        self.server.busy = False

    def test_busy_rejects_second_job(self):
        self.server.busy = False
        self.server.run_job = lambda *_: None
        self.assertEqual(self.request("POST", "/api/jobs", {"text": "anything"})[0], 202)
        self.assertEqual(self.request("POST", "/api/jobs", {"text": "anything"})[0], 409)
        self.server.busy = False


if __name__ == "__main__":
    unittest.main()
