-- =====================================================================
-- 08c_two_session_manual.sql
-- Manual version of the concurrency test, good for a live demo or a
-- screenshot. Open TWO SQL Developer worksheets (or two terminals),
-- both connected as LEDGERCORE. Run the steps in the order shown.
-- =====================================================================

-- STEP 0 (window 1): make a fresh account with 1000.00 and note its id
SET SERVEROUTPUT ON
DECLARE c NUMBER; a NUMBER; n VARCHAR2(12); t NUMBER;
BEGIN
  ledger_pkg.create_customer('Manual Demo ' || TO_CHAR(SYSTIMESTAMP,'HH24MISS'),
                             'manual_' || TO_CHAR(SYSTIMESTAMP,'YYYYMMDDHH24MISSFF3') || '@ledgercore.test',
                             NULL, c);
  ledger_pkg.create_account(c, 'SAVINGS', a, n);
  ledger_pkg.deposit_funds(a, 1000, t, 'Manual demo');
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Use account_id = ' || a);
END;
/

-- STEP 1 (window 1): withdraw 700 but DO NOT COMMIT yet.
--   Replace 123 with your account_id.
-- VARIABLE t NUMBER
-- EXEC ledger_pkg.withdraw_funds(123, 700, :t, 'Session 1');
-- SELECT balance FROM accounts WHERE account_id = 123;   -- shows 300 here only

-- STEP 2 (window 2): try to withdraw 700 from the same account.
-- VARIABLE t NUMBER
-- EXEC ledger_pkg.withdraw_funds(123, 700, :t, 'Session 2');
--   -> This HANGS. It is waiting for window 1's row lock (FOR UPDATE).
--      Take a screenshot now.

-- STEP 3 (window 1): COMMIT;
--   -> Window 2 wakes up immediately, reads the NEW balance 300.00 and
--      fails with ORA-20004 Insufficient funds.

-- STEP 4 (either window): check the result
-- SELECT balance FROM accounts WHERE account_id = 123;        -- 300.00
-- SELECT event_type, details FROM transaction_log
-- WHERE account_id = 123 ORDER BY log_id;                     -- 1 COMPLETED + 1 REJECTED
