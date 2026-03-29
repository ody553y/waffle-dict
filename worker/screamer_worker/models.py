from __future__ import annotations

from dataclasses import asdict, dataclass, field


@dataclass(frozen=True)
class HealthResponse:
    service: str = "screamer-worker"
    status: str = "ok"
    version: str = "0.1.0"
    model_loaded: bool = False
    model_id: str | None = None

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


@dataclass(frozen=True)
class RecordingConfig:
    sample_rate_hz: int
    channels: int
    language_hint: str | None = None
    enable_realtime_preview: bool = False


@dataclass(frozen=True)
class LiveSessionConfig:
    session_id: str
    model_id: str
    recording: RecordingConfig
    metadata: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class FileTranscriptionRequest:
    job_id: str
    model_id: str
    file_path: str
    language_hint: str | None = None
    translate_to_english: bool = False


@dataclass(frozen=True)
class FileTranscriptionResponse:
    job_id: str
    backend_id: str
    text: str

    def to_dict(self) -> dict[str, str]:
        return asdict(self)
