# LedgerCore - project context

DBMS course project (BCSE302L, VIT). A transaction-safe banking database and audit system.
Fictional demo data only. The database is the source of truth.

## Stack
- Oracle Database XE 21c, SQL and PL/SQL (do not switch to any other database)
- Later: Python Flask (python-oracledb) backend, React frontend
- Secrets only in .env (never commit it), provide .env.example

## Locked design decisions
- IDs use GENERATED ALWAYS AS IDENTITY
- Money is NUMBER(15,2), timestamps are TIMESTAMP DEFAULT SYSTIMESTAMP
- Account types: SAVINGS, CURRENT
- Account status: ACTIVE, FROZEN, CLOSED. FROZEN and CLOSED block deposits, withdrawals and transfers. closed_at is filled only when CLOSED
- No overdrafts: CHECK (balance >= 0) plus a PL/SQL funds check
- ACCOUNT_ENTRIES is a core table: deposit = 1 CREDIT entry, withdrawal = 1 DEBIT entry, transfer = 1 DEBIT + 1 CREDIT
- TRANSFER_DETAILS has CHECK (source_account_id <> destination_account_id)
- Package procedures never COMMIT. Each sets a SAVEPOINT, on error does ROLLBACK TO SAVEPOINT and re-raises. The caller commits
- Rejected attempts are logged through an AUTONOMOUS_TRANSACTION logging procedure so the log survives rollback
- Triggers are only for auditing (ACCOUNT_AUDIT old/new balance), never for changing balances
- Transfers lock both accounts with SELECT ... FOR UPDATE in a fixed order (lower account_id first)

## Tables
CUSTOMERS(customer_id PK, full_name NN, email NN UNIQUE, phone, created_at NN)
ACCOUNTS(account_id PK, account_no NN UNIQUE VARCHAR2(12), customer_id FK NN, account_type, balance NN default 0, status default ACTIVE, opened_at NN, closed_at)
TRANSACTIONS(transaction_id PK, transaction_type DEPOSIT/WITHDRAWAL/TRANSFER, amount > 0, status COMPLETED/REJECTED, description, created_at NN)
TRANSFER_DETAILS(transaction_id PK FK, source_account_id FK NN, destination_account_id FK NN)
ACCOUNT_ENTRIES(entry_id PK, transaction_id FK NN, account_id FK NN, entry_type DEBIT/CREDIT, amount > 0, balance_after NN, created_at NN)
ACCOUNT_AUDIT(audit_id PK, account_id FK NN, old_balance, new_balance, changed_by default USER, changed_at NN)
TRANSACTION_LOG(log_id PK, transaction_id FK nullable, account_id FK nullable, event_type STARTED/COMPLETED/REJECTED/ERROR, details VARCHAR2(500), logged_at NN)

ER diagram (Chen notation, course style): docs/er_diagram.png

## Repo layout and status
All code is already written. database/run_all.sql runs 01 to 09 in order (see README.md).
backend/ is Flask (python app.py), frontend/ is Vite React (npm run dev).
The SQL has NOT been run against a real database yet. First job: run it, fix errors, save real output.

## How to work with me
- Deadline is tight: fix errors directly, but tell me in plain words what you changed and why
- Do not change the locked design decisions above without asking me
- Explain code in simple, plain language. I have to defend all of it in a viva
- Never say a test passed unless you actually ran it and saw the output
- Give execution order and prerequisites for every script
