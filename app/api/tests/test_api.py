"""API tests against a real PostgreSQL (CI service container) and a temp data dir."""
import hashlib
import os

import pytest
from fastapi.testclient import TestClient


@pytest.fixture(scope="module")
def client(tmp_path_factory):
    os.environ["DATA_DIR"] = str(tmp_path_factory.mktemp("data"))
    from app.main import app
    with TestClient(app) as c:
        yield c


def test_health(client):
    assert client.get("/api/healthz").json()["status"] == "ok"
    assert client.get("/api/readyz").status_code == 200


def test_upload_download_roundtrip(client):
    payload = os.urandom(300_000)
    r = client.post("/api/files", files={"file": ("demo.bin", payload, "application/octet-stream")})
    assert r.status_code == 201
    meta = r.json()
    assert meta["size_bytes"] == len(payload)
    assert meta["sha256"] == hashlib.sha256(payload).hexdigest()

    got = client.get(f"/api/files/{meta['id']}")
    assert got.status_code == 200 and got.content == payload
    assert any(f["id"] == meta["id"] for f in client.get("/api/files").json())


def test_filename_is_sanitized(client):
    r = client.post("/api/files", files={"file": ("../../etc/passwd", b"x", "text/plain")})
    assert r.json()["name"] == "passwd"


def test_delete_and_404(client):
    meta = client.post("/api/files", files={"file": ("a.txt", b"hello", "text/plain")}).json()
    assert client.delete(f"/api/files/{meta['id']}").status_code == 204
    assert client.get(f"/api/files/{meta['id']}").status_code == 404
    assert client.get("/api/files/not-a-uuid").status_code == 422
