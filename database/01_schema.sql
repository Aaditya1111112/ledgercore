-- =====================================================================
-- 01_schema.sql
-- Tables, primary keys, foreign keys, NOT NULL and defaults.
-- CHECK and UNIQUE constraints and indexes are added in 02.
-- Safe to re-run: it drops the old objects first.
-- Run as: LEDGERCORE
-- =====================================================================

-- Drop old tables (children first) so the script can be re-run
BEGIN
  FOR t IN (
    SELECT table_name FROM user_tables
    WHERE table_name IN ('TRANSACTION_LOG','ACCOUNT_AUDIT','ACCOUNT_ENTRIES',
                         'TRANSFER_DETAILS','TRANSACTIONS','ACCOUNTS','CUSTOMERS')
  ) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences WHERE sequence_name = 'ACCOUNT_NO_SEQ') LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
  END LOOP;
END;
/

-- Used to build the visible account number, e.g. LC0000000001
CREATE SEQUENCE account_no_seq START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---------------------------------------------------------------------
-- CUSTOMERS: one row per bank customer
-- ---------------------------------------------------------------------
CREATE TABLE customers (
  customer_id   NUMBER GENERATED ALWAYS AS IDENTITY,
  full_name     VARCHAR2(100)  NOT NULL,
  email         VARCHAR2(150)  NOT NULL,
  phone         VARCHAR2(15),
  created_at    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_customers PRIMARY KEY (customer_id)
);

-- ---------------------------------------------------------------------
-- ACCOUNTS: each account belongs to exactly one customer.
-- balance is stored on purpose (fast reads and row locking); it must
-- always equal credits minus debits in ACCOUNT_ENTRIES.
-- ---------------------------------------------------------------------
CREATE TABLE accounts (
  account_id    NUMBER GENERATED ALWAYS AS IDENTITY,
  account_no    VARCHAR2(12)   NOT NULL,
  customer_id   NUMBER         NOT NULL,
  account_type  VARCHAR2(10)   NOT NULL,
  balance       NUMBER(15,2)   DEFAULT 0 NOT NULL,
  status        VARCHAR2(10)   DEFAULT 'ACTIVE' NOT NULL,
  opened_at     TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  closed_at     TIMESTAMP,
  CONSTRAINT pk_accounts PRIMARY KEY (account_id),
  CONSTRAINT fk_accounts_customer FOREIGN KEY (customer_id)
    REFERENCES customers (customer_id)
);

-- ---------------------------------------------------------------------
-- TRANSACTIONS: one row per business operation (deposit, withdrawal,
-- transfer). Rejected attempts are kept with status REJECTED.
-- ---------------------------------------------------------------------
CREATE TABLE transactions (
  transaction_id    NUMBER GENERATED ALWAYS AS IDENTITY,
  transaction_type  VARCHAR2(10)   NOT NULL,
  amount            NUMBER(15,2)   NOT NULL,
  status            VARCHAR2(10)   NOT NULL,
  description       VARCHAR2(200),
  created_at        TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_transactions PRIMARY KEY (transaction_id)
);

-- ---------------------------------------------------------------------
-- TRANSFER_DETAILS: extra facts for transfers only (ISA subclass of
-- TRANSACTION in the ER diagram). Shares the transaction's key.
-- ---------------------------------------------------------------------
CREATE TABLE transfer_details (
  transaction_id          NUMBER  NOT NULL,
  source_account_id       NUMBER  NOT NULL,
  destination_account_id  NUMBER  NOT NULL,
  CONSTRAINT pk_transfer_details PRIMARY KEY (transaction_id),
  CONSTRAINT fk_td_transaction FOREIGN KEY (transaction_id)
    REFERENCES transactions (transaction_id),
  CONSTRAINT fk_td_source FOREIGN KEY (source_account_id)
    REFERENCES accounts (account_id),
  CONSTRAINT fk_td_destination FOREIGN KEY (destination_account_id)
    REFERENCES accounts (account_id)
);

-- ---------------------------------------------------------------------
-- ACCOUNT_ENTRIES: the ledger. Every money movement writes entries:
-- deposit = 1 CREDIT, withdrawal = 1 DEBIT, transfer = 1 DEBIT + 1 CREDIT
-- ---------------------------------------------------------------------
CREATE TABLE account_entries (
  entry_id        NUMBER GENERATED ALWAYS AS IDENTITY,
  transaction_id  NUMBER         NOT NULL,
  account_id      NUMBER         NOT NULL,
  entry_type      VARCHAR2(6)    NOT NULL,
  amount          NUMBER(15,2)   NOT NULL,
  balance_after   NUMBER(15,2)   NOT NULL,
  created_at      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_account_entries PRIMARY KEY (entry_id),
  CONSTRAINT fk_entries_transaction FOREIGN KEY (transaction_id)
    REFERENCES transactions (transaction_id),
  CONSTRAINT fk_entries_account FOREIGN KEY (account_id)
    REFERENCES accounts (account_id)
);

-- ---------------------------------------------------------------------
-- ACCOUNT_AUDIT: filled only by trigger trg_accounts_balance_audit
-- ---------------------------------------------------------------------
CREATE TABLE account_audit (
  audit_id      NUMBER GENERATED ALWAYS AS IDENTITY,
  account_id    NUMBER         NOT NULL,
  old_balance   NUMBER(15,2),
  new_balance   NUMBER(15,2),
  changed_by    VARCHAR2(128)  DEFAULT USER NOT NULL,
  changed_at    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_account_audit PRIMARY KEY (audit_id),
  CONSTRAINT fk_audit_account FOREIGN KEY (account_id)
    REFERENCES accounts (account_id)
);

-- ---------------------------------------------------------------------
-- TRANSACTION_LOG: lifecycle and failure events. Both FKs are nullable
-- because a rejected attempt may have no transaction row, or may name
-- an account that does not exist.
-- ---------------------------------------------------------------------
CREATE TABLE transaction_log (
  log_id          NUMBER GENERATED ALWAYS AS IDENTITY,
  transaction_id  NUMBER,
  account_id      NUMBER,
  event_type      VARCHAR2(20)   NOT NULL,
  details         VARCHAR2(500),
  logged_at       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_transaction_log PRIMARY KEY (log_id),
  CONSTRAINT fk_log_transaction FOREIGN KEY (transaction_id)
    REFERENCES transactions (transaction_id),
  CONSTRAINT fk_log_account FOREIGN KEY (account_id)
    REFERENCES accounts (account_id)
);

PROMPT 01_schema.sql done: 7 tables and 1 sequence created
