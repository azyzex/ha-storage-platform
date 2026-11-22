"""File storage API.

Upload / list / download / delete files. Bytes are written to DATA_DIR (the GlusterFS volume,
replicated on 3 nodes); metadata (name, size, sha256, type, date) goes to PostgreSQL.
The service is stateless, so any pod can serve any request and pods can be killed or scaled freely.
"""
import hashlib
import os
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, UploadFile
from fastapi.responses import FileResponse
from prometheus_fastapi_instrumentator import Instrumentator

from . import db
from .config import CHUNK, DATA_DIR, MAX_UPLOAD_BYTES
from .probe import Prober


@asynccontextmanager
async def lifespan(_: FastAPI):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    db.init()
    prober = Prober(DATA_DIR, float(os.environ.get("PROBE_INTERVAL", "5")))
    prober.start()
    yield
    prober.stop()
    db.pool.close()


app = FastAPI(title="HA Storage API", version="0.1.0", lifespan=lifespan)
Instrumentator().instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


def _path(file_id: uuid.UUID):
    return DATA_DIR / str(file_id)


@app.get("/api/healthz")
def healthz():
    """Liveness: the process is up."""
    return {"status": "ok", "pod": os.environ.get("HOSTNAME", "local")}


@app.get("/api/readyz")
def readyz():
    """Readiness: database reachable and storage writable."""
    try:
        db.ping()
        probe = DATA_DIR / f".ready-{os.environ.get('HOSTNAME', 'local')}"
        probe.write_bytes(b"ok")
        probe.unlink()
    except Exception as exc:  # report the reason, never crash the probe
        raise HTTPException(status_code=503, detail=f"not ready: {exc.__class__.__name__}") from exc
    return {"status": "ready"}


@app.post("/api/files", status_code=201)
async def upload(file: UploadFile):
    file_id = uuid.uuid4()
    final = _path(file_id)
    tmp = final.with_suffix(".part")
    digest, size = hashlib.sha256(), 0
    try:
        with tmp.open("wb") as out:
            while chunk := await file.read(CHUNK):
                size += len(chunk)
                if size > MAX_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="file too large")
                digest.update(chunk)
                out.write(chunk)
            out.flush()
            os.fsync(out.fileno())
        tmp.rename(final)  # atomic: readers never see a half-written file
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
    row = {
        "id": file_id,
        "name": os.path.basename((file.filename or "unnamed").replace("\\", "/"))[:255] or "unnamed",
        "size_bytes": size,
        "sha256": digest.hexdigest(),
        "content_type": file.content_type or "application/octet-stream",
    }
    with db.pool.connection() as conn:
        conn.execute(
            "INSERT INTO files (id, name, size_bytes, sha256, content_type) "
            "VALUES (%(id)s, %(name)s, %(size_bytes)s, %(sha256)s, %(content_type)s)", row)
    row["id"] = str(file_id)
    return row


@app.get("/api/files")
def list_files():
    with db.pool.connection() as conn:
        rows = conn.execute(
            "SELECT id::text, name, size_bytes, sha256, content_type, created_at "
            "FROM files ORDER BY created_at DESC LIMIT 500").fetchall()
    return rows


@app.get("/api/files/{file_id}")
def download(file_id: uuid.UUID):
    with db.pool.connection() as conn:
        row = conn.execute("SELECT name, content_type FROM files WHERE id = %s", (file_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="not found")
    path = _path(file_id)
    if not path.exists():
        raise HTTPException(status_code=410, detail="metadata exists but bytes are missing")
    return FileResponse(path, media_type=row["content_type"], filename=row["name"])


@app.delete("/api/files/{file_id}", status_code=204)
def delete(file_id: uuid.UUID):
    with db.pool.connection() as conn:
        deleted = conn.execute("DELETE FROM files WHERE id = %s RETURNING id", (file_id,)).fetchone()
    if not deleted:
        raise HTTPException(status_code=404, detail="not found")
    _path(file_id).unlink(missing_ok=True)
