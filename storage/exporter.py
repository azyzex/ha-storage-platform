"""Per-node GlusterFS exporter for Prometheus (runs inside every storage node, port 9713).

Why a custom exporter: the upstream gluster-prometheus project is unmaintained. This one reads the local
node's view through the gluster CLI and exposes a handful of metrics that matter for alerting:

  gluster_up                         1 if glusterd answers on this node
  gluster_peers_connected            peers this node sees as "Peer in Cluster (Connected)"
  gluster_volume_started{volume}     1 if the volume is started
  gluster_brick_up{volume,brick}     1 per brick reported online by "volume status"
  gluster_heal_pending_entries{volume,brick}   files waiting for self-heal on each brick
  gluster_brick_free_bytes{volume,brick}       free space on this node's brick filesystem

If the whole node dies, Prometheus loses the scrape target: `up == 0` is the "node down" signal.
"""
import os
import re
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET  # nosec B405 - parses trusted local gluster CLI output only

from prometheus_client import Gauge, start_http_server

VOLUME = os.environ.get("GLUSTER_VOLUME", "files")
BRICK_ROOT = os.environ.get("GLUSTER_BRICK_ROOT", "/bricks")
PORT = int(os.environ.get("EXPORTER_PORT", "9713"))
INTERVAL = float(os.environ.get("EXPORTER_INTERVAL", "5"))
NODE = os.environ.get("HOSTNAME", "unknown")

UP = Gauge("gluster_up", "glusterd answers on this node", ["node"])
PEERS = Gauge("gluster_peers_connected", "Peers in cluster and connected, seen from this node", ["node"])
STARTED = Gauge("gluster_volume_started", "Volume is started", ["node", "volume"])
BRICK_UP = Gauge("gluster_brick_up", "Brick online according to volume status", ["node", "volume", "brick"])
HEAL = Gauge("gluster_heal_pending_entries", "Entries pending self-heal per brick", ["node", "volume", "brick"])
FREE = Gauge("gluster_brick_free_bytes", "Free bytes on this node's brick filesystem", ["node", "volume", "brick"])


def gluster(*args: str, timeout: int = 15) -> str:
    out = subprocess.run(["gluster", "--mode=script", *args],  # nosec B603 B607 - fixed command, no user input
                         capture_output=True, text=True, timeout=timeout, check=True)
    return out.stdout


def collect() -> None:
    try:
        peers = gluster("peer", "status")
        UP.labels(NODE).set(1)
        PEERS.labels(NODE).set(peers.count("Peer in Cluster (Connected)"))
    except Exception:
        UP.labels(NODE).set(0)
        return

    try:
        info = gluster("volume", "info", VOLUME)
        STARTED.labels(NODE, VOLUME).set(1 if "Status: Started" in info else 0)
    except Exception:
        STARTED.labels(NODE, VOLUME).set(0)

    try:
        root = ET.fromstring(gluster("--xml", "volume", "status", VOLUME))  # nosec B314 - trusted local CLI output
        for node in root.iter("node"):
            host, path = node.findtext("hostname"), node.findtext("path")
            if path and path.startswith("/"):
                BRICK_UP.labels(NODE, VOLUME, f"{host}:{path}").set(1 if node.findtext("status") == "1" else 0)
    except Exception:
        pass

    try:
        heal = gluster("volume", "heal", VOLUME, "info", timeout=30)
        for brick, entries in re.findall(r"Brick (\S+)\n(?:.*\n)*?Number of entries: (\d+|-)", heal):
            if entries.isdigit():
                HEAL.labels(NODE, VOLUME, brick).set(int(entries))
    except Exception:
        pass

    local_brick = f"{BRICK_ROOT}/{VOLUME}"
    if os.path.isdir(local_brick):
        FREE.labels(NODE, VOLUME, f"{NODE}:{local_brick}").set(shutil.disk_usage(local_brick).free)


if __name__ == "__main__":
    start_http_server(PORT)
    while True:
        collect()
        time.sleep(INTERVAL)
