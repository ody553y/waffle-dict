from __future__ import annotations

import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Mapping

from screamer_worker.backends.base import TranscriptionBackend
from screamer_worker.models import (
    FileTranscriptionRequest,
    FileTranscriptionResponse,
    HealthResponse,
)


class WorkerHTTPServer(ThreadingHTTPServer):
    def __init__(
        self,
        server_address: tuple[str, int],
        RequestHandlerClass: type[BaseHTTPRequestHandler],
        transcription_backends: Mapping[str, TranscriptionBackend] | None = None,
    ) -> None:
        super().__init__(server_address, RequestHandlerClass)
        self.transcription_backends = dict(transcription_backends or {})


class WorkerRequestHandler(BaseHTTPRequestHandler):
    server_version = "ScreamerWorker/0.1"

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path == "/health":
            self._write_json(HTTPStatus.OK, HealthResponse().to_dict())
            return

        self._write_json(
            HTTPStatus.NOT_FOUND,
            {"error": "not_found", "message": f"No route for {self.path}"},
        )

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path == "/transcriptions/file":
            request_payload = self._read_json()
            request = FileTranscriptionRequest(**request_payload)
            server = self.server
            assert isinstance(server, WorkerHTTPServer)
            backend = server.transcription_backends[request.model_id]
            text = backend.transcribe_file(request)
            response = FileTranscriptionResponse(
                job_id=request.job_id,
                backend_id=backend.backend_id,
                text=text,
            )
            self._write_json(HTTPStatus.OK, response.to_dict())
            return

        self._write_json(
            HTTPStatus.NOT_FOUND,
            {"error": "not_found", "message": f"No route for {self.path}"},
        )

    def log_message(self, format: str, *args: object) -> None:
        # Keep unit test output clean; production logging can be layered in later.
        return

    def _read_json(self) -> dict[str, object]:
        content_length = int(self.headers.get("Content-Length", "0"))
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
) -> WorkerHTTPServer:
    return WorkerHTTPServer(
        (host, port),
        WorkerRequestHandler,
        transcription_backends=transcription_backends,
    )


def serve(
    host: str = "127.0.0.1",
    port: int = 8765,
    transcription_backends: Mapping[str, TranscriptionBackend] | None = None,
) -> None:
    server = make_server(
        host=host,
        port=port,
        transcription_backends=transcription_backends,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
