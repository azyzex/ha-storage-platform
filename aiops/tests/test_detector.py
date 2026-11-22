"""The detector stays quiet on normal noise and flags a sustained slowdown (no Prometheus needed)."""
from collections import deque

import numpy as np

import detector


def feed(history, rows):
    streak = [0]
    flags = []
    for row in rows:
        history.append(list(row))
        if len(history) > detector.RECENT:
            detector.evaluate(history, streak)
            flags.append(detector.ANOMALY._value.get())
    return flags


def normal_rows(rng, n):
    # write ~76 ms, read ~3 ms, no heal backlog, all bricks online (what CI measured)
    return np.column_stack([rng.normal(76, 6, n), rng.normal(3, 0.4, n), np.zeros(n), np.zeros(n)])


def test_quiet_on_normal_noise():
    rng = np.random.default_rng(1)
    flags = feed(deque(maxlen=500), normal_rows(rng, 60))
    assert sum(flags) == 0


def test_flags_sustained_slowdown_below_static_threshold():
    rng = np.random.default_rng(2)
    history = deque(maxlen=500)
    feed(history, normal_rows(rng, 40))
    slow = normal_rows(rng, 6)
    slow[:, 0] = rng.normal(230, 10, 6)   # 3x slower writes, still far below the 500 ms static alert
    flags = feed(history, slow)
    assert flags[-1] == 1
    assert detector.ZSCORE.labels("write_ms")._value.get() > 4   # explanation points at writes
