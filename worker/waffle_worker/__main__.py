import argparse
import os
import sys

from waffle_worker.backends.diarization import DiarizationPipeline
from waffle_worker.server import serve


def main() -> None:
    parser = argparse.ArgumentParser(description="Waffle worker")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--hf-token",
        default=None,
        help="HuggingFace token used for pyannote speaker diarization.",
    )
    args = parser.parse_args()

    backends: dict = {}

    try:
        from waffle_worker.backends.faster_whisper import FasterWhisperBackend

        fw = FasterWhisperBackend()
        for model_id in [
            "whisper-tiny",
            "whisper-base",
            "whisper-small",
            "whisper-medium",
            "whisper-large-v3",
            "tiny",
            "base",
            "small",
            "medium",
            "large-v3",
            fw.backend_id,
        ]:
            backends[model_id] = fw
    except Exception:
        pass

    try:
        from waffle_worker.backends.parakeet import ParakeetBackend

        pk = ParakeetBackend()
        backends["parakeet-0.6b"] = pk
        backends[pk.backend_id] = pk
    except Exception:
        pass

    hf_token = args.hf_token or os.getenv("HF_TOKEN")
    diarization_pipeline = DiarizationPipeline(hf_token=hf_token)

    serve(
        host=args.host,
        port=args.port,
        transcription_backends=backends,
        diarization_pipeline=diarization_pipeline,
    )


if __name__ == "__main__":
    main()
