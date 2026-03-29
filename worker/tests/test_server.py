import json
import tempfile
import threading
import time
import unittest
from http.client import HTTPConnection
from pathlib import Path

from screamer_worker.backends.base import BackendCapabilities
from screamer_worker.models import BackendTranscriptionResult, TranscriptionSegment
from screamer_worker.server import MAX_REQUEST_BODY_BYTES, make_server


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

    def transcribe_file(self, request) -> BackendTranscriptionResult:
        text = f"transcribed:{Path(request.file_path).name}:{request.model_id}"
        return BackendTranscriptionResult(
            text=text,
            segments=[
                TranscriptionSegment(start=0.0, end=1.0, text=text),
            ],
        )

    def cancel_job(self, job_id: str) -> None:
        return None


class FailingPrepareBackend(StubBackend):
    def prepare_model(self, model_id: str) -> None:
        raise RuntimeError("model load failed")


class StubNoSegmentsBackend(StubBackend):
    def transcribe_file(self, request) -> BackendTranscriptionResult:
        return BackendTranscriptionResult(
            text=f"transcribed:{Path(request.file_path).name}:{request.model_id}",
            segments=None,
        )


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
            conn.close()
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
                "model_loaded": False,
                "model_id": None,
            },
        )

    def test_health_reports_loaded_model_after_successful_transcription(self) -> None:
        temp_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        temp_file.write(b"RIFF")
        temp_file.flush()
        temp_file.close()

        server = make_server(
            host="127.0.0.1",
            port=0,
            transcription_backends={"stub-whisper": StubBackend()},
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.05)

        request_payload = {
            "job_id": "job-health",
            "model_id": "stub-whisper",
            "file_path": temp_file.name,
            "language_hint": None,
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
            _transcription_response = conn.getresponse()
            _transcription_response.read()

            conn.request("GET", "/health")
            response = conn.getresponse()
            payload = json.loads(response.read())
        finally:
            conn.close()
            Path(temp_file.name).unlink(missing_ok=True)
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.assertEqual(response.status, 200)
        self.assertEqual(payload["model_loaded"], True)
        self.assertEqual(payload["model_id"], "stub-whisper")

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
            conn.close()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.assertEqual(response.status, 404)
        self.assertEqual(payload["error"], "not_found")

    def test_file_transcription_route_uses_registered_backend(self) -> None:
        temp_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        temp_file.write(b"RIFF")
        temp_file.flush()
        temp_file.close()

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
            "file_path": temp_file.name,
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
            conn.close()
            Path(temp_file.name).unlink(missing_ok=True)
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.assertEqual(response.status, 200)
        self.assertEqual(payload["job_id"], "job-123")
        self.assertEqual(payload["backend_id"], "stub-whisper")
        self.assertEqual(payload["text"], f"transcribed:{Path(temp_file.name).name}:stub-whisper")
        self.assertEqual(
            payload["segments"],
            [
                {
                    "start": 0.0,
                    "end": 1.0,
                    "text": f"transcribed:{Path(temp_file.name).name}:stub-whisper",
                }
            ],
        )

    def test_file_transcription_route_returns_null_segments_when_backend_omits_them(self) -> None:
        temp_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        temp_file.write(b"RIFF")
        temp_file.flush()
        temp_file.close()

        server = make_server(
            host="127.0.0.1",
            port=0,
            transcription_backends={"stub-whisper": StubNoSegmentsBackend()},
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.05)

        request_payload = {
            "job_id": "job-234",
            "model_id": "stub-whisper",
            "file_path": temp_file.name,
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
            conn.close()
            Path(temp_file.name).unlink(missing_ok=True)
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.assertEqual(response.status, 200)
        self.assertEqual(payload["job_id"], "job-234")
        self.assertEqual(payload["backend_id"], "stub-whisper")
        self.assertEqual(payload["segments"], None)

    def test_file_transcription_returns_404_when_audio_file_missing(self) -> None:
        server = make_server(
            host="127.0.0.1",
            port=0,
            transcription_backends={"stub-whisper": StubBackend()},
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.05)

        request_payload = {
            "job_id": "job-404",
            "model_id": "stub-whisper",
            "file_path": "/tmp/does-not-exist.wav",
            "language_hint": None,
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
            conn.close()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.assertEqual(response.status, 404)
        self.assertEqual(payload["error"], "file_not_found")
        self.assertIn("detail", payload)

    def test_file_transcription_returns_503_when_model_load_fails(self) -> None:
        temp_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        temp_file.write(b"RIFF")
        temp_file.flush()
        temp_file.close()

        server = make_server(
            host="127.0.0.1",
            port=0,
            transcription_backends={"stub-whisper": FailingPrepareBackend()},
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.05)

        request_payload = {
            "job_id": "job-503",
            "model_id": "stub-whisper",
            "file_path": temp_file.name,
            "language_hint": None,
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
            conn.close()
            Path(temp_file.name).unlink(missing_ok=True)
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.assertEqual(response.status, 503)
        self.assertEqual(payload["error"], "model_unavailable")
        self.assertIn("detail", payload)

    def test_file_transcription_returns_400_for_malformed_body(self) -> None:
        server = make_server(
            host="127.0.0.1",
            port=0,
            transcription_backends={"stub-whisper": StubBackend()},
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.05)

        try:
            conn = HTTPConnection("127.0.0.1", server.server_port, timeout=2)
            conn.request(
                "POST",
                "/transcriptions/file",
                body="{not-valid-json",
                headers={"Content-Type": "application/json"},
            )
            response = conn.getresponse()
            payload = json.loads(response.read())
        finally:
            conn.close()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.assertEqual(response.status, 400)
        self.assertEqual(payload["error"], "invalid_request_body")
        self.assertIn("detail", payload)

    def test_file_transcription_rejects_payloads_over_content_length_limit(self) -> None:
        server = make_server(
            host="127.0.0.1",
            port=0,
            transcription_backends={"stub-whisper": StubBackend()},
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.05)

        try:
            conn = HTTPConnection("127.0.0.1", server.server_port, timeout=5)
            conn.putrequest("POST", "/transcriptions/file")
            conn.putheader("Content-Type", "application/json")
            conn.putheader("Content-Length", str(MAX_REQUEST_BODY_BYTES + 1))
            conn.endheaders()
            response = conn.getresponse()
            payload = json.loads(response.read())
        finally:
            conn.close()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.assertEqual(response.status, 413)
        self.assertEqual(payload["error"], "payload_too_large")
        self.assertIn("detail", payload)


if __name__ == "__main__":
    unittest.main()
