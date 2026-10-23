"""Calls into the LEDGER_PKG PL/SQL package.

Python does NOT re-implement any banking rule. It only:
  1. calls the package procedure,
  2. COMMITs if it worked, ROLLBACKs if it raised.
The package never commits itself, so this file is the transaction owner.
"""
from decimal import Decimal

import oracledb

from .db import get_pool


def _call(proc_name, in_args, out_types):
    """Call a package procedure with IN args followed by OUT args.

    Returns the OUT values as a list. Commits on success, rolls back on error.
    """
    with get_pool().acquire() as conn:
        cur = conn.cursor()
        out_vars = [cur.var(t) for t in out_types]
        try:
            cur.callproc(proc_name, list(in_args) + out_vars)
            conn.commit()
        except oracledb.DatabaseError:
            conn.rollback()
            raise
        return [v.getvalue() for v in out_vars]


def _money(value):
    # Decimal keeps exact cents (a float like 0.1 + 0.2 would not)
    return Decimal(str(value))


def create_customer(full_name, email, phone):
    (customer_id,) = _call("ledger_pkg.create_customer", [full_name, email, phone], [int])
    return customer_id


def create_account(customer_id, account_type):
    account_id, account_no = _call(
        "ledger_pkg.create_account", [customer_id, account_type], [int, str]
    )
    return account_id, account_no


def _money_call(proc_name, in_args, description):
    """deposit/withdraw/transfer all end with (OUT transaction_id, IN description)."""
    with get_pool().acquire() as conn:
        cur = conn.cursor()
        txn_id = cur.var(int)
        try:
            cur.callproc(proc_name, list(in_args) + [txn_id, description])
            conn.commit()
        except oracledb.DatabaseError:
            conn.rollback()
            raise
        return txn_id.getvalue()


def deposit(account_id, amount, description=None):
    return _money_call("ledger_pkg.deposit_funds", [account_id, _money(amount)], description)


def withdraw(account_id, amount, description=None):
    return _money_call("ledger_pkg.withdraw_funds", [account_id, _money(amount)], description)


def transfer(source_id, destination_id, amount, description=None):
    return _money_call(
        "ledger_pkg.transfer_funds", [source_id, destination_id, _money(amount)], description
    )


def set_status(account_id, status):
    _call("ledger_pkg.set_account_status", [account_id, status], [])
