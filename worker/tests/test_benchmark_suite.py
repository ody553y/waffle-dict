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


if __name__ == "__main__":
    unittest.main()
