from __future__ import annotations

from screamer_worker.models import DiarizationSegment, TranscriptionSegment


def merge_speakers(
    transcription_segments: list[TranscriptionSegment],
    diarization_segments: list[DiarizationSegment],
) -> list[TranscriptionSegment]:
    if transcription_segments == []:
        return []

    if diarization_segments == []:
        return [
            TranscriptionSegment(
                start=segment.start,
                end=segment.end,
                text=segment.text,
                speaker=segment.speaker,
            )
            for segment in transcription_segments
        ]

    diarization_segments_sorted = sorted(
        diarization_segments,
        key=lambda segment: (segment.start, segment.end, segment.speaker),
    )

    merged: list[TranscriptionSegment] = []
    for transcription_segment in transcription_segments:
        midpoint = (transcription_segment.start + transcription_segment.end) / 2.0
        matched = _match_diarization_segment(
            midpoint=midpoint,
            diarization_segments=diarization_segments_sorted,
        )
        merged.append(
            TranscriptionSegment(
                start=transcription_segment.start,
                end=transcription_segment.end,
                text=transcription_segment.text,
                speaker=matched.speaker if matched is not None else transcription_segment.speaker,
            )
        )

    return merged


def _match_diarization_segment(
    midpoint: float,
    diarization_segments: list[DiarizationSegment],
) -> DiarizationSegment | None:
    if diarization_segments == []:
        return None

    overlaps = [
        segment
        for segment in diarization_segments
        if segment.start <= midpoint <= segment.end
    ]
    if overlaps:
        return min(overlaps, key=lambda segment: (segment.end - segment.start, segment.start))

    return min(
        diarization_segments,
        key=lambda segment: (_distance_to_segment(midpoint, segment), segment.start, segment.end),
    )


def _distance_to_segment(midpoint: float, segment: DiarizationSegment) -> float:
    if midpoint < segment.start:
        return segment.start - midpoint
    if midpoint > segment.end:
        return midpoint - segment.end
    return 0.0
