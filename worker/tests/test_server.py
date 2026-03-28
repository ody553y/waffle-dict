import json
import threading
import time
import unittest
from http.client import HTTPConnection
from pathlib import Path

from screamer_worker.backends.base import BackendCapabilities
from screamer_worker.server import make_server


class StubBackend:
    backend_id = "stub-whisper"
    capabilities = BackendCapabilities(
        supports_translation=True,
        supports_realtime_preview=False,
    )

    def prepare_model(self, model_id: str) -> None:
        return None

    def start_live_session(self, config) -> str:
        return config.session_id

    def finish_live_session(self, session_id: str) -> str:
        return session_id

    def transcribe_file(self, request) -> str:
        return f"transcribed:{Path(request.file_path).name}:{request.model_id}"

    def cancel_job(self, job_id: str) -> None:
        return None


class WorkerServerTests(unittest.TestCase):
    def test_health_endpoint_reports_worker_status(self) -> None:
        server = make_server(host="127.0.0.1", port=0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.05)

        try:
            conn = HTTPConnection("127.0.0.1", server.server_port, timeout=2)
            conn.request("GET", "/health")
            response = conn.getresponse()
            payload = json.loads(response.read())
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.assertEqual(response.status, 200)
        self.assertEqual(
            payload,
            {
                "service": "screamer-worker",
                "status": "ok",
                "version": "0.1.0",
            },
        )

    def test_unknown_route_returns_not_found_payload(self) -> None:
        server = make_server(host="127.0.0.1", port=0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.05)

        try:
            conn = HTTPConnection("127.0.0.1", server.server_port, timeout=2)
            conn.request("GET", "/missing")
            response = conn.getresponse()
            payload = json.loads(response.read())
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.assertEqual(response.status, 404)
        self.assertEqual(payload["error"], "not_found")

    def test_file_transcription_route_uses_registered_backend(self) -> None:
        server = make_server(
            host="127.0.0.1",
            port=0,
            transcription_backends={"stub-whisper": StubBackend()},
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.05)

        request_payload = {
            "job_id": "job-123",
            "model_id": "stub-whisper",
            "file_path": "/tmp/demo.wav",
            "language_hint": "en",
            "translate_to_english": False,
        }

        try:
            conn = HTTPConnection("127.0.0.1", server.server_port, timeout=2)
            conn.request(
                "POST",
                "/transcriptions/file",
                body=json.dumps(request_payload),
                headers={"Content-Type": "application/json"},
            )
            response = conn.getresponse()
            payload = json.loads(response.read())
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.assertEqual(response.status, 200)
        self.assertEqual(payload["job_id"], "job-123")
        self.assertEqual(payload["backend_id"], "stub-whisper")
        self.assertEqual(payload["text"], "transcribed:demo.wav:stub-whisper")


if __name__ == "__main__":
    unittest.main()
