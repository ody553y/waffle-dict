from __future__ import annotations

import json
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from benchmarks.benchmark_suite import BenchmarkResult, BenchmarkSuite


class BenchmarkSuiteTests(unittest.TestCase):
    def test_benchmark_result_serialization_round_trip(self) -> None:
        result = BenchmarkResult(
            model_id="whisper-small",
            audio_duration_seconds=60.0,
            mean_latency_seconds=20.0,
            min_latency_seconds=18.0,
            max_latency_seconds=24.0,
            peak_memory_mb=512.0,
            realtime_factor=3.0,
        )

        payload = result.to_dict()
        self.assertEqual(payload["model_id"], "whisper-small")
        self.assertEqual(payload["audio_duration_seconds"], 60.0)
        self.assertEqual(payload["realtime_factor"], 3.0)

        encoded = json.dumps(payload)
        decoded = BenchmarkResult.from_dict(json.loads(encoded))
        self.assertEqual(decoded, result)

    def test_report_formats_console_table(self) -> None:
        suite = BenchmarkSuite()
        suite._results = {
            "whisper-small": BenchmarkResult(
                model_id="whisper-small",
                audio_duration_seconds=60.0,
                mean_latency_seconds=20.0,
                min_latency_seconds=19.0,
                max_latency_seconds=21.0,
                peak_memory_mb=420.0,
                realtime_factor=3.0,
            ),
            "parakeet-0.6b": BenchmarkResult(
                model_id="parakeet-0.6b",
                audio_duration_seconds=60.0,
                mean_latency_seconds=30.0,
                min_latency_seconds=29.0,
                max_latency_seconds=31.0,
                peak_memory_mb=650.0,
                realtime_factor=2.0,
            ),
        }

        report = suite.report()

        self.assertIn("Model", report)
        self.assertIn("Mean (s)", report)
        self.assertIn("whisper-small", report)
        self.assertIn("parakeet-0.6b", report)
        self.assertIn("3.00", report)

    def test_diarization_request_uses_worker_diarize_field(self) -> None:
        suite = BenchmarkSuite()
        captured: dict[str, object] = {}

        def fake_post_json(path: str, payload: dict[str, object]) -> dict[str, object]:
            captured["path"] = path
            captured["payload"] = payload
            return {"speaker_embeddings": {}}

        suite._post_json = fake_post_json  # type: ignore[method-assign]
        suite._request_transcription(
            model_id="whisper-small",
            audio_path=Path("/tmp/example.wav"),
            request_diarization=True,
        )

        self.assertEqual(captured["path"], "/transcriptions/file")
        payload = captured["payload"]
        self.assertIsInstance(payload, dict)
        assert isinstance(payload, dict)
        self.assertEqual(payload.get("diarize"), True)
        self.assertNotIn("request_diarization", payload)

    def test_diarization_request_requires_speaker_embeddings_in_response(self) -> None:
        suite = BenchmarkSuite()

        def fake_post_json(_path: str, _payload: dict[str, object]) -> dict[str, object]:
            return {"text": "ok"}

        suite._post_json = fake_post_json  # type: ignore[method-assign]

        with self.assertRaisesRegex(RuntimeError, "speaker_embeddings"):
            suite._request_transcription(
                model_id="whisper-small",
                audio_path=Path("/tmp/example.wav"),
                request_diarization=True,
            )


if __name__ == "__main__":
    unittest.main()
