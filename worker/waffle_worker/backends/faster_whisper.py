from __future__ import annotations

import logging
from dataclasses import dataclass, field

from waffle_worker.backends.base import BackendCapabilities
from waffle_worker.models import (
    BackendTranscriptionResult,
    FileTranscriptionRequest,
    LiveSessionConfig,
    TranscriptionSegment,
)

logger = logging.getLogger(__name__)

try:
    from faster_whisper import WhisperModel

    _HAS_FASTER_WHISPER = True
except ImportError:
    _HAS_FASTER_WHISPER = False


@dataclass
class FasterWhisperBackend:
    backend_id: str = "faster-whisper"
    capabilities: BackendCapabilities = field(
        default_factory=lambda: BackendCapabilities(
            supports_translation=True,
            supports_realtime_preview=False,
        )
    )
    _models: dict[str, object] = field(default_factory=dict, repr=False)

    @staticmethod
    def _resolved_model_name(model_id: str) -> str:
        if model_id.startswith("whisper-"):
            return model_id.removeprefix("whisper-")
        return model_id

    def prepare_model(self, model_id: str) -> None:
        if not _HAS_FASTER_WHISPER:
            raise RuntimeError(
                "faster-whisper is not installed. "
                "Install it with: pip install faster-whisper"
            )
        if model_id in self._models:
            return
        resolved_model_id = self._resolved_model_name(model_id)
        logger.info("Loading faster-whisper model %s", resolved_model_id)
        self._models[model_id] = WhisperModel(
            resolved_model_id, device="cpu", compute_type="int8"
        )
        logger.info("Model %s loaded", resolved_model_id)

    def start_live_session(self, config: LiveSessionConfig) -> str:
        raise NotImplementedError("Live sessions not yet supported")

    def finish_live_session(self, session_id: str) -> str:
        raise NotImplementedError("Live sessions not yet supported")

    def transcribe_file(
        self,
        request: FileTranscriptionRequest,
    ) -> BackendTranscriptionResult:
        if not _HAS_FASTER_WHISPER:
            raise RuntimeError("faster-whisper is not installed")

        model = self._models.get(request.model_id)
        if model is None:
            self.prepare_model(request.model_id)
            model = self._models[request.model_id]

        task = "translate" if request.translate_to_english else "transcribe"
        segment_results, _info = model.transcribe(
            request.file_path,
            language=request.language_hint,
            task=task,
            beam_size=5,
        )

        segments: list[TranscriptionSegment] = []
        for segment in segment_results:
            segments.append(
                TranscriptionSegment(
                    start=float(segment.start),
                    end=float(segment.end),
                    text=segment.text.strip(),
                )
            )

        text = " ".join(
            segment.text for segment in segments if segment.text
        )
        return BackendTranscriptionResult(text=text, segments=segments)

    def cancel_job(self, job_id: str) -> None:
        pass
