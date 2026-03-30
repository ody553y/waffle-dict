from __future__ import annotations

import math
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
        segments, _speaker_embeddings = self.diarize_with_embeddings(file_path)
        return segments

    def diarize_with_embeddings(
        self,
        file_path: str,
    ) -> tuple[list[DiarizationSegment], dict[str, list[float] | None]]:
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
        speaker_durations: dict[str, float] = {}
        for segment in segments:
            segment_duration = max(0.0, segment.end - segment.start)
            speaker_durations[segment.speaker] = (
                speaker_durations.get(segment.speaker, 0.0) + segment_duration
            )

        extracted_embeddings = self._extract_speaker_embeddings(
            pipeline=pipeline,
            file_path=file_path,
            diarization_result=diarization_result,
        )

        speaker_embeddings: dict[str, list[float] | None] = {}
        for speaker_label in sorted(speaker_durations.keys()):
            # Very short samples are unreliable for profile-level matching.
            if speaker_durations.get(speaker_label, 0.0) < 1.0:
                speaker_embeddings[speaker_label] = None
                continue

            speaker_embeddings[speaker_label] = extracted_embeddings.get(speaker_label)

        return segments, speaker_embeddings

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

    def _extract_speaker_embeddings(
        self,
        *,
        pipeline: Any,
        file_path: str,
        diarization_result: Any,
    ) -> dict[str, list[float] | None]:
        extractor = getattr(pipeline, "extract_speaker_embeddings", None)
        if callable(extractor):
            try:
                raw = extractor(
                    file_path=file_path,
                    diarization_result=diarization_result,
                )
            except TypeError:
                raw = extractor(file_path, diarization_result)
            return self._normalize_embedding_map(raw)

        raw_from_result = getattr(diarization_result, "speaker_embeddings", None)
        if raw_from_result is not None:
            return self._normalize_embedding_map(raw_from_result)

        return {}

    def _normalize_embedding_map(self, raw: Any) -> dict[str, list[float] | None]:
        if isinstance(raw, dict) is False:
            return {}

        normalized: dict[str, list[float] | None] = {}
        for key, value in raw.items():
            normalized[str(key)] = self._coerce_embedding(value)
        return normalized

    def _coerce_embedding(self, value: Any) -> list[float] | None:
        if value is None:
            return None

        if hasattr(value, "tolist"):
            value = value.tolist()

        if isinstance(value, (list, tuple)) is False:
            return None

        embedding: list[float] = []
        for element in value:
            try:
                numeric = float(element)
            except (TypeError, ValueError):
                return None
            if math.isfinite(numeric) is False:
                return None
            embedding.append(numeric)

        return embedding if embedding else None
