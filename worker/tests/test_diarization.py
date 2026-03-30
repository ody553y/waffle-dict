from __future__ import annotations

import unittest
from dataclasses import asdict

from screamer_worker.backends.diarization import DiarizationPipeline
from screamer_worker.models import DiarizationSegment


class _FakeTimeSegment:
    def __init__(self, start: float, end: float) -> None:
        self.start = start
        self.end = end


class _FakePyannoteResult:
    def __init__(self, entries: list[tuple[float, float, str]]) -> None:
        self._entries = entries

    def itertracks(self, yield_label: bool = False):
        for start, end, speaker in self._entries:
            if yield_label:
                yield _FakeTimeSegment(start, end), None, speaker
            else:
                yield _FakeTimeSegment(start, end), None


class _FakePipeline:
    def __call__(self, _file_path: str) -> _FakePyannoteResult:
        return _FakePyannoteResult(
            [
                (4.2, 5.4, "SPEAKER_02"),
                (0.0, 1.0, "SPEAKER_00"),
                (2.5, 3.5, "SPEAKER_01"),
            ]
        )


class _FakePipelineWithEmbeddings(_FakePipeline):
    def extract_speaker_embeddings(self, file_path: str, diarization_result: _FakePyannoteResult):
        _ = file_path
        _ = diarization_result
        return {
            "SPEAKER_00": [0.1, 0.2, 0.3],
            "SPEAKER_01": None,
            "SPEAKER_02": [0.5, 0.6, 0.7],
        }


class DiarizationPipelineTests(unittest.TestCase):
    def test_diarization_segment_dataclass_serialization(self) -> None:
        segment = DiarizationSegment(start=0.25, end=1.5, speaker="SPEAKER_00")
        self.assertEqual(
            asdict(segment),
            {"start": 0.25, "end": 1.5, "speaker": "SPEAKER_00"},
        )

    def test_is_available_false_without_token(self) -> None:
        pipeline = DiarizationPipeline(
            hf_token=None,
            pipeline_factory=lambda _model, _token: _FakePipeline(),
        )
        self.assertFalse(pipeline.is_available())

    def test_diarize_returns_sorted_segments(self) -> None:
        pipeline = DiarizationPipeline(
            hf_token="hf_test_token",
            pipeline_factory=lambda _model, _token: _FakePipeline(),
        )

        segments = pipeline.diarize("/tmp/fake-audio.wav")

        self.assertEqual(
            segments,
            [
                DiarizationSegment(start=0.0, end=1.0, speaker="SPEAKER_00"),
                DiarizationSegment(start=2.5, end=3.5, speaker="SPEAKER_01"),
                DiarizationSegment(start=4.2, end=5.4, speaker="SPEAKER_02"),
            ],
        )

    def test_diarize_with_embeddings_returns_per_speaker_vectors(self) -> None:
        pipeline = DiarizationPipeline(
            hf_token="hf_test_token",
            pipeline_factory=lambda _model, _token: _FakePipelineWithEmbeddings(),
        )

        segments, embeddings = pipeline.diarize_with_embeddings("/tmp/fake-audio.wav")

        self.assertEqual(len(segments), 3)
        self.assertEqual(embeddings["SPEAKER_00"], [0.1, 0.2, 0.3])
        self.assertEqual(embeddings["SPEAKER_01"], None)
        self.assertEqual(embeddings["SPEAKER_02"], [0.5, 0.6, 0.7])


if __name__ == "__main__":
    unittest.main()
