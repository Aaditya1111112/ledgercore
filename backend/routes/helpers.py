"""Small input checks. The database re-checks everything anyway."""
from flask import request

from services.errors import ApiError


def body():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ApiError("Request body must be JSON")
    return data


def require(data, *fields):
    missing = [f for f in fields if data.get(f) in (None, "")]
    if missing:
        raise ApiError("Missing field(s): " + ", ".join(missing))


def as_int(value, name):
    try:
        return int(value)
    except (TypeError, ValueError):
        raise ApiError(f"{name} must be a whole number")


def as_amount(value):
    try:
        amount = float(value)
    except (TypeError, ValueError):
        raise ApiError("amount must be a number")
    return value if isinstance(value, str) else amount
