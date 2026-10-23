-- =====================================================================
-- 09_query_plan_tests.sql
-- Before/after comparison of an execution plan when we add an index.
--
-- Query under test: an account statement (entries of ONE account in the
-- last 30 days). This is the most common read in the app.
--
-- Steps:
--   1. Generate about 20,000 ledger entries over 50 accounts (through
--      the package, so data stays consistent). Skipped if already done.
--   2. Make sure the index does NOT exist, gather stats, EXPLAIN PLAN.
--   3. Create index on account_entries(account_id, created_at), gather
--      stats, EXPLAIN PLAN again.
--   4. A second query that reads almost all rows, to show an index does
--      not always help.
-- Run as: LEDGERCORE. Step 1 takes around a minute the first time.
-- =====================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 200
SET VERIFY OFF
SET TIMING ON

-- ---------- 1. Bulk data ----------
DECLARE
  TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  v_ids    t_ids;
  v_cust   NUMBER;
  v_no     VARCHAR2(12);
  v_txn    NUMBER;
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM customers WHERE email = 'perf.test@ledgercore.test';
  IF v_exists > 0 THEN
    DBMS_OUTPUT.PUT_LINE('Performance data already exists, skipping generation');
    RETURN;
  END IF;

  ledger_pkg.create_customer('Performance Test Customer', 'perf.test@ledgercore.test', NULL, v_cust);
  FOR i IN 1 .. 50 LOOP
    ledger_pkg.create_account(v_cust, 'SAVINGS', v_ids(i), v_no);
  END LOOP;
  COMMIT;

  FOR i IN 1 .. 20000 LOOP
    ledger_pkg.deposit_funds(v_ids(MOD(i, 50) + 1),
                             ROUND(DBMS_RANDOM.VALUE(1, 5000), 2), v_txn, 'perf data');
    IF MOD(i, 1000) = 0 THEN
      COMMIT;
    END IF;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Generated 20,000 deposits over 50 accounts');
END;
/

-- Pick one performance account to query
COLUMN acc_id NEW_VALUE acc_id NOPRINT
SELECT MIN(a.account_id) AS acc_id
FROM   accounts a JOIN customers c ON c.customer_id = a.customer_id
WHERE  c.email = 'perf.test@ledgercore.test';

SELECT COUNT(*) AS total_entries FROM account_entries;
SELECT COUNT(*) AS entries_for_this_account FROM account_entries WHERE account_id = &acc_id;

-- ---------- 2. BEFORE: no index on account_entries(account_id, created_at) ----------
BEGIN
  EXECUTE IMMEDIATE 'DROP INDEX idx_entries_account_time';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE <> -1418 THEN RAISE; END IF;   -- -1418 = index does not exist
END;
/
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'ACCOUNT_ENTRIES', cascade => TRUE)

PROMPT
PROMPT ===== PLAN BEFORE INDEX =====
EXPLAIN PLAN SET STATEMENT_ID = 'BEFORE' FOR
  SELECT entry_id, created_at, entry_type, amount, balance_after
  FROM   account_entries
  WHERE  account_id = &acc_id
  AND    created_at >= SYSTIMESTAMP - INTERVAL '30' DAY
  ORDER  BY created_at;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'BEFORE', 'TYPICAL'));

-- Run it once for real (see the elapsed time printed by SET TIMING ON)
SELECT COUNT(*) AS rows_returned FROM (
  SELECT entry_id FROM account_entries
  WHERE account_id = &acc_id AND created_at >= SYSTIMESTAMP - INTERVAL '30' DAY);

-- ---------- 3. AFTER: create the index ----------
CREATE INDEX idx_entries_account_time ON account_entries (account_id, created_at);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'ACCOUNT_ENTRIES', cascade => TRUE)

PROMPT
PROMPT ===== PLAN AFTER INDEX =====
EXPLAIN PLAN SET STATEMENT_ID = 'AFTER' FOR
  SELECT entry_id, created_at, entry_type, amount, balance_after
  FROM   account_entries
  WHERE  account_id = &acc_id
  AND    created_at >= SYSTIMESTAMP - INTERVAL '30' DAY
  ORDER  BY created_at;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'AFTER', 'TYPICAL'));

SELECT COUNT(*) AS rows_returned FROM (
  SELECT entry_id FROM account_entries
  WHERE account_id = &acc_id AND created_at >= SYSTIMESTAMP - INTERVAL '30' DAY);

-- ---------- 4. When an index does NOT help ----------
-- This reads nearly every row (all entries from the last 30 days), so
-- a full table scan is cheaper than jumping through the index.
PROMPT
PROMPT ===== LOW-SELECTIVITY QUERY (index not useful) =====
EXPLAIN PLAN SET STATEMENT_ID = 'LOWSEL' FOR
  SELECT SUM(amount) FROM account_entries
  WHERE  created_at >= SYSTIMESTAMP - INTERVAL '30' DAY;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'LOWSEL', 'TYPICAL'));

-- Cost of the index: extra storage, and every insert must also update it
SELECT segment_name, ROUND(bytes / 1024) AS size_kb
FROM   user_segments
WHERE  segment_name IN ('ACCOUNT_ENTRIES', 'IDX_ENTRIES_ACCOUNT_TIME');

SET TIMING OFF
