"""Storage anomaly detector (AIOps).

Every STEP seconds it reads a few health signals from Prometheus, learns what "normal" looks like from the
samples it has collected so far, and scores the latest samples with an Isolation Forest. It exposes:

  aiops_anomaly                     1 when the recent samples look abnormal (2 consecutive anomalous samples)
  aiops_anomaly_score               > 0 means outside the learned normal region (-decision_function)
  aiops_feature_zscore{feature}     robust z-score of each signal vs the baseline (explains *why*)
  aiops_baseline_samples            how many samples the current model was trained on
  aiops_feature_value{feature}      the raw latest value of each signal

Why: static thresholds (e.g. "write latency > 500 ms") miss gray failures, such as one slow node that makes
every replicated write 3x slower but stays under the threshold. The model learns this system's own normal.
Scope (honest): it learns from what it has seen since it started; a production version would train on
weeks of history and handle daily/weekly seasonality.
"""
import logging
import os
import time
from collections import deque

import numpy as np
import requests
from prometheus_client import Gauge, start_http_server
from sklearn.ensemble import IsolationForest

PROM = os.environ.get("PROMETHEUS_URL", "http://kps-prometheus.monitoring:9090")
STEP = float(os.environ.get("STEP_SECONDS", "15"))
RECENT = int(os.environ.get("RECENT_SAMPLES", "4"))          # newest samples kept out of training (1 min)
MIN_TRAIN = int(os.environ.get("MIN_TRAIN_SAMPLES", "16"))   # ~4 min of baseline before judging
MAX_HISTORY = int(os.environ.get("MAX_HISTORY_SAMPLES", "960"))  # ~4 h at 15 s

FEATURES = {
    "write_ms": '1000 * sum(rate(storage_probe_seconds_sum{op="write"}[1m])) '
                '/ sum(rate(storage_probe_seconds_count{op="write"}[1m]))',
    "read_ms": '1000 * sum(rate(storage_probe_seconds_sum{op="read"}[1m])) '
               '/ sum(rate(storage_probe_seconds_count{op="read"}[1m]))',
    "heal_pending": "sum(max by (brick) (gluster_heal_pending_entries)) or vector(0)",
    "bricks_offline": "3 - (count(min by (brick) (gluster_brick_up) == 1) or vector(0))",
}

ANOMALY = Gauge("aiops_anomaly", "1 when recent storage behaviour is abnormal")
SCORE = Gauge("aiops_anomaly_score", "Isolation Forest anomaly score of the latest sample (>0 = abnormal)")
ZSCORE = Gauge("aiops_feature_zscore", "Robust z-score of a signal vs the learned baseline", ["feature"])
VALUE = Gauge("aiops_feature_value", "Latest raw value of a signal", ["feature"])
TRAINED = Gauge("aiops_baseline_samples", "Samples the current model was trained on")

log = logging.getLogger("aiops")


def query(expr: str) -> float | None:
    r = requests.get(f"{PROM}/api/v1/query", params={"query": expr}, timeout=10)
    r.raise_for_status()
    result = r.json()["data"]["result"]
    if not result:
        return None
    v = float(result[0]["value"][1])
    return None if np.isnan(v) or np.isinf(v) else v


def sample() -> list[float] | None:
    values = []
    for name, expr in FEATURES.items():
        v = query(expr)
        if v is None:
            return None
        values.append(v)
        VALUE.labels(name).set(v)
    return values


def evaluate(history: deque, streak: list[int]) -> None:
    data = np.array(history, dtype=float)
    train, recent = data[:-RECENT], data[-RECENT:]
    TRAINED.set(len(train))
    if len(train) < MIN_TRAIN:
        return
    median = np.median(train, axis=0)
    mad = np.median(np.abs(train - median), axis=0) * 1.4826
    # floor the spread so flat signals (e.g. heal_pending always 0) don't explode the z-score
    spread = np.maximum(mad, np.maximum(0.05 * np.abs(median), 1e-3))
    z_train, z_recent = (train - median) / spread, (recent - median) / spread

    model = IsolationForest(n_estimators=200, contamination="auto", random_state=0).fit(z_train)
    score = float(-model.decision_function(z_recent[-1:])[0])
    SCORE.set(score)
    for name, z in zip(FEATURES, z_recent[-1]):
        ZSCORE.labels(name).set(float(z))

    # an anomaly needs both the model and a material shift in at least one signal (|z| > 4)
    is_anomalous = score > 0 and float(np.max(np.abs(z_recent[-1]))) > 4
    streak[0] = streak[0] + 1 if is_anomalous else 0
    ANOMALY.set(1 if streak[0] >= 2 else 0)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    start_http_server(int(os.environ.get("PORT", "9100")))
    history: deque = deque(maxlen=MAX_HISTORY)
    streak = [0]
    while True:
        t0 = time.monotonic()
        try:
            s = sample()
            if s is not None:
                history.append(s)
                if len(history) > RECENT:
                    evaluate(history, streak)
        except Exception as exc:  # keep running; Prometheus may be restarting
            log.warning("cycle failed: %s", exc)
        time.sleep(max(0.0, STEP - (time.monotonic() - t0)))


if __name__ == "__main__":
    main()
