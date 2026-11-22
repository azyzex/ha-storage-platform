"""PostgreSQL access: metadata only (the bytes live on GlusterFS)."""
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import DATABASE_URL

SCHEMA = """
CREATE TABLE IF NOT EXISTS files (
    id           UUID PRIMARY KEY,
    name         TEXT        NOT NULL,
    size_bytes   BIGINT      NOT NULL,
    sha256       CHAR(64)    NOT NULL,
    content_type TEXT        NOT NULL DEFAULT 'application/octet-stream',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""

# check_connection: a connection killed by a database restart is detected and replaced
# before it is handed to a request, so the API recovers on its own after Postgres comes back.
pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=10, open=False,
                      kwargs={"row_factory": dict_row},
                      check=ConnectionPool.check_connection)


def init() -> None:
    pool.open(wait=True, timeout=60)
    with pool.connection() as conn:
        conn.execute(SCHEMA)


def ping() -> bool:
    with pool.connection(timeout=2) as conn:
        conn.execute("SELECT 1")
    return True
