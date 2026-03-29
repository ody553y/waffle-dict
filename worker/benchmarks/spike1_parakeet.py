#!/usr/bin/env python3
"""Spike 1: Parakeet Apple Silicon benchmark.

Pass criteria (from plan):
  - RTF ≤ 0.3 on Apple Silicon

Usage:
    python3 -m benchmarks.spike1_parakeet --audio path/to/clip.wav

If no --audio is given, a 10s silence WAV is generated for a smoke test.
"""
from __future__ import annotations

import argparse
import struct
import tempfile
import time
from pathlib import Path


def generate_silence_wav(path: Path, duration_s: float = 10.0, sample_rate: int = 16000) -> None:
    num_samples = int(sample_rate * duration_s)
    data_size = num_samples * 2  # 16-bit mono
    with open(path, "wb") as f:
        f.write(b"RIFF")
        f.write(struct.pack("<I", 36 + data_size))
        f.write(b"WAVE")
        f.write(b"fmt ")
        f.write(struct.pack("<I", 16))
        f.write(struct.pack("<HH", 1, 1))  # PCM, mono
        f.write(struct.pack("<I", sample_rate))
        f.write(struct.pack("<I", sample_rate * 2))
        f.write(struct.pack("<HH", 2, 16))
        f.write(b"data")
        f.write(struct.pack("<I", data_size))
        f.write(b"\x00" * data_size)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", type=Path, default=None)
    args = parser.parse_args()

    try:
        import nemo.collections.asr as nemo_asr  # noqa: F401
    except ImportError:
        print("FAIL: NeMo ASR not installed.")
        print("Install with: pip install nemo_toolkit[asr]")
        raise SystemExit(1)

    audio_path = args.audio
    if audio_path is None:
        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        audio_path = Path(tmp.name)
        generate_silence_wav(audio_path)
        print(f"Generated 10s silence at {audio_path}")

    import wave

    with wave.open(str(audio_path), "rb") as wf:
        audio_duration = wf.getnframes() / wf.getframerate()

    print(f"Audio duration: {audio_duration:.1f}s")
    print("Loading model: nvidia/parakeet-tdt-0.6b-v3")

    t0 = time.perf_counter()
    model = nemo_asr.models.ASRModel.from_pretrained("nvidia/parakeet-tdt-0.6b-v3")
    load_time = time.perf_counter() - t0
    print(f"Model loaded in {load_time:.2f}s")

    t0 = time.perf_counter()
    transcriptions = model.transcribe([str(audio_path)])
    text = transcriptions[0] if transcriptions else ""
    transcribe_time = time.perf_counter() - t0

    rtf = transcribe_time / audio_duration
    print(f"Transcription time: {transcribe_time:.2f}s")
    print(f"RTF: {rtf:.3f}")
    print(f"Text: {text!r}")
    print()

    if rtf <= 0.3:
        print(f"PASS: RTF {rtf:.3f} ≤ 0.3")
    else:
        print(f"FAIL: RTF {rtf:.3f} > 0.3")

    if audio_duration <= 12 and transcribe_time <= 2.0:
        print(f"PASS: Latency {transcribe_time:.2f}s ≤ 2s for {audio_duration:.0f}s clip")
    elif audio_duration <= 12:
        print(f"FAIL: Latency {transcribe_time:.2f}s > 2s for {audio_duration:.0f}s clip")


if __name__ == "__main__":
    main()
