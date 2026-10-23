-- =====================================================================
-- 02_constraints_indexes.sql
-- Domain rules (CHECK), uniqueness (UNIQUE) and indexes.
-- Every constraint is named so error messages say which rule failed.
-- Run as: LEDGERCORE, after 01_schema.sql
-- =====================================================================

-- CUSTOMERS ------------------------------------------------------------
ALTER TABLE customers ADD CONSTRAINT uq_customers_email UNIQUE (email);
ALTER TABLE customers ADD CONSTRAINT ck_customers_email
  CHECK (email LIKE '%_@_%._%');

-- ACCOUNTS -------------------------------------------------------------
ALTER TABLE accounts ADD CONSTRAINT uq_accounts_no UNIQUE (account_no);
ALTER TABLE accounts ADD CONSTRAINT ck_accounts_type
  CHECK (account_type IN ('SAVINGS', 'CURRENT'));
ALTER TABLE accounts ADD CONSTRAINT ck_accounts_status
  CHECK (status IN ('ACTIVE', 'FROZEN', 'CLOSED'));
-- No overdrafts, enforced by the database itself
ALTER TABLE accounts ADD CONSTRAINT ck_accounts_balance
  CHECK (balance >= 0);
-- closed_at is filled if and only if the account is CLOSED
ALTER TABLE accounts ADD CONSTRAINT ck_accounts_closed
  CHECK ( (status = 'CLOSED' AND closed_at IS NOT NULL)
       OR (status <> 'CLOSED' AND closed_at IS NULL) );

-- TRANSACTIONS ---------------------------------------------------------
ALTER TABLE transactions ADD CONSTRAINT ck_txn_type
  CHECK (transaction_type IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER'));
ALTER TABLE transactions ADD CONSTRAINT ck_txn_amount
  CHECK (amount > 0);
ALTER TABLE transactions ADD CONSTRAINT ck_txn_status
  CHECK (status IN ('COMPLETED', 'REJECTED'));

-- TRANSFER_DETAILS -----------------------------------------------------
ALTER TABLE transfer_details ADD CONSTRAINT ck_td_not_self
  CHECK (source_account_id <> destination_account_id);

-- ACCOUNT_ENTRIES ------------------------------------------------------
ALTER TABLE account_entries ADD CONSTRAINT ck_entry_type
  CHECK (entry_type IN ('DEBIT', 'CREDIT'));
ALTER TABLE account_entries ADD CONSTRAINT ck_entry_amount
  CHECK (amount > 0);
ALTER TABLE account_entries ADD CONSTRAINT ck_entry_balance_after
  CHECK (balance_after >= 0);
-- One transaction touches an account at most once. This unique
-- constraint also gives us an index that starts with transaction_id.
ALTER TABLE account_entries ADD CONSTRAINT uq_entries_txn_account
  UNIQUE (transaction_id, account_id);

-- TRANSACTION_LOG ------------------------------------------------------
ALTER TABLE transaction_log ADD CONSTRAINT ck_log_event
  CHECK (event_type IN ('STARTED', 'COMPLETED', 'REJECTED', 'ERROR'));

-- INDEXES --------------------------------------------------------------
-- Oracle does not index foreign keys automatically. We index the ones
-- we join or filter on.
CREATE INDEX idx_accounts_customer ON accounts (customer_id);
CREATE INDEX idx_td_source         ON transfer_details (source_account_id);
CREATE INDEX idx_td_destination    ON transfer_details (destination_account_id);
CREATE INDEX idx_audit_account     ON account_audit (account_id, changed_at);
CREATE INDEX idx_log_transaction   ON transaction_log (transaction_id);
CREATE INDEX idx_log_account       ON transaction_log (account_id);
CREATE INDEX idx_txn_created       ON transactions (created_at);

-- NOTE: the index on account_entries(account_id, created_at), used by
-- account statements, is created in 09_query_plan_tests.sql so we can
-- compare the execution plan before and after it exists.

PROMPT 02_constraints_indexes.sql done
