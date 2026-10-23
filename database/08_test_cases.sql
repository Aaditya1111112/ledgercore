-- =====================================================================
-- 08_test_cases.sql
-- Repeatable tests. Each test checks the real database state and
-- prints PASS or FAIL. Nothing is assumed: every result is computed.
-- Each run creates its own fresh test customer and accounts, so it
-- can be run many times.
-- Run as: LEDGERCORE, after 07b
-- Save the output to docs/test_results/08_test_cases_output.txt
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

DECLARE
  v_pass   PLS_INTEGER := 0;
  v_fail   PLS_INTEGER := 0;
  v_tag    VARCHAR2(30) := TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3');

  v_cust   NUMBER;
  v_a      NUMBER;   -- main ACTIVE account
  v_b      NUMBER;   -- second ACTIVE account
  v_c      NUMBER;   -- CLOSED account
  v_d      NUMBER;   -- FROZEN account
  v_no     VARCHAR2(12);
  v_txn    NUMBER;
  v_code   NUMBER;

  v_bal_a      NUMBER;
  v_bal_b      NUMBER;
  v_t4_before  NUMBER;
  v_t4_after   NUMBER;
  v_cnt        NUMBER;
  v_cnt2       NUMBER;
  v_num        NUMBER;
  v_num2       NUMBER;

  PROCEDURE report_result (p_name VARCHAR2, p_ok BOOLEAN, p_detail VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF p_ok THEN
      v_pass := v_pass + 1;
      DBMS_OUTPUT.PUT_LINE('PASS  ' || p_name);
    ELSE
      v_fail := v_fail + 1;
      DBMS_OUTPUT.PUT_LINE('FAIL  ' || p_name || '   ' || p_detail);
    END IF;
  END;

  FUNCTION bal (p_id NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN get_account_balance(p_id);
  END;

  FUNCTION entry_count (p_id NUMBER) RETURN NUMBER IS
    n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO n FROM account_entries WHERE account_id = p_id;
    RETURN n;
  END;

  FUNCTION completed_txn_count RETURN NUMBER IS
    n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO n FROM transactions WHERE status = 'COMPLETED';
    RETURN n;
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE('LedgerCore test run ' || v_tag);
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------------------');

  -- ---------------- SETUP ----------------
  ledger_pkg.create_customer('Test Runner ' || v_tag, 'test_' || v_tag || '@ledgercore.test', NULL, v_cust);
  ledger_pkg.create_account(v_cust, 'SAVINGS', v_a, v_no);
  ledger_pkg.create_account(v_cust, 'CURRENT', v_b, v_no);
  ledger_pkg.create_account(v_cust, 'SAVINGS', v_c, v_no);
  ledger_pkg.create_account(v_cust, 'SAVINGS', v_d, v_no);
  ledger_pkg.set_account_status(v_c, 'CLOSED');
  ledger_pkg.set_account_status(v_d, 'FROZEN');
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Setup: customer ' || v_cust || ', accounts A=' || v_a || ' B=' || v_b
                       || ' C(closed)=' || v_c || ' D(frozen)=' || v_d);

  -- ---------------- T01 deposit ----------------
  v_bal_a := bal(v_a);
  ledger_pkg.deposit_funds(v_a, 1000, v_txn, 'T01');
  COMMIT;
  report_result('T01 Deposit increases balance by exactly 1000.00',
         bal(v_a) = v_bal_a + 1000, 'balance=' || bal(v_a));

  -- ---------------- T02 withdrawal ----------------
  v_bal_a := bal(v_a);
  ledger_pkg.withdraw_funds(v_a, 250.50, v_txn, 'T02');
  COMMIT;
  report_result('T02 Withdrawal decreases balance by exactly 250.50',
         bal(v_a) = v_bal_a - 250.50, 'balance=' || bal(v_a));

  -- ---------------- T03 insufficient funds ----------------
  v_bal_a := bal(v_a);
  v_code := 0;
  BEGIN
    ledger_pkg.withdraw_funds(v_a, 999999, v_txn, 'T03');
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
  END;
  report_result('T03 Withdrawal over balance rejected (-20004), balance unchanged',
         v_code = -20004 AND bal(v_a) = v_bal_a, 'code=' || v_code || ' balance=' || bal(v_a));

  -- ---------------- T04 successful transfer ----------------
  v_bal_a := bal(v_a);
  v_bal_b := bal(v_b);
  v_t4_before := v_bal_a;
  ledger_pkg.transfer_funds(v_a, v_b, 300, v_txn, 'T04');
  COMMIT;
  v_t4_after := bal(v_a);
  SELECT COUNT(*),
         SUM(CASE WHEN entry_type = 'DEBIT'  THEN amount ELSE 0 END),
         SUM(CASE WHEN entry_type = 'CREDIT' THEN amount ELSE 0 END)
  INTO   v_cnt, v_num, v_num2
  FROM   account_entries WHERE transaction_id = v_txn;
  report_result('T04 Transfer debits source and credits destination by equal amounts',
         bal(v_a) = v_bal_a - 300 AND bal(v_b) = v_bal_b + 300
         AND v_cnt = 2 AND v_num = 300 AND v_num2 = 300,
         'A=' || bal(v_a) || ' B=' || bal(v_b) || ' entries=' || v_cnt);

  -- ---------------- T05 nonexistent destination ----------------
  v_bal_a := bal(v_a);
  v_cnt := entry_count(v_a);
  v_code := 0;
  BEGIN
    ledger_pkg.transfer_funds(v_a, -1, 50, v_txn, 'T05');
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
  END;
  report_result('T05 Transfer to nonexistent account fails with no partial debit',
         v_code = -20002 AND bal(v_a) = v_bal_a AND entry_count(v_a) = v_cnt,
         'code=' || v_code || ' balance=' || bal(v_a));

  -- ---------------- T06 zero / negative amount ----------------
  v_code := 0;
  BEGIN ledger_pkg.deposit_funds(v_a, 0, v_txn, 'T06a');
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; END;
  v_num := v_code;
  v_code := 0;
  BEGIN ledger_pkg.withdraw_funds(v_a, -10, v_txn, 'T06b');
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; END;
  report_result('T06 Zero deposit and negative withdrawal rejected (-20001)',
         v_num = -20001 AND v_code = -20001, 'codes=' || v_num || ',' || v_code);

  -- ---------------- T07 self transfer ----------------
  v_bal_a := bal(v_a);
  v_code := 0;
  BEGIN ledger_pkg.transfer_funds(v_a, v_a, 10, v_txn, 'T07');
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; END;
  report_result('T07 Transfer to same account rejected (-20005)',
         v_code = -20005 AND bal(v_a) = v_bal_a, 'code=' || v_code);

  -- ---------------- T08 closed / frozen accounts ----------------
  v_code := 0;
  BEGIN ledger_pkg.deposit_funds(v_d, 100, v_txn, 'T08a');
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; END;
  v_num := v_code;
  v_code := 0;
  BEGIN ledger_pkg.deposit_funds(v_c, 100, v_txn, 'T08b');
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; END;
  v_num2 := v_code;
  v_bal_a := bal(v_a);
  v_code := 0;
  BEGIN ledger_pkg.transfer_funds(v_a, v_d, 100, v_txn, 'T08c');
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; END;
  report_result('T08 Deposit to FROZEN, deposit to CLOSED, transfer to FROZEN all rejected (-20003)',
         v_num = -20003 AND v_num2 = -20003 AND v_code = -20003
         AND bal(v_a) = v_bal_a AND bal(v_d) = 0 AND bal(v_c) = 0,
         'codes=' || v_num || ',' || v_num2 || ',' || v_code);

  -- ---------------- T09 induced failure mid-transfer ----------------
  v_bal_a := bal(v_a);
  v_bal_b := bal(v_b);
  v_cnt  := completed_txn_count;
  v_cnt2 := entry_count(v_a) + entry_count(v_b);
  v_code := 0;
  ledger_pkg.set_fail_after_debit(TRUE);
  BEGIN
    ledger_pkg.transfer_funds(v_a, v_b, 100, v_txn, 'T09');
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
  END;
  ledger_pkg.set_fail_after_debit(FALSE);
  report_result('T09 Failure after debit rolls back everything (no balance, entry or transaction change)',
         v_code = -20099 AND bal(v_a) = v_bal_a AND bal(v_b) = v_bal_b
         AND completed_txn_count = v_cnt
         AND entry_count(v_a) + entry_count(v_b) = v_cnt2,
         'code=' || v_code || ' A=' || bal(v_a) || ' B=' || bal(v_b));

  -- ---------------- T10 audit trail ----------------
  -- Account A had exactly 3 successful balance changes: T01, T02, T04
  SELECT COUNT(*) INTO v_cnt FROM account_audit WHERE account_id = v_a;
  SELECT old_balance, new_balance INTO v_num, v_num2
  FROM (SELECT old_balance, new_balance FROM account_audit
        WHERE account_id = v_a ORDER BY audit_id DESC)
  WHERE ROWNUM = 1;
  report_result('T10 Audit has one row per balance change, last row matches T04 old/new balance',
         v_cnt = 3 AND v_num = v_t4_before AND v_num2 = v_t4_after,
         'rows=' || v_cnt || ' old=' || v_num || ' new=' || v_num2);

  -- ---------------- T11 history and statement consistency ----------------
  SELECT NVL(SUM(CASE entry_type WHEN 'CREDIT' THEN amount ELSE -amount END), 0)
  INTO v_num FROM account_entries WHERE account_id = v_a;
  SELECT balance_after INTO v_num2
  FROM (SELECT balance_after FROM account_entries WHERE account_id = v_a ORDER BY entry_id DESC)
  WHERE ROWNUM = 1;
  report_result('T11 Credits minus debits = balance, and last balance_after = balance',
         v_num = bal(v_a) AND v_num2 = bal(v_a),
         'ledger=' || v_num || ' last=' || v_num2 || ' balance=' || bal(v_a));

  -- ---------------- T12 bank-wide reconciliation ----------------
  SELECT COUNT(*) INTO v_cnt FROM v_reconciliation WHERE difference <> 0;
  report_result('T12 Reconciliation: every account balance matches its ledger',
         v_cnt = 0, v_cnt || ' account(s) out of balance');

  -- ---------------- T13 rejected and failed attempts are logged ----------------
  SELECT COUNT(*) INTO v_cnt FROM transaction_log
  WHERE account_id = v_a AND event_type = 'REJECTED';      -- T03, T05, T06a, T06b, T07, T08c
  SELECT COUNT(*) INTO v_cnt2 FROM transaction_log
  WHERE account_id = v_a AND event_type = 'ERROR';         -- T09
  SELECT COUNT(*) INTO v_num FROM transactions
  WHERE status = 'REJECTED' AND amount = 999999 AND description LIKE '%Insufficient funds%'
  AND created_at >= SYSTIMESTAMP - INTERVAL '1' HOUR;
  report_result('T13 Rejections logged as REJECTED, system failure logged as ERROR (survive rollback)',
         v_cnt >= 6 AND v_cnt2 >= 1 AND v_num >= 1,
         'rejected=' || v_cnt || ' error=' || v_cnt2 || ' rejected_txn=' || v_num);

  -- ---------------- T14 CHECK constraint blocks a direct negative balance ----------------
  v_code := 0;
  BEGIN
    UPDATE accounts SET balance = -1 WHERE account_id = v_a;
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
  END;
  ROLLBACK;
  report_result('T14 Direct UPDATE to negative balance blocked by ck_accounts_balance (ORA-02290)',
         v_code = -2290, 'code=' || v_code);

  -- ---------------- T15 ledger is append-only ----------------
  v_code := 0;
  BEGIN
    UPDATE account_entries SET amount = 1 WHERE account_id = v_a;
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE;
  END;
  ROLLBACK;
  report_result('T15 Updating a ledger entry is blocked by trigger (-20010)',
         v_code = -20010, 'code=' || v_code);

  -- ---------------- T16 transaction count function ----------------
  report_result('T16 GET_TRANSACTION_COUNT(A) = 3 completed transactions (T01, T02, T04)',
         get_transaction_count(v_a) = 3, 'count=' || get_transaction_count(v_a));

  -- ---------------- T17 closing needs zero balance ----------------
  v_code := 0;
  BEGIN ledger_pkg.set_account_status(v_a, 'CLOSED');
  EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; END;
  report_result('T17 Closing an account with money in it is rejected (-20006)',
         v_code = -20006, 'code=' || v_code);

  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('RESULT: ' || v_pass || ' passed, ' || v_fail || ' failed');
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------------------');

  -- Cursor-based statement for the test account (explicit cursor demo)
  print_account_statement(v_a);
END;
/

-- Cursor FOR loop reports
EXEC print_high_value_transactions(50000)
EXEC print_monthly_activity(NULL)
