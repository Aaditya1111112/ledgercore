from flask import Blueprint, jsonify

from services import ledger_service
from services.db import query, query_one
from services.errors import ApiError
from .helpers import as_int, body, require

bp = Blueprint("accounts", __name__)


@bp.get("/customers")
def list_customers():
    return jsonify(query("""
        SELECT c.customer_id, c.full_name, c.email, c.phone, c.created_at,
               COUNT(a.account_id) AS account_count
        FROM customers c LEFT JOIN accounts a ON a.customer_id = c.customer_id
        GROUP BY c.customer_id, c.full_name, c.email, c.phone, c.created_at
        ORDER BY c.customer_id"""))


@bp.post("/customers")
def create_customer():
    data = body()
    require(data, "full_name", "email")
    customer_id = ledger_service.create_customer(
        data["full_name"], data["email"], data.get("phone")
    )
    return jsonify({"customer_id": customer_id}), 201


@bp.get("/accounts")
def list_accounts():
    return jsonify(query("SELECT * FROM v_account_overview ORDER BY account_id"))


@bp.get("/accounts/<int:account_id>")
def get_account(account_id):
    row = query_one(
        """SELECT o.*, get_transaction_count(o.account_id) AS transaction_count
           FROM v_account_overview o WHERE o.account_id = :id""",
        {"id": account_id},
    )
    if row is None:
        raise ApiError(f"Account {account_id} does not exist", 404)
    return jsonify(row)


@bp.post("/accounts")
def create_account():
    data = body()
    require(data, "customer_id", "account_type")
    account_id, account_no = ledger_service.create_account(
        as_int(data["customer_id"], "customer_id"), data["account_type"]
    )
    return jsonify({"account_id": account_id, "account_no": account_no}), 201


@bp.patch("/accounts/<int:account_id>/status")
def set_status(account_id):
    data = body()
    require(data, "status")
    ledger_service.set_status(account_id, data["status"])
    return jsonify({"account_id": account_id, "status": data["status"].upper()})


@bp.get("/accounts/<int:account_id>/statement")
def statement(account_id):
    account = query_one("SELECT * FROM v_account_overview WHERE account_id = :id", {"id": account_id})
    if account is None:
        raise ApiError(f"Account {account_id} does not exist", 404)
    entries = query(
        """SELECT e.entry_id, e.transaction_id, e.entry_type, e.amount, e.balance_after,
                  e.created_at, t.transaction_type, t.description
           FROM account_entries e JOIN transactions t ON t.transaction_id = e.transaction_id
           WHERE e.account_id = :id
           ORDER BY e.entry_id DESC
           FETCH FIRST 200 ROWS ONLY""",
        {"id": account_id},
    )
    return jsonify({"account": account, "entries": entries})
