# Worker Benchmarks

The benchmark suite measures transcription latency, memory usage, and realtime factor (RTF) against a running worker instance.

## Prerequisites

1. Start the worker in a separate shell:

```bash
cd worker
python -m waffle_worker --host 127.0.0.1 --port 8765
```

2. Generate local WAV fixtures (do not commit large audio files):

```bash
cd worker/benchmarks
mkdir -p fixtures
ffmpeg -f lavfi -i "anoisesrc=color=white:duration=10" -ar 16000 -ac 1 fixtures/short-10s.wav
ffmpeg -f lavfi -i "anoisesrc=color=white:duration=60" -ar 16000 -ac 1 fixtures/medium-60s.wav
ffmpeg -f lavfi -i "anoisesrc=color=white:duration=300" -ar 16000 -ac 1 fixtures/long-300s.wav
```

## Usage

Run from the `worker/` directory.

```bash
python -m benchmarks.benchmark_suite --model whisper-small --audio benchmarks/fixtures/medium-60s.wav --runs 5
python -m benchmarks.benchmark_suite --all --audio benchmarks/fixtures/medium-60s.wav
python -m benchmarks.benchmark_suite --diarization --audio benchmarks/fixtures/medium-60s.wav --runs 3
```

Outputs:
- Console table report
- JSON payload on stdout
- Timestamped JSON file saved to `worker/benchmarks/results/`

## Metrics

- **Mean/Min/Max latency (seconds):** request-to-response timing per run
- **Peak RSS/Heap (MB):** max of `ru_maxrss` growth and Python heap peak (`tracemalloc`)
- **Realtime Factor (RTF):** `audio_duration_seconds / mean_latency_seconds`
  - `RTF > 1` means faster than real-time

