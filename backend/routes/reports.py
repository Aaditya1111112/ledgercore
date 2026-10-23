from flask import Blueprint, jsonify, request

from services.db import query, query_one
from services.errors import ApiError
from .helpers import as_int

bp = Blueprint("reports", __name__)


@bp.get("/reports/summary")
def summary():
    return jsonify(query_one("""
        SELECT
          (SELECT COUNT(*) FROM customers)                                AS customers,
          (SELECT COUNT(*) FROM accounts)                                 AS accounts,
          (SELECT COUNT(*) FROM accounts WHERE status = 'ACTIVE')         AS active_accounts,
          (SELECT NVL(SUM(balance), 0) FROM accounts)                     AS total_balance,
          (SELECT COUNT(*) FROM transactions WHERE status = 'COMPLETED')  AS completed_transactions,
          (SELECT COUNT(*) FROM transactions WHERE status = 'REJECTED')   AS rejected_transactions,
          (SELECT COUNT(*) FROM v_reconciliation WHERE difference <> 0)   AS unreconciled_accounts
        FROM dual"""))


@bp.get("/reports/monthly")
def monthly():
    return jsonify(query("SELECT * FROM v_monthly_activity ORDER BY month DESC, transaction_type"))


@bp.get("/reports/high-value")
def high_value():
    try:
        threshold = float(request.args.get("threshold", 50000))
    except ValueError:
        raise ApiError("threshold must be a number")
    return jsonify(query(
        """SELECT t.transaction_id, t.transaction_type, t.amount, t.created_at, t.description,
                  LISTAGG(a.account_no || ' ' || e.entry_type, ', ')
                    WITHIN GROUP (ORDER BY e.entry_type DESC) AS accounts
           FROM transactions t
           JOIN account_entries e ON e.transaction_id = t.transaction_id
           JOIN accounts a ON a.account_id = e.account_id
           WHERE t.status = 'COMPLETED' AND t.amount >= :th
           GROUP BY t.transaction_id, t.transaction_type, t.amount, t.created_at, t.description
           ORDER BY t.amount DESC
           FETCH FIRST 100 ROWS ONLY""",
        {"th": threshold},
    ))


@bp.get("/reports/reconciliation")
def reconciliation():
    return jsonify(query("SELECT * FROM v_reconciliation ORDER BY ABS(difference) DESC, account_id"))


@bp.get("/audit")
def audit():
    account_id = request.args.get("account_id")
    sql = """SELECT au.audit_id, au.account_id, a.account_no, au.old_balance, au.new_balance,
                    au.new_balance - au.old_balance AS change, au.changed_by, au.changed_at
             FROM account_audit au JOIN accounts a ON a.account_id = au.account_id"""
    params = {}
    if account_id:
        sql += " WHERE au.account_id = :id"
        params["id"] = as_int(account_id, "account_id")
    sql += " ORDER BY au.audit_id DESC FETCH FIRST 200 ROWS ONLY"
    return jsonify(query(sql, params))


@bp.get("/logs")
def logs():
    return jsonify(query(
        """SELECT log_id, transaction_id, account_id, event_type, details, logged_at
           FROM transaction_log ORDER BY log_id DESC FETCH FIRST 200 ROWS ONLY"""))
