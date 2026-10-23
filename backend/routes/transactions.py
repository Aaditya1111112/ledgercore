from flask import Blueprint, jsonify, request

from services import ledger_service
from services.db import query
from .helpers import as_amount, as_int, body, require

bp = Blueprint("transactions", __name__)


@bp.post("/transactions/deposit")
def deposit():
    data = body()
    require(data, "account_id", "amount")
    txn_id = ledger_service.deposit(
        as_int(data["account_id"], "account_id"), as_amount(data["amount"]), data.get("description")
    )
    return jsonify({"transaction_id": txn_id, "status": "COMPLETED"}), 201


@bp.post("/transactions/withdraw")
def withdraw():
    data = body()
    require(data, "account_id", "amount")
    txn_id = ledger_service.withdraw(
        as_int(data["account_id"], "account_id"), as_amount(data["amount"]), data.get("description")
    )
    return jsonify({"transaction_id": txn_id, "status": "COMPLETED"}), 201


@bp.post("/transactions/transfer")
def transfer():
    data = body()
    require(data, "source_account_id", "destination_account_id", "amount")
    txn_id = ledger_service.transfer(
        as_int(data["source_account_id"], "source_account_id"),
        as_int(data["destination_account_id"], "destination_account_id"),
        as_amount(data["amount"]),
        data.get("description"),
    )
    return jsonify({"transaction_id": txn_id, "status": "COMPLETED"}), 201


@bp.get("/transactions")
def recent():
    limit = min(as_int(request.args.get("limit", 50), "limit"), 500)
    return jsonify(query(
        """SELECT t.transaction_id, t.transaction_type, t.amount, t.status, t.description,
                  t.created_at,
                  (SELECT LISTAGG(a.account_no || ' ' || e.entry_type, ', ')
                          WITHIN GROUP (ORDER BY e.entry_type DESC)
                   FROM account_entries e JOIN accounts a ON a.account_id = e.account_id
                   WHERE e.transaction_id = t.transaction_id) AS accounts
           FROM transactions t
           ORDER BY t.transaction_id DESC
           FETCH FIRST :lim ROWS ONLY""",
        {"lim": limit},
    ))
