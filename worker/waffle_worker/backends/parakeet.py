from __future__ import annotations

import logging
from dataclasses import dataclass, field

from waffle_worker.backends.base import BackendCapabilities
from waffle_worker.models import (
    BackendTranscriptionResult,
    FileTranscriptionRequest,
    LiveSessionConfig,
)

logger = logging.getLogger(__name__)

try:
    import nemo.collections.asr as nemo_asr

    _HAS_NEMO = True
except ImportError:
    _HAS_NEMO = False


@dataclass
class ParakeetBackend:
    backend_id: str = "parakeet"
    capabilities: BackendCapabilities = field(
        default_factory=lambda: BackendCapabilities(
            supports_translation=False,
            supports_realtime_preview=False,
        )
    )
    _model: object | None = field(default=None, repr=False)
    _loaded_model_id: str | None = field(default=None, repr=False)

    def prepare_model(self, model_id: str) -> None:
        if not _HAS_NEMO:
            raise RuntimeError(
                "NeMo toolkit is not installed. "
                "Install it with: pip install nemo_toolkit[asr]"
            )
        if self._loaded_model_id == model_id:
            return
        logger.info("Loading Parakeet model %s", model_id)
        self._model = nemo_asr.models.ASRModel.from_pretrained(
            "nvidia/parakeet-tdt-0.6b-v3"
        )
        self._loaded_model_id = model_id
        logger.info("Parakeet model %s loaded", model_id)

    def start_live_session(self, config: LiveSessionConfig) -> str:
        raise NotImplementedError("Live sessions not yet supported for Parakeet")

    def finish_live_session(self, session_id: str) -> str:
        raise NotImplementedError("Live sessions not yet supported for Parakeet")

    def transcribe_file(
        self,
        request: FileTranscriptionRequest,
    ) -> BackendTranscriptionResult:
        if not _HAS_NEMO:
            raise RuntimeError("NeMo toolkit is not installed")

        if self._model is None:
            self.prepare_model(request.model_id)

        transcriptions = self._model.transcribe([request.file_path])
        if not transcriptions:
            return BackendTranscriptionResult(text="", segments=None)
        return BackendTranscriptionResult(
            text=transcriptions[0],
            segments=None,
        )

    def cancel_job(self, job_id: str) -> None:
        pass
