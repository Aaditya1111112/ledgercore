-- =====================================================================
-- 07_triggers.sql
-- Triggers are used ONLY for auditing and protecting history.
-- They never change balances (that logic stays in LEDGER_PKG).
-- Run as: LEDGERCORE, after 06
-- =====================================================================

-- 1. Balance audit: every time a balance changes, save old and new value.
--    Fires for package updates AND for any direct UPDATE, so nobody can
--    change a balance without leaving a trace.
CREATE OR REPLACE TRIGGER trg_accounts_balance_audit
AFTER UPDATE OF balance ON accounts
FOR EACH ROW
WHEN (OLD.balance <> NEW.balance)
BEGIN
  INSERT INTO account_audit (account_id, old_balance, new_balance)
  VALUES (:NEW.account_id, :OLD.balance, :NEW.balance);
END;
/
SHOW ERRORS

-- 2. The ledger is append-only: entries can never be edited or deleted.
--    A mistake is fixed with a new, opposite transaction, like real banks do.
CREATE OR REPLACE TRIGGER trg_entries_no_change
BEFORE UPDATE OR DELETE ON account_entries
BEGIN
  RAISE_APPLICATION_ERROR(-20010,
    'Ledger entries are permanent and cannot be updated or deleted');
END;
/
SHOW ERRORS

-- 3. Same protection for the audit trail itself.
CREATE OR REPLACE TRIGGER trg_audit_no_change
BEFORE UPDATE OR DELETE ON account_audit
BEGIN
  RAISE_APPLICATION_ERROR(-20011,
    'Audit records are permanent and cannot be updated or deleted');
END;
/
SHOW ERRORS

PROMPT 07_triggers.sql done
