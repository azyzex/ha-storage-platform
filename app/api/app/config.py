"""Runtime settings, read from environment variables (set by Kubernetes)."""
import os
from pathlib import Path

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://storage:storage@localhost:5432/storage")
# Where file bytes go. In the cluster this is the GlusterFS mount (hostPath /mnt/gluster).
DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
MAX_UPLOAD_BYTES = int(os.environ.get("MAX_UPLOAD_BYTES", str(200 * 1024 * 1024)))  # 200 MB
CHUNK = 1024 * 1024
