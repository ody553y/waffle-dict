from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from waffle_worker.models import (
    BackendTranscriptionResult,
    FileTranscriptionRequest,
    LiveSessionConfig,
)


@dataclass(frozen=True)
class BackendCapabilities:
    supports_translation: bool
    supports_realtime_preview: bool


class TranscriptionBackend(Protocol):
    backend_id: str
    capabilities: BackendCapabilities

    def prepare_model(self, model_id: str) -> None:
        ...

    def start_live_session(self, config: LiveSessionConfig) -> str:
        ...

    def finish_live_session(self, session_id: str) -> str:
        ...

    def transcribe_file(
        self,
        request: FileTranscriptionRequest,
    ) -> BackendTranscriptionResult:
        ...

    def cancel_job(self, job_id: str) -> None:
        ...
