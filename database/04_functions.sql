-- =====================================================================
-- 04_functions.sql
-- Read-only helper functions.
-- Run as: LEDGERCORE, after 03
-- =====================================================================

-- Returns the current balance. Raises -20002 if the account is missing.
CREATE OR REPLACE FUNCTION get_account_balance (
  p_account_id IN accounts.account_id%TYPE
) RETURN NUMBER
IS
  v_balance accounts.balance%TYPE;
BEGIN
  SELECT balance INTO v_balance
  FROM accounts
  WHERE account_id = p_account_id;

  RETURN v_balance;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20002, 'Account ' || p_account_id || ' does not exist');
END get_account_balance;
/
SHOW ERRORS

-- Number of COMPLETED transactions that moved money in or out of the
-- account. Counted from the ledger, so rejected attempts are not counted.
-- This is the derived attribute transaction_count in the ER diagram.
CREATE OR REPLACE FUNCTION get_transaction_count (
  p_account_id IN accounts.account_id%TYPE
) RETURN NUMBER
IS
  v_exists NUMBER;
  v_count  NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM accounts WHERE account_id = p_account_id;
  IF v_exists = 0 THEN
    RAISE_APPLICATION_ERROR(-20002, 'Account ' || p_account_id || ' does not exist');
  END IF;

  SELECT COUNT(DISTINCT transaction_id) INTO v_count
  FROM account_entries
  WHERE account_id = p_account_id;

  RETURN v_count;
END get_transaction_count;
/
SHOW ERRORS

PROMPT 04_functions.sql done
