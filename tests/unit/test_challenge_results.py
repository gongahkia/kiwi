from __future__ import annotations

from kiwi.app.challenge_results import ChallengeHistory, ChallengeOutcome, ChallengeResult


def test_challenge_history_retains_local_metric_histograms_without_a_composite_score() -> None:
    history = ChallengeHistory(
        (
            ChallengeResult("practice_7", "a" * 64, ChallengeOutcome.FAILURE, 1, 40, 280, 20, 4),
            ChallengeResult("practice_7", "b" * 64, ChallengeOutcome.SUCCESS, 0, 30, 240, 15, 3),
        )
    )

    buckets = history.histogram("practice_7", "ticks", bins=2)

    assert tuple(bucket.count for bucket in buckets) == (1, 1)
    assert history.for_challenge("practice_7")[1].outcome is ChallengeOutcome.SUCCESS
