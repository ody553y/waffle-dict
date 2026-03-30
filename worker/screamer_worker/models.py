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
    diarize: bool = False


@dataclass(frozen=True)
class FileTranscriptionResponse:
    job_id: str
    backend_id: str
    text: str
    segments: list["TranscriptionSegment"] | None = None
    speaker_embeddings: dict[str, list[float] | None] | None = None

    def to_dict(self) -> dict[str, object]:
        payload: dict[str, object] = {
            "job_id": self.job_id,
            "backend_id": self.backend_id,
            "text": self.text,
            "segments": None,
        }
        if self.segments is not None:
            payload["segments"] = [segment.to_dict() for segment in self.segments]
        if self.speaker_embeddings is not None:
            payload["speaker_embeddings"] = self.speaker_embeddings
        return payload


@dataclass(frozen=True)
class TranscriptionSegment:
    start: float
    end: float
    text: str
    speaker: str | None = None

    def to_dict(self) -> dict[str, object]:
        payload: dict[str, object] = {
            "start": self.start,
            "end": self.end,
            "text": self.text,
        }
        if self.speaker is not None:
            payload["speaker"] = self.speaker
        return payload


@dataclass(frozen=True)
class DiarizationSegment:
    start: float
    end: float
    speaker: str


@dataclass(frozen=True)
class DiarizationStatusResponse:
    available: bool
    model: str
    embedding_support: bool = True

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


@dataclass(frozen=True)
class BackendTranscriptionResult:
    text: str
    segments: list[TranscriptionSegment] | None = None

    def to_dict(self) -> dict[str, object]:
        return asdict(self)
