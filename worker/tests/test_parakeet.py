import json
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from waffle_worker.backends.base import BackendCapabilities
from waffle_worker.models import BackendTranscriptionResult
from waffle_worker.server import make_server


class ParakeetModelLoadFailureTest(unittest.TestCase):
    """Test that ParakeetBackend raises gracefully when NeMo is not installed."""

    def test_prepare_model_raises_when_nemo_not_installed(self) -> None:
        with patch.dict("sys.modules", {"nemo": None, "nemo.collections": None, "nemo.collections.asr": None}):
            # Re-import with NeMo mocked away to force _HAS_NEMO = False
            import importlib
            import waffle_worker.backends.parakeet as parakeet_mod

            original_has_nemo = parakeet_mod._HAS_NEMO
            parakeet_mod._HAS_NEMO = False
            try:
                backend = parakeet_mod.ParakeetBackend()
                with self.assertRaises(RuntimeError) as ctx:
                    backend.prepare_model("parakeet-0.6b")
                self.assertIn("NeMo toolkit is not installed", str(ctx.exception))
            finally:
                parakeet_mod._HAS_NEMO = original_has_nemo


class ParakeetTranscriptionStubTest(unittest.TestCase):
    """Test that parakeet-0.6b routes to the backend and returns transcription text."""

    def test_transcription_via_server_with_stub_parakeet(self) -> None:
        stub = _StubParakeetBackend()

        server = make_server(
            host="127.0.0.1",
            port=0,
            transcription_backends={"parakeet-0.6b": stub},
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.05)

        temp_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        temp_file.write(b"RIFF")
        temp_file.flush()
        temp_file.close()

        request_payload = {
            "job_id": "parakeet-job-1",
            "model_id": "parakeet-0.6b",
            "file_path": temp_file.name,
            "language_hint": None,
            "translate_to_english": False,
        }

        try:
            from http.client import HTTPConnection

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
        self.assertEqual(payload["job_id"], "parakeet-job-1")
        self.assertEqual(payload["backend_id"], "parakeet")
        self.assertEqual(payload["text"], "stub parakeet transcription")
        self.assertEqual(payload["segments"], None)


class _StubParakeetBackend:
    backend_id = "parakeet"
    capabilities = BackendCapabilities(
        supports_translation=False,
        supports_realtime_preview=False,
    )

    def prepare_model(self, model_id: str) -> None:
        pass

    def start_live_session(self, config) -> str:
        raise NotImplementedError

    def finish_live_session(self, session_id: str) -> str:
        raise NotImplementedError

    def transcribe_file(self, request) -> BackendTranscriptionResult:
        return BackendTranscriptionResult(
            text="stub parakeet transcription",
            segments=None,
        )

    def cancel_job(self, job_id: str) -> None:
        pass


if __name__ == "__main__":
    unittest.main()
