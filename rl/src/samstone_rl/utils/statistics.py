"""Numerically stable statistics shared by policy and card comparisons."""

from __future__ import annotations

import math


def sign_test(better: int, worse: int) -> float:
    if min(better, worse) < 0:
        raise ValueError("les effectifs doivent etre positifs")
    count = better + worse
    if not count:
        return 1.0
    log_term = log_tail = -count * math.log(2.0)
    for index in range(1, min(better, worse) + 1):
        log_term += math.log(count - index + 1) - math.log(index)
        high, low = max(log_tail, log_term), min(log_tail, log_term)
        log_tail = high + math.log1p(math.exp(low - high))
    return min(1.0, math.exp(log_tail + math.log(2.0)))
