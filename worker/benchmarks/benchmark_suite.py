from __future__ import annotations

import argparse
import json
import platform
import resource
import tracemalloc
import wave
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from statistics import mean
from time import perf_counter
from typing import Any, Callable
from urllib import error, request
from uuid import uuid4


@dataclass(frozen=True)
class BenchmarkResult:
    model_id: str
    audio_duration_seconds: float
    mean_latency_seconds: float
    min_latency_seconds: float
    max_latency_seconds: float
    peak_memory_mb: float
    realtime_factor: float

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @staticmethod
    def from_dict(payload: dict[str, Any]) -> "BenchmarkResult":
        return BenchmarkResult(
            model_id=str(payload["model_id"]),
            audio_duration_seconds=float(payload["audio_duration_seconds"]),
            mean_latency_seconds=float(payload["mean_latency_seconds"]),
            min_latency_seconds=float(payload["min_latency_seconds"]),
            max_latency_seconds=float(payload["max_latency_seconds"]),
            peak_memory_mb=float(payload["peak_memory_mb"]),
            realtime_factor=float(payload["realtime_factor"]),
        )


class BenchmarkSuite:
    DEFAULT_MODEL_IDS = (
        "whisper-tiny",
        "whisper-base",
        "whisper-small",
        "whisper-medium",
        "whisper-large-v3",
        "parakeet-0.6b",
    )

    def __init__(self, host: str = "127.0.0.1", port: int = 8765) -> None:
        self.host = host
        self.port = port
        self.base_url = f"http://{host}:{port}"
        self._results: dict[str, BenchmarkResult] = {}

    def benchmark_transcription(
        self,
        model_id: str,
        audio_file: str,
        runs: int = 3,
    ) -> BenchmarkResult:
        audio_path = self._validated_audio_path(audio_file)
        run_count = self._validated_run_count(runs)
        audio_duration_seconds = self._audio_duration_seconds(audio_path)

        latencies: list[float] = []
        peak_memory_samples_mb: list[float] = []
        for _ in range(run_count):
            latency_seconds, peak_memory_mb = self._measure_call(
                lambda: self._request_transcription(
                    model_id=model_id,
                    audio_path=audio_path,
                    request_diarization=False,
                )
            )
            latencies.append(latency_seconds)
            peak_memory_samples_mb.append(peak_memory_mb)

        result = self._build_result(
            model_id=model_id,
            audio_duration_seconds=audio_duration_seconds,
            latencies=latencies,
            peak_memory_samples_mb=peak_memory_samples_mb,
        )
        self._results[model_id] = result
        return result

    def benchmark_diarization(self, audio_file: str, runs: int = 3) -> BenchmarkResult:
        audio_path = self._validated_audio_path(audio_file)
        run_count = self._validated_run_count(runs)
        audio_duration_seconds = self._audio_duration_seconds(audio_path)

        latencies: list[float] = []
        peak_memory_samples_mb: list[float] = []
        for _ in range(run_count):
            latency_seconds, peak_memory_mb = self._measure_call(
                lambda: self._request_transcription(
                    model_id="whisper-small",
                    audio_path=audio_path,
                    request_diarization=True,
                )
            )
            latencies.append(latency_seconds)
            peak_memory_samples_mb.append(peak_memory_mb)

        result = self._build_result(
            model_id="diarization",
            audio_duration_seconds=audio_duration_seconds,
            latencies=latencies,
            peak_memory_samples_mb=peak_memory_samples_mb,
        )
        self._results[result.model_id] = result
        return result

    def benchmark_all_models(self, audio_file: str) -> dict[str, BenchmarkResult]:
        discovered_model_ids = self._discover_model_ids()
        benchmarked: dict[str, BenchmarkResult] = {}

        for model_id in discovered_model_ids:
            try:
                benchmarked[model_id] = self.benchmark_transcription(model_id, audio_file)
            except RuntimeError as exc:
                if self._is_skippable_model_error(exc):
                    print(f"[benchmarks] skipping {model_id}: {exc}")
                    continue
                raise

        if not benchmarked:
            raise RuntimeError(
                "No models were benchmarked successfully. Confirm the worker is running "
                "and at least one model is installed."
            )

        return benchmarked

    def report(self) -> str:
        if not self._results:
            return "No benchmark results recorded yet."

        rows = [
            [
                "Model",
                "Audio (s)",
                "Mean (s)",
                "Min (s)",
                "Max (s)",
                "Peak RSS/Heap (MB)",
                "RTF",
            ]
        ]

        for result in sorted(self._results.values(), key=lambda item: item.model_id):
            rows.append(
                [
                    result.model_id,
                    f"{result.audio_duration_seconds:.2f}",
                    f"{result.mean_latency_seconds:.2f}",
                    f"{result.min_latency_seconds:.2f}",
                    f"{result.max_latency_seconds:.2f}",
                    f"{result.peak_memory_mb:.2f}",
                    f"{result.realtime_factor:.2f}",
                ]
            )

        return _format_table(rows)

    def save_results(
        self,
        results: dict[str, BenchmarkResult] | None = None,
        output_dir: Path | None = None,
    ) -> Path:
        payload_results = results if results is not None else self._results
        if not payload_results:
            raise RuntimeError("No benchmark results available to save.")

        root_output_dir = output_dir or Path(__file__).resolve().parent / "results"
        root_output_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        output_path = root_output_dir / f"benchmark-{timestamp}.json"

        payload = {
            "generated_at": datetime.now(tz=timezone.utc).isoformat(),
            "host": self.host,
            "port": self.port,
            "results": {
                model_id: result.to_dict()
                for model_id, result in sorted(payload_results.items())
            },
        }
        output_path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
        return output_path

    def _validated_audio_path(self, audio_file: str) -> Path:
        audio_path = Path(audio_file).expanduser().resolve()
        if not audio_path.exists():
            raise FileNotFoundError(f"Audio fixture not found: {audio_path}")
        if not audio_path.is_file():
            raise FileNotFoundError(f"Audio fixture is not a file: {audio_path}")
        return audio_path

    def _validated_run_count(self, runs: int) -> int:
        if runs < 1:
            raise ValueError("runs must be >= 1")
        return runs

    def _audio_duration_seconds(self, audio_path: Path) -> float:
        if audio_path.suffix.lower() != ".wav":
            raise ValueError(
                f"Only WAV fixtures are supported for benchmark timing metadata: {audio_path.name}"
            )

        with wave.open(str(audio_path), "rb") as handle:
            frame_rate = handle.getframerate()
            frame_count = handle.getnframes()

        if frame_rate <= 0:
            raise ValueError(f"Invalid WAV sample rate in {audio_path}")
        return frame_count / frame_rate

    def _measure_call(self, fn: Callable[[], Any]) -> tuple[float, float]:
        rss_before_mb = self._ru_maxrss_mb()
        tracemalloc.start()
        tracemalloc.reset_peak()

        started_at = perf_counter()
        fn()
        latency_seconds = perf_counter() - started_at

        _current_bytes, peak_bytes = tracemalloc.get_traced_memory()
        tracemalloc.stop()

        rss_after_mb = self._ru_maxrss_mb()
        rss_growth_mb = max(0.0, rss_after_mb - rss_before_mb)
        heap_peak_mb = peak_bytes / (1024 * 1024)
        peak_memory_mb = max(rss_growth_mb, heap_peak_mb)
        return latency_seconds, peak_memory_mb

    def _ru_maxrss_mb(self) -> float:
        usage = resource.getrusage(resource.RUSAGE_SELF)
        if platform.system() == "Darwin":
            return usage.ru_maxrss / (1024 * 1024)
        return usage.ru_maxrss / 1024

    def _request_transcription(
        self,
        model_id: str,
        audio_path: Path,
        request_diarization: bool,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "job_id": f"benchmark-{uuid4()}",
            "model_id": model_id,
            "file_path": str(audio_path),
            "language_hint": None,
            "translate_to_english": False,
            "diarize": request_diarization,
        }

        response = self._post_json("/transcriptions/file", payload)
        if request_diarization and "speaker_embeddings" not in response:
            raise RuntimeError(
                "Expected diarization response to include speaker_embeddings"
            )
        return response

    def _post_json(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        body = json.dumps(payload).encode("utf-8")
        req = request.Request(
            url=f"{self.base_url}{path}",
            method="POST",
            headers={"Content-Type": "application/json"},
            data=body,
        )

        try:
            with request.urlopen(req, timeout=600) as response:
                response_body = response.read().decode("utf-8")
                return json.loads(response_body)
        except error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"Worker returned HTTP {exc.code} for {path}: {detail}"
            ) from exc
        except error.URLError as exc:
            raise RuntimeError(
                f"Worker request failed for {path}: {exc.reason}"
            ) from exc

    def _request_health(self) -> dict[str, Any] | None:
        try:
            with request.urlopen(f"{self.base_url}/health", timeout=10) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception:
            return None

    def _discover_model_ids(self) -> list[str]:
        candidates = list(self.DEFAULT_MODEL_IDS)
        health = self._request_health()
        loaded_model_id = health.get("model_id") if health else None
        if isinstance(loaded_model_id, str) and loaded_model_id:
            candidates.insert(0, loaded_model_id)
        return _dedupe_preserving_order(candidates)

    def _is_skippable_model_error(self, exc: RuntimeError) -> bool:
        message = str(exc)
        return "unknown_model" in message or "model_unavailable" in message

    def _build_result(
        self,
        model_id: str,
        audio_duration_seconds: float,
        latencies: list[float],
        peak_memory_samples_mb: list[float],
    ) -> BenchmarkResult:
        mean_latency = mean(latencies)
        return BenchmarkResult(
            model_id=model_id,
            audio_duration_seconds=audio_duration_seconds,
            mean_latency_seconds=mean_latency,
            min_latency_seconds=min(latencies),
            max_latency_seconds=max(latencies),
            peak_memory_mb=max(peak_memory_samples_mb),
            realtime_factor=(audio_duration_seconds / mean_latency) if mean_latency > 0 else 0.0,
        )


def _dedupe_preserving_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    deduped: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        deduped.append(item)
    return deduped


def _format_table(rows: list[list[str]]) -> str:
    column_count = max(len(row) for row in rows)
    widths = [0] * column_count

    for row in rows:
        for idx, value in enumerate(row):
            widths[idx] = max(widths[idx], len(value))

    formatted_rows: list[str] = []
    for idx, row in enumerate(rows):
        padded = [row[column].ljust(widths[column]) for column in range(column_count)]
        formatted_rows.append(" | ".join(padded))
        if idx == 0:
            separator = ["-" * widths[column] for column in range(column_count)]
            formatted_rows.append("-+-".join(separator))
    return "\n".join(formatted_rows)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Benchmark Waffle worker performance.")
    parser.add_argument("--host", default="127.0.0.1", help="Worker host")
    parser.add_argument("--port", type=int, default=8765, help="Worker port")
    parser.add_argument("--model", help="Model ID to benchmark")
    parser.add_argument("--audio", required=True, help="Path to a WAV audio fixture")
    parser.add_argument("--runs", type=int, default=3, help="Benchmark runs per model")
    parser.add_argument(
        "--all",
        action="store_true",
        dest="benchmark_all",
        help="Benchmark all discovered model IDs",
    )
    parser.add_argument(
        "--diarization",
        action="store_true",
        help="Benchmark diarization-enabled transcription",
    )

    args = parser.parse_args()
    if not args.benchmark_all and not args.diarization and not args.model:
        parser.error("either --model, --all, or --diarization is required")
    return args


def main() -> None:
    args = _parse_args()
    suite = BenchmarkSuite(host=args.host, port=args.port)

    if args.benchmark_all:
        results = suite.benchmark_all_models(args.audio)
    elif args.diarization:
        result = suite.benchmark_diarization(args.audio, runs=args.runs)
        results = {result.model_id: result}
    else:
        assert args.model is not None
        result = suite.benchmark_transcription(args.model, args.audio, runs=args.runs)
        results = {result.model_id: result}

    print(suite.report())

    output_path = suite.save_results(results)
    print(f"\nSaved JSON results to {output_path}")
    print(
        json.dumps(
            {model_id: result.to_dict() for model_id, result in sorted(results.items())},
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
