from __future__ import annotations

import json
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Mapping

from screamer_worker.backends.diarization import DiarizationPipeline
from screamer_worker.backends.base import TranscriptionBackend
from screamer_worker.merge import merge_speakers
from screamer_worker.models import (
    DiarizationStatusResponse,
    FileTranscriptionRequest,
    FileTranscriptionResponse,
    HealthResponse,
)


class WorkerHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False

    def __init__(
        self,
        server_address: tuple[str, int],
        RequestHandlerClass: type[BaseHTTPRequestHandler],
        transcription_backends: Mapping[str, TranscriptionBackend] | None = None,
        diarization_pipeline: DiarizationPipeline | None = None,
    ) -> None:
        super().__init__(server_address, RequestHandlerClass)
        self.transcription_backends = dict(transcription_backends or {})
        self.diarization_pipeline = diarization_pipeline
        self.loaded_model_id: str | None = None


MAX_REQUEST_BODY_BYTES = 1024 * 1024  # 1 MiB


class RequestTooLargeError(ValueError):
    pass


class WorkerRequestHandler(BaseHTTPRequestHandler):
    server_version = "ScreamerWorker/0.1"
    protocol_version = "HTTP/1.0"

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path == "/health":
            server = self.server
            assert isinstance(server, WorkerHTTPServer)
            self._write_json(
                HTTPStatus.OK,
                HealthResponse(
                    model_loaded=server.loaded_model_id is not None,
                    model_id=server.loaded_model_id,
                ).to_dict(),
            )
            return

        if self.path == "/diarization/status":
            server = self.server
            assert isinstance(server, WorkerHTTPServer)
            diarization_pipeline = server.diarization_pipeline
            self._write_json(
                HTTPStatus.OK,
                DiarizationStatusResponse(
                    available=(
                        diarization_pipeline is not None
                        and diarization_pipeline.is_available()
                    ),
                    model=DiarizationPipeline.MODEL_ID,
                    embedding_support=True,
                ).to_dict(),
            )
            return

        self._write_json(
            HTTPStatus.NOT_FOUND,
            {"error": "not_found", "detail": f"No route for {self.path}"},
        )

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path == "/transcriptions/file":
            try:
                request_payload = self._read_json()
            except RequestTooLargeError as error:
                self._write_json(
                    HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                    {"error": "payload_too_large", "detail": str(error)},
                )
                return
            except (json.JSONDecodeError, ValueError) as error:
                self._write_json(
                    HTTPStatus.BAD_REQUEST,
                    {"error": "invalid_request_body", "detail": str(error)},
                )
                return

            try:
                request = FileTranscriptionRequest(**request_payload)
            except TypeError as error:
                self._write_json(
                    HTTPStatus.BAD_REQUEST,
                    {"error": "invalid_request_body", "detail": str(error)},
                )
                return

            if not Path(request.file_path).exists():
                self._write_json(
                    HTTPStatus.NOT_FOUND,
                    {"error": "file_not_found", "detail": f"Audio file does not exist: {request.file_path}"},
                )
                return

            server = self.server
            assert isinstance(server, WorkerHTTPServer)
            diarization_pipeline = server.diarization_pipeline
            if request.diarize:
                if (
                    diarization_pipeline is None
                    or diarization_pipeline.is_available() is False
                ):
                    self._write_json(
                        HTTPStatus.BAD_REQUEST,
                        {
                            "error": "diarization_unavailable",
                            "detail": (
                                "Speaker diarization requires a HuggingFace token. "
                                "Set HF_TOKEN or pass --hf-token."
                            ),
                        },
                    )
                    return

            backend = server.transcription_backends.get(request.model_id)
            if backend is None:
                self._write_json(
                    HTTPStatus.BAD_REQUEST,
                    {"error": "unknown_model", "detail": f"Unknown model_id: {request.model_id}"},
                )
                return

            try:
                backend.prepare_model(request.model_id)
                server.loaded_model_id = request.model_id
            except Exception as error:
                self._write_json(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    {"error": "model_unavailable", "detail": str(error)},
                )
                return

            started = time.perf_counter()
            try:
                transcription_result = backend.transcribe_file(request)
            except Exception as error:
                self._write_json(
                    HTTPStatus.INTERNAL_SERVER_ERROR,
                    {"error": "transcription_failed", "detail": str(error)},
                )
                return
            elapsed_seconds = time.perf_counter() - started
            print(
                f"[screamer-worker] transcribed job_id={request.job_id} "
                f"model_id={request.model_id} duration_seconds={elapsed_seconds:.3f}",
                flush=True,
            )

            segments = transcription_result.segments
            speaker_embeddings: dict[str, list[float] | None] | None = None

            if request.diarize:
                assert diarization_pipeline is not None
                try:
                    diarization_segments, speaker_embeddings = (
                        diarization_pipeline.diarize_with_embeddings(request.file_path)
                    )
                    if speaker_embeddings is None:
                        speaker_embeddings = {}
                    for diarization_segment in diarization_segments:
                        speaker_embeddings.setdefault(diarization_segment.speaker, None)
                except RuntimeError as error:
                    self._write_json(
                        HTTPStatus.BAD_REQUEST,
                        {
                            "error": "diarization_unavailable",
                            "detail": str(error),
                        },
                    )
                    return
                except Exception as error:
                    self._write_json(
                        HTTPStatus.INTERNAL_SERVER_ERROR,
                        {"error": "diarization_failed", "detail": str(error)},
                    )
                    return

                if segments is not None:
                    segments = merge_speakers(
                        transcription_segments=segments,
                        diarization_segments=diarization_segments,
                    )

            response = FileTranscriptionResponse(
                job_id=request.job_id,
                backend_id=backend.backend_id,
                text=transcription_result.text,
                segments=segments,
                speaker_embeddings=speaker_embeddings if request.diarize else None,
            )
            self._write_json(HTTPStatus.OK, response.to_dict())
            return

        self._write_json(
            HTTPStatus.NOT_FOUND,
            {"error": "not_found", "detail": f"No route for {self.path}"},
        )

    def log_message(self, format: str, *args: object) -> None:
        # Keep unit test output clean; production logging can be layered in later.
        return

    def _read_json(self) -> dict[str, object]:
        content_length = int(self.headers.get("Content-Length", "0"))
        if content_length < 1:
            raise ValueError("Request body must not be empty")
        if content_length > MAX_REQUEST_BODY_BYTES:
            raise RequestTooLargeError(
                f"Request body exceeds {MAX_REQUEST_BODY_BYTES} bytes"
            )
        body = self.rfile.read(content_length)
        return json.loads(body)

    def _write_json(self, status: HTTPStatus, payload: dict[str, object]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def make_server(
    host: str = "127.0.0.1",
    port: int = 8765,
    transcription_backends: Mapping[str, TranscriptionBackend] | None = None,
    diarization_pipeline: DiarizationPipeline | None = None,
) -> WorkerHTTPServer:
    return WorkerHTTPServer(
        (host, port),
        WorkerRequestHandler,
        transcription_backends=transcription_backends,
        diarization_pipeline=diarization_pipeline,
    )


def serve(
    host: str = "127.0.0.1",
    port: int = 8765,
    transcription_backends: Mapping[str, TranscriptionBackend] | None = None,
    diarization_pipeline: DiarizationPipeline | None = None,
) -> None:
    server = make_server(
        host=host,
        port=port,
        transcription_backends=transcription_backends,
        diarization_pipeline=diarization_pipeline,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
