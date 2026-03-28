from __future__ import annotations

import logging
from dataclasses import dataclass, field

from screamer_worker.backends.base import BackendCapabilities
from screamer_worker.models import FileTranscriptionRequest, LiveSessionConfig

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

    def prepare_model(self, model_id: str) -> None:
        if not _HAS_FASTER_WHISPER:
            raise RuntimeError(
                "faster-whisper is not installed. "
                "Install it with: pip install faster-whisper"
            )
        if model_id in self._models:
            return
        logger.info("Loading faster-whisper model %s", model_id)
        self._models[model_id] = WhisperModel(
            model_id, device="cpu", compute_type="int8"
        )
        logger.info("Model %s loaded", model_id)

    def start_live_session(self, config: LiveSessionConfig) -> str:
        raise NotImplementedError("Live sessions not yet supported")

    def finish_live_session(self, session_id: str) -> str:
        raise NotImplementedError("Live sessions not yet supported")

    def transcribe_file(self, request: FileTranscriptionRequest) -> str:
        if not _HAS_FASTER_WHISPER:
            raise RuntimeError("faster-whisper is not installed")

        model = self._models.get(request.model_id)
        if model is None:
            self.prepare_model(request.model_id)
            model = self._models[request.model_id]

        task = "translate" if request.translate_to_english else "transcribe"
        segments, _info = model.transcribe(
            request.file_path,
            language=request.language_hint,
            task=task,
            beam_size=5,
        )
        return " ".join(seg.text.strip() for seg in segments)

    def cancel_job(self, job_id: str) -> None:
        pass
