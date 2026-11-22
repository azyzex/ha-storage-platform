"""Client-side storage probe.

Every few seconds each API pod writes (with fsync), reads back and deletes a small file on the GlusterFS
volume and records how long each step took. This is storage latency as the application experiences it,
through the FUSE mount; it feeds the Grafana dashboard, the "storage slow" alert and the anomaly detector.
"""
import os
import threading
import time
from pathlib import Path

from prometheus_client import Counter, Histogram

PROBE = Histogram(
    "storage_probe_seconds", "Latency of a 4 KB probe on the storage volume", ["op"],
    buckets=(0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10))
FAILURES = Counter("storage_probe_failures_total", "Storage probe failures", ["op"])
PAYLOAD = os.urandom(4096)


def probe_once(data_dir: Path) -> None:
    path = data_dir / f".probe-{os.environ.get('HOSTNAME', 'local')}"
    op = "write"
    try:
        t0 = time.perf_counter()
        with path.open("wb") as f:
            f.write(PAYLOAD)
            f.flush()
            os.fsync(f.fileno())
        PROBE.labels("write").observe(time.perf_counter() - t0)

        op = "read"
        t0 = time.perf_counter()
        if path.read_bytes() != PAYLOAD:
            raise OSError("probe content mismatch")
        PROBE.labels("read").observe(time.perf_counter() - t0)
    except OSError:
        FAILURES.labels(op).inc()
    finally:
        path.unlink(missing_ok=True)


class Prober:
    def __init__(self, data_dir: Path, interval: float = 5.0):
        self.data_dir, self.interval = data_dir, interval
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, name="storage-probe", daemon=True)

    def _loop(self) -> None:
        while not self._stop.wait(self.interval):
            probe_once(self.data_dir)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
