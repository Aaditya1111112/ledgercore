"""Unit tests for error mapping. They do not need a database.

Run from the backend folder:  python -m pytest
"""
from services.errors import parse_oracle_error


def test_business_error_message_is_cleaned():
    msg = ("ORA-20004: Insufficient funds: balance 300.00, requested 700.00\n"
           "ORA-06512: at \"LEDGERCORE.LEDGER_PKG\", line 210")
    status, body = parse_oracle_error(20004, msg)
    assert status == 409
    assert body["error"] == "Insufficient funds: balance 300.00, requested 700.00"
    assert body["code"] == "ORA-20004"


def test_not_found_maps_to_404():
    status, _ = parse_oracle_error(20002, "ORA-20002: Account 99 does not exist")
    assert status == 404


def test_system_error_details_are_hidden():
    status, body = parse_oracle_error(1438, "ORA-01438: value larger than specified precision")
    assert status == 500
    assert "precision" not in body["error"]
    assert body["code"] == "ORA-01438"
