# LedgerCore

A transaction-safe banking database and audit system built on Oracle Database and PL/SQL, with a Flask API and a React dashboard on top.

Course project for Database Systems (BCSE302L), VIT Vellore. This is an educational simulation that uses only fictional data. It is not a real banking service.

## What it shows

- A normalized schema (3NF) with primary keys, foreign keys, NOT NULL, CHECK and UNIQUE constraints
- All balance changes in one PL/SQL package (`LEDGER_PKG`). The API never updates a balance itself
- Atomic transfers: the debit, the credit, the ledger entries and the transaction rows either all happen or none happen
- Row locking with `SELECT ... FOR UPDATE`, with locks always taken in the same order so transfers cannot deadlock
- A double-entry style ledger (`ACCOUNT_ENTRIES`) and a reconciliation check proving balances match the ledger
- Audit triggers, and an append-only ledger that cannot be edited
- Rejected attempts logged with an autonomous transaction, so the log survives the rollback
- Explicit cursor and cursor FOR loop reports
- `EXPLAIN PLAN` before and after adding an index
- An automated two-session concurrency test

## Architecture

```
React (Vite)  ->  Flask REST API  ->  Oracle XE 21c
 dashboard        validation,          tables, constraints,
                  commit/rollback      LEDGER_PKG, triggers,
                                       cursors, views
```

The package procedures never commit. Each one sets a savepoint, rolls back to it if anything fails and re-raises the error. The caller owns the transaction: Flask commits when the call succeeds and rolls back when it fails.

## Database design

ER diagram (Chen notation): `docs/er_diagram.png`

| Table | Purpose |
|---|---|
| CUSTOMERS | Bank customers (email is unique) |
| ACCOUNTS | Accounts with type, balance and status (ACTIVE, FROZEN or CLOSED) |
| TRANSACTIONS | One row per operation (COMPLETED or REJECTED) |
| TRANSFER_DETAILS | Source and destination of each transfer (ISA subclass of TRANSACTION) |
| ACCOUNT_ENTRIES | Ledger: deposit = 1 CREDIT, withdrawal = 1 DEBIT, transfer = 1 DEBIT + 1 CREDIT |
| ACCOUNT_AUDIT | Old and new balance on every change, written by a trigger |
| TRANSACTION_LOG | COMPLETED, REJECTED and ERROR events |

There are two deliberate denormalizations:

- `ACCOUNTS.balance` could be calculated from the ledger, but it is stored so reads are fast and so there is a row to lock.
- `ACCOUNT_ENTRIES.balance_after` is stored so statements don't need a running total.

The `v_reconciliation` view proves that both stay correct.

### Business rules

| Rule | Where it is enforced |
|---|---|
| Amount > 0, at most 2 decimals | `ck_txn_amount` + `check_amount` in the package |
| No overdraft | `ck_accounts_balance` + the funds check while the row is locked |
| No self-transfer | `ck_td_not_self` + the package check |
| Only ACTIVE accounts can move money | Package (`check_active`) |
| Closing requires a zero balance, and a closed account is permanent | Package + `ck_accounts_closed` |
| Ledger and audit rows cannot be changed | Triggers `trg_entries_no_change` and `trg_audit_no_change` |

### Error codes

| Code | Meaning | HTTP |
|---|---|---|
| ORA-20001 | Invalid amount | 400 |
| ORA-20002 | Account or customer not found | 404 |
| ORA-20003 | Account not ACTIVE | 409 |
| ORA-20004 | Insufficient funds | 409 |
| ORA-20005 | Transfer to the same account | 400 |
| ORA-20006 | Invalid input | 400 |
| other | System error (logged as ERROR, details hidden) | 500 |

## Setup

### Prerequisites
- Oracle Database XE 21c, with the pluggable database `XEPDB1`
- SQLcl (`sql`) or SQL*Plus. SQL Developer also works if you run the scripts with F5
- Python 3.10+ and Node 18+

### 1. Database

```bash
# once, as SYSTEM: creates the LEDGERCORE user
sql system@localhost:1521/XEPDB1 @database/00_create_user.sql

# as LEDGERCORE, from the project root: builds everything and runs all tests
sql ledgercore@localhost:1521/XEPDB1 @database/run_all.sql
```

`run_all.sql` runs these scripts in order and saves the output to `docs/test_results/run_all_output.txt`:

| Order | Script | What it does |
|---|---|---|
| 1 | 01_schema.sql | Tables, keys, NOT NULL, defaults (drops old objects first) |
| 2 | 02_constraints_indexes.sql | CHECK, UNIQUE, indexes |
| 3 | 03_sample_data.sql | 5 customers, 7 accounts |
| 4 | 04_functions.sql | GET_ACCOUNT_BALANCE, GET_TRANSACTION_COUNT |
| 5 | 05_procedures.sql | Autonomous loggers, cursor reports, views |
| 6 | 06_packages.sql | LEDGER_PKG |
| 7 | 07_triggers.sql | Audit and append-only triggers |
| 8 | 07b_demo_activity.sql | Demo deposits, withdrawals and transfers through the package |
| 9 | 08_test_cases.sql | Tests T01 to T17 (PASS or FAIL computed from real data) |
| 10 | 08b_concurrency_test.sql | T18: two sessions withdrawing at the same time |
| 11 | 09_query_plan_tests.sql | 20,000 rows, then the plan before and after the index |

`08c_two_session_manual.sql` has steps for a live demo of the concurrency test in two windows.

Warning: `01_schema.sql` drops all tables, so re-running `run_all.sql` rebuilds the database from scratch.

### 2. Backend

```bash
cd backend
python -m venv venv
venv\Scripts\activate         # Windows   (source venv/bin/activate on Mac/Linux)
pip install -r requirements.txt
copy ..\.env.example .env     # then put your real password in backend/.env
python app.py                 # http://localhost:5000/api/health
python -m pytest              # unit tests (no DB needed)
```

### 3. Frontend

```bash
cd frontend
npm install
npm run dev                   # http://localhost:5173
```

## API

| Method | Path | Purpose |
|---|---|---|
| GET | /api/health | API and database check |
| GET, POST | /api/customers | List or create customers |
| GET, POST | /api/accounts | List or open accounts |
| GET | /api/accounts/{id} | One account, with its transaction count |
| PATCH | /api/accounts/{id}/status | ACTIVE, FROZEN or CLOSED |
| GET | /api/accounts/{id}/statement | Ledger entries for the account |
| POST | /api/transactions/deposit | `{account_id, amount, description}` |
| POST | /api/transactions/withdraw | `{account_id, amount, description}` |
| POST | /api/transactions/transfer | `{source_account_id, destination_account_id, amount, description}` |
| GET | /api/transactions | Recent transactions, including rejected ones |
| GET | /api/reports/summary, /monthly, /high-value, /reconciliation | Reports |
| GET | /api/audit, /api/logs | Audit trail and event log |

## Test results

Real outputs are saved in `docs/test_results/`. The test list:

| Test | Checks |
|---|---|
| T01, T02 | A deposit or withdrawal changes the balance by exactly the amount |
| T03 | A withdrawal over the balance is rejected and the balance is unchanged |
| T04 | A transfer debits and credits equal amounts and writes 2 entries |
| T05 | A transfer to a missing account causes no partial debit |
| T06 | Zero or negative amounts are rejected |
| T07 | A self-transfer is rejected |
| T08 | FROZEN and CLOSED accounts are rejected |
| T09 | A failure forced after the debit rolls back everything |
| T10 | The audit has one row per change, with the correct old and new values |
| T11 | Credits minus debits equals the balance, and the statement is consistent |
| T12 | Every account reconciles with its ledger |
| T13 | Rejections are logged as REJECTED and failures as ERROR, and both survive the rollback |
| T14 | A direct negative balance is blocked by the CHECK constraint |
| T15 | Ledger entries cannot be edited |
| T16 | GET_TRANSACTION_COUNT is correct |
| T17 | An account with money in it cannot be closed |
| T18 | Concurrent withdrawals: one succeeds, one is rejected, the final balance is correct |

## Repository layout

```
database/   SQL and PL/SQL scripts (run_all.sql runs everything)
backend/    Flask API (routes/, services/, tests/)
frontend/   React + Vite dashboard
docs/       ER diagram, test results
```
