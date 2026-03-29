import argparse
import sys

from screamer_worker.server import serve


def main() -> None:
    parser = argparse.ArgumentParser(description="Screamer worker")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    backends: dict = {}

    try:
        from screamer_worker.backends.faster_whisper import FasterWhisperBackend

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
        from screamer_worker.backends.parakeet import ParakeetBackend

        pk = ParakeetBackend()
        backends["parakeet-0.6b"] = pk
        backends[pk.backend_id] = pk
    except Exception:
        pass

    serve(host=args.host, port=args.port, transcription_backends=backends)


if __name__ == "__main__":
    main()
