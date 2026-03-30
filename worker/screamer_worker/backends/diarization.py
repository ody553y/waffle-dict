from __future__ import annotations

from typing import Any, Callable

from screamer_worker.models import DiarizationSegment

try:
    from pyannote.audio import Pipeline as _PyannotePipeline

    _HAS_PYANNOTE = True
except ImportError:
    _PyannotePipeline = None
    _HAS_PYANNOTE = False


def _default_pipeline_factory(model_id: str, hf_token: str) -> Any:
    if _PyannotePipeline is None:
        raise RuntimeError("pyannote.audio is not installed")
    return _PyannotePipeline.from_pretrained(model_id, use_auth_token=hf_token)


class DiarizationPipeline:
    MODEL_ID = "pyannote/speaker-diarization-3.1"

    def __init__(
        self,
        hf_token: str | None = None,
        pipeline_factory: Callable[[str, str], Any] | None = None,
    ) -> None:
        token = (hf_token or "").strip()
        self._hf_token = token or None
        self._pipeline_factory = (
            pipeline_factory
            if pipeline_factory is not None
            else (_default_pipeline_factory if _HAS_PYANNOTE else None)
        )
        self._pipeline: Any | None = None
        self._pipeline_failed = False

    def is_available(self) -> bool:
        return (
            self._pipeline_factory is not None
            and self._hf_token is not None
            and self._pipeline_failed is False
        )

    def diarize(self, file_path: str) -> list[DiarizationSegment]:
        if self.is_available() is False:
            raise RuntimeError(
                "Speaker diarization is unavailable. "
                "Install pyannote.audio and set HF_TOKEN or pass --hf-token."
            )

        pipeline = self._ensure_pipeline()
        diarization_result = pipeline(file_path)

        segments: list[DiarizationSegment] = []
        for turn, _track, speaker in diarization_result.itertracks(yield_label=True):
            segments.append(
                DiarizationSegment(
                    start=float(turn.start),
                    end=float(turn.end),
                    speaker=str(speaker),
                )
            )

        segments.sort(key=lambda segment: (segment.start, segment.end, segment.speaker))
        return segments

    def _ensure_pipeline(self) -> Any:
        if self._pipeline is not None:
            return self._pipeline

        if self._pipeline_factory is None or self._hf_token is None:
            raise RuntimeError(
                "Speaker diarization is unavailable. "
                "Install pyannote.audio and set HF_TOKEN or pass --hf-token."
            )

        try:
            self._pipeline = self._pipeline_factory(self.MODEL_ID, self._hf_token)
        except Exception as error:
            self._pipeline_failed = True
            raise RuntimeError(f"Failed to initialize diarization pipeline: {error}") from error

        return self._pipeline
