-- =====================================================================
-- 05_procedures.sql
-- 1. Failure logging procedures (AUTONOMOUS_TRANSACTION)
-- 2. Cursor-based report procedures (print with DBMS_OUTPUT)
-- 3. Reporting views used by the Flask API
--
-- The balance-changing procedures (CREATE_ACCOUNT, DEPOSIT_FUNDS,
-- WITHDRAW_FUNDS, TRANSFER_FUNDS) live in LEDGER_PKG (06_packages.sql)
-- so all business rules are in one place.
-- Run as: LEDGERCORE, after 04
-- =====================================================================

-- ---------------------------------------------------------------------
-- record_rejection
-- Saves a rejected attempt even though the main work is rolled back.
-- PRAGMA AUTONOMOUS_TRANSACTION means this procedure runs in its own
-- small, separate transaction and commits only its own rows.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE record_rejection (
  p_txn_type    IN VARCHAR2,
  p_amount      IN NUMBER,
  p_account_id  IN NUMBER,
  p_reason      IN VARCHAR2
)
IS
  PRAGMA AUTONOMOUS_TRANSACTION;
  v_txn_id      transactions.transaction_id%TYPE;
  v_account_id  accounts.account_id%TYPE;
  v_exists      NUMBER;
BEGIN
  -- Only link the account if it really exists (FK would fail otherwise)
  SELECT COUNT(*) INTO v_exists FROM accounts WHERE account_id = p_account_id;
  IF v_exists = 1 THEN
    v_account_id := p_account_id;
  END IF;

  -- Keep a REJECTED transaction row when the amount itself is valid.
  -- (A zero or negative amount cannot be stored because of ck_txn_amount,
  -- so for those we keep only the log row.)
  IF p_amount > 0 AND p_amount = ROUND(p_amount, 2) AND p_amount < 1e13 THEN
    INSERT INTO transactions (transaction_type, amount, status, description)
    VALUES (p_txn_type, p_amount, 'REJECTED', SUBSTR(p_reason, 1, 200))
    RETURNING transaction_id INTO v_txn_id;
  END IF;

  INSERT INTO transaction_log (transaction_id, account_id, event_type, details)
  VALUES (v_txn_id, v_account_id, 'REJECTED',
          SUBSTR(p_txn_type || ' on account ' || p_account_id || ': ' || p_reason, 1, 500));

  COMMIT;   -- commits ONLY the rows written inside this procedure
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;   -- logging must never hide the original error
END record_rejection;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- log_system_error
-- Same idea, for unexpected database or system errors (not business
-- rule rejections). No transaction row is kept, only a log row.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE log_system_error (
  p_txn_type    IN VARCHAR2,
  p_account_id  IN NUMBER,
  p_message     IN VARCHAR2
)
IS
  PRAGMA AUTONOMOUS_TRANSACTION;
  v_account_id  accounts.account_id%TYPE;
  v_exists      NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM accounts WHERE account_id = p_account_id;
  IF v_exists = 1 THEN
    v_account_id := p_account_id;
  END IF;

  INSERT INTO transaction_log (account_id, event_type, details)
  VALUES (v_account_id, 'ERROR',
          SUBSTR(p_txn_type || ' on account ' || p_account_id || ': ' || p_message, 1, 500));
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
END log_system_error;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- print_account_statement  (EXPLICIT CURSOR: OPEN / FETCH / CLOSE)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE print_account_statement (
  p_account_id IN NUMBER,
  p_from       IN DATE DEFAULT NULL,
  p_to         IN DATE DEFAULT NULL
)
IS
  CURSOR c_entries IS
    SELECT e.created_at, t.transaction_type, e.entry_type, e.amount,
           e.balance_after, t.description
    FROM   account_entries e
    JOIN   transactions t ON t.transaction_id = e.transaction_id
    WHERE  e.account_id = p_account_id
    AND    (p_from IS NULL OR e.created_at >= p_from)
    AND    (p_to   IS NULL OR e.created_at <  p_to + 1)
    ORDER  BY e.entry_id;

  r_entry     c_entries%ROWTYPE;
  v_acc_no    accounts.account_no%TYPE;
  v_name      customers.full_name%TYPE;
  v_balance   accounts.balance%TYPE;
  v_status    accounts.status%TYPE;
BEGIN
  SELECT a.account_no, c.full_name, a.balance, a.status
  INTO   v_acc_no, v_name, v_balance, v_status
  FROM   accounts a JOIN customers c ON c.customer_id = a.customer_id
  WHERE  a.account_id = p_account_id;

  DBMS_OUTPUT.PUT_LINE('==================================================================');
  DBMS_OUTPUT.PUT_LINE('STATEMENT  ' || v_acc_no || '  ' || v_name || '  (' || v_status || ')');
  DBMS_OUTPUT.PUT_LINE('==================================================================');
  DBMS_OUTPUT.PUT_LINE(RPAD('Date', 20) || RPAD('Type', 12) || RPAD('Dr/Cr', 8)
                       || LPAD('Amount', 14) || LPAD('Balance', 14));

  OPEN c_entries;
  LOOP
    FETCH c_entries INTO r_entry;
    EXIT WHEN c_entries%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(
      RPAD(TO_CHAR(r_entry.created_at, 'DD-MON-YY HH24:MI'), 20) ||
      RPAD(r_entry.transaction_type, 12) ||
      RPAD(r_entry.entry_type, 8) ||
      LPAD(TO_CHAR(r_entry.amount, 'FM999,999,999,990.00'), 14) ||
      LPAD(TO_CHAR(r_entry.balance_after, 'FM999,999,999,990.00'), 14));
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE(c_entries%ROWCOUNT || ' entries. Current balance: '
                       || TO_CHAR(v_balance, 'FM999,999,999,990.00'));
  CLOSE c_entries;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20002, 'Account ' || p_account_id || ' does not exist');
END print_account_statement;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- print_high_value_transactions  (CURSOR FOR LOOP)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE print_high_value_transactions (
  p_threshold IN NUMBER DEFAULT 50000
)
IS
  v_count PLS_INTEGER := 0;
BEGIN
  DBMS_OUTPUT.PUT_LINE('HIGH-VALUE COMPLETED TRANSACTIONS (>= '
                       || TO_CHAR(p_threshold, 'FM999,999,999,990.00') || ')');
  FOR r IN (
    SELECT t.transaction_id, t.transaction_type, t.amount, t.created_at,
           LISTAGG(a.account_no || ' ' || e.entry_type, ', ')
             WITHIN GROUP (ORDER BY e.entry_type DESC) AS accounts_involved
    FROM   transactions t
    JOIN   account_entries e ON e.transaction_id = t.transaction_id
    JOIN   accounts a        ON a.account_id = e.account_id
    WHERE  t.status = 'COMPLETED'
    AND    t.amount >= p_threshold
    GROUP  BY t.transaction_id, t.transaction_type, t.amount, t.created_at
    ORDER  BY t.amount DESC
  ) LOOP
    v_count := v_count + 1;
    DBMS_OUTPUT.PUT_LINE('#' || r.transaction_id || '  ' || RPAD(r.transaction_type, 11)
      || LPAD(TO_CHAR(r.amount, 'FM999,999,999,990.00'), 14) || '  '
      || TO_CHAR(r.created_at, 'DD-MON-YY HH24:MI') || '  ' || r.accounts_involved);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(v_count || ' transaction(s) found');
END print_high_value_transactions;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- print_monthly_activity  (CURSOR FOR LOOP with GROUP BY)
-- Pass an account_id for one account, or NULL for the whole bank.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE print_monthly_activity (
  p_account_id IN NUMBER DEFAULT NULL
)
IS
BEGIN
  DBMS_OUTPUT.PUT_LINE('MONTHLY ACTIVITY ' ||
    CASE WHEN p_account_id IS NULL THEN '(all accounts)' ELSE '(account ' || p_account_id || ')' END);
  DBMS_OUTPUT.PUT_LINE(RPAD('Month', 10) || LPAD('Entries', 9)
    || LPAD('Credits', 16) || LPAD('Debits', 16) || LPAD('Net', 16));
  FOR r IN (
    SELECT TRUNC(created_at, 'MM') AS month_start,
           COUNT(*) AS entry_count,
           SUM(CASE WHEN entry_type = 'CREDIT' THEN amount ELSE 0 END) AS credits,
           SUM(CASE WHEN entry_type = 'DEBIT'  THEN amount ELSE 0 END) AS debits
    FROM   account_entries
    WHERE  p_account_id IS NULL OR account_id = p_account_id
    GROUP  BY TRUNC(created_at, 'MM')
    ORDER  BY month_start
  ) LOOP
    DBMS_OUTPUT.PUT_LINE(RPAD(TO_CHAR(r.month_start, 'MON-YYYY'), 10)
      || LPAD(r.entry_count, 9)
      || LPAD(TO_CHAR(r.credits, 'FM999,999,999,990.00'), 16)
      || LPAD(TO_CHAR(r.debits,  'FM999,999,999,990.00'), 16)
      || LPAD(TO_CHAR(r.credits - r.debits, 'FM999,999,999,990.00'), 16));
  END LOOP;
END print_monthly_activity;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- VIEWS (read-only shortcuts used by the API and tests)
-- ---------------------------------------------------------------------

-- Accounts with owner name
CREATE OR REPLACE VIEW v_account_overview AS
SELECT a.account_id, a.account_no, a.account_type, a.balance, a.status,
       a.opened_at, a.closed_at, c.customer_id, c.full_name, c.email
FROM   accounts a
JOIN   customers c ON c.customer_id = a.customer_id;

-- Completed activity per month and type
CREATE OR REPLACE VIEW v_monthly_activity AS
SELECT TO_CHAR(TRUNC(created_at, 'MM'), 'YYYY-MM') AS month,
       transaction_type,
       COUNT(*)    AS transaction_count,
       SUM(amount) AS total_amount
FROM   transactions
WHERE  status = 'COMPLETED'
GROUP  BY TRUNC(created_at, 'MM'), transaction_type;

-- Stored balance vs balance rebuilt from the ledger.
-- difference must be 0 for every account.
CREATE OR REPLACE VIEW v_reconciliation AS
SELECT a.account_id, a.account_no, a.balance AS stored_balance,
       NVL(SUM(CASE e.entry_type WHEN 'CREDIT' THEN e.amount ELSE -e.amount END), 0)
         AS ledger_balance,
       a.balance - NVL(SUM(CASE e.entry_type WHEN 'CREDIT' THEN e.amount ELSE -e.amount END), 0)
         AS difference
FROM   accounts a
LEFT JOIN account_entries e ON e.account_id = a.account_id
GROUP  BY a.account_id, a.account_no, a.balance;

PROMPT 05_procedures.sql done
