from __future__ import annotations

import unittest

from screamer_worker.merge import merge_speakers
from screamer_worker.models import DiarizationSegment, TranscriptionSegment


class MergeSpeakersTests(unittest.TestCase):
    def test_merge_assigns_speaker_for_exact_midpoint_overlap(self) -> None:
        transcription_segments = [
            TranscriptionSegment(start=0.0, end=1.0, text="hello"),
            TranscriptionSegment(start=1.0, end=2.0, text="there"),
        ]
        diarization_segments = [
            DiarizationSegment(start=0.0, end=1.2, speaker="SPEAKER_00"),
            DiarizationSegment(start=1.2, end=2.2, speaker="SPEAKER_01"),
        ]

        merged = merge_speakers(transcription_segments, diarization_segments)

        self.assertEqual(merged[0].speaker, "SPEAKER_00")
        self.assertEqual(merged[1].speaker, "SPEAKER_01")

    def test_merge_assigns_nearest_when_no_overlap_exists(self) -> None:
        transcription_segments = [
            TranscriptionSegment(start=10.0, end=12.0, text="late segment"),
        ]
        diarization_segments = [
            DiarizationSegment(start=0.0, end=1.0, speaker="SPEAKER_00"),
            DiarizationSegment(start=15.0, end=16.0, speaker="SPEAKER_01"),
        ]

        merged = merge_speakers(transcription_segments, diarization_segments)

        self.assertEqual(merged[0].speaker, "SPEAKER_01")

    def test_merge_uses_midpoint_for_partial_overlap_boundaries(self) -> None:
        transcription_segments = [
            TranscriptionSegment(start=4.0, end=4.8, text="boundary segment"),
        ]
        diarization_segments = [
            DiarizationSegment(start=3.9, end=4.3, speaker="SPEAKER_00"),
            DiarizationSegment(start=4.3, end=5.0, speaker="SPEAKER_01"),
        ]

        merged = merge_speakers(transcription_segments, diarization_segments)

        self.assertEqual(merged[0].speaker, "SPEAKER_01")

    def test_merge_returns_unmodified_segments_when_no_diarization_segments(self) -> None:
        transcription_segments = [
            TranscriptionSegment(start=0.0, end=1.0, text="hello"),
            TranscriptionSegment(start=1.0, end=2.0, text="world"),
        ]

        merged = merge_speakers(transcription_segments, [])

        self.assertEqual(
            merged,
            [
                TranscriptionSegment(start=0.0, end=1.0, text="hello", speaker=None),
                TranscriptionSegment(start=1.0, end=2.0, text="world", speaker=None),
            ],
        )


if __name__ == "__main__":
    unittest.main()
