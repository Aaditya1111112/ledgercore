"""Oracle connection pool and small query helpers.

Credentials come from environment variables (see .env.example).
Uses python-oracledb in thin mode, so no Oracle Client install is needed.
"""
import os
from datetime import date, datetime
from decimal import Decimal

import oracledb
from dotenv import load_dotenv

load_dotenv()

_pool = None


def get_pool():
    """Create the pool once, on first use."""
    global _pool
    if _pool is None:
        _pool = oracledb.create_pool(
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            dsn=os.environ.get("DB_DSN", "localhost:1521/XEPDB1"),
            min=1,
            max=5,
            increment=1,
        )
    return _pool


def _clean(value):
    """Turn Oracle types into JSON-friendly values."""
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return value


def query(sql, params=None):
    """Run a SELECT and return a list of dicts with lowercase keys."""
    with get_pool().acquire() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params or {})
            columns = [c[0].lower() for c in cur.description]
            return [
                {col: _clean(val) for col, val in zip(columns, row)}
                for row in cur.fetchall()
            ]


def query_one(sql, params=None):
    rows = query(sql, params)
    return rows[0] if rows else None
