-- =====================================================================
-- 08b_concurrency_test.sql
-- Proves that two sessions withdrawing at the SAME time cannot cause an
-- overdraft or a lost update.
--
-- How: an account gets 1000.00. Two scheduler jobs (two separate
-- database sessions) each try to withdraw 700.00 at the same moment.
-- Each job holds its row lock for 3 seconds (test hook) so they really
-- overlap. Expected: one succeeds, the other waits for the lock, then
-- sees balance 300.00 and is rejected. Final balance = 300.00.
--
-- Without SELECT ... FOR UPDATE both sessions could read 1000, both
-- pass the funds check, and the balance would go to -400 (the CHECK
-- constraint would then stop the second one, but the business check
-- would have been bypassed).
--
-- Needs the CREATE JOB privilege (granted in 00_create_user.sql).
-- Run as: LEDGERCORE. Takes about 15 seconds.
-- A manual two-window version is in 08c_two_session_manual.sql
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

DECLARE
  v_tag     VARCHAR2(20) := TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISS');
  v_cust    NUMBER;
  v_acc     NUMBER;
  v_no      VARCHAR2(12);
  v_txn     NUMBER;
  v_debits  NUMBER;
  v_rejects NUMBER;
  v_final   NUMBER;
BEGIN
  ledger_pkg.create_customer('Concurrency Test ' || v_tag,
                             'conc_' || v_tag || '@ledgercore.test', NULL, v_cust);
  ledger_pkg.create_account(v_cust, 'SAVINGS', v_acc, v_no);
  ledger_pkg.deposit_funds(v_acc, 1000, v_txn, 'Concurrency setup');
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Account ' || v_acc || ' (' || v_no || ') funded with 1000.00');

  FOR i IN 1 .. 2 LOOP
    DBMS_SCHEDULER.CREATE_JOB(
      job_name   => 'LC_CONC_' || v_tag || '_' || i,
      job_type   => 'PLSQL_BLOCK',
      job_action => 'DECLARE t NUMBER; BEGIN '
                 || 'ledger_pkg.set_delay_after_lock(3); '
                 || 'ledger_pkg.withdraw_funds(' || v_acc || ', 700, t, ''Concurrent job ' || i || '''); '
                 || 'COMMIT; END;',
      enabled    => TRUE,
      auto_drop  => TRUE);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Two jobs started, each withdrawing 700.00. Waiting 15 seconds...');

  DBMS_SESSION.SLEEP(15);

  SELECT COUNT(*) INTO v_debits FROM account_entries
  WHERE account_id = v_acc AND entry_type = 'DEBIT';
  SELECT COUNT(*) INTO v_rejects FROM transaction_log
  WHERE account_id = v_acc AND event_type = 'REJECTED';
  v_final := get_account_balance(v_acc);

  DBMS_OUTPUT.PUT_LINE('Successful withdrawals : ' || v_debits);
  DBMS_OUTPUT.PUT_LINE('Rejected withdrawals   : ' || v_rejects);
  DBMS_OUTPUT.PUT_LINE('Final balance          : ' || TO_CHAR(v_final, 'FM999990.00'));

  IF v_debits = 1 AND v_rejects = 1 AND v_final = 300 THEN
    DBMS_OUTPUT.PUT_LINE('PASS  T18 Concurrent withdrawals: exactly one succeeded, no overdraft, no lost update');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FAIL  T18 Concurrent withdrawals (if both counts are 0, the jobs did not run: '
                         || 'check job_queue_processes and USER_SCHEDULER_JOB_RUN_DETAILS)');
  END IF;
END;
/

-- Job history: shows both sessions, their start times and outcome
COLUMN job_name FORMAT A32
COLUMN status FORMAT A10
COLUMN error# FORMAT 999999
SELECT job_name, status, error#,
       TO_CHAR(actual_start_date, 'HH24:MI:SS.FF2') AS started,
       TO_CHAR(run_duration) AS duration
FROM   user_scheduler_job_run_details
WHERE  job_name LIKE 'LC_CONC_%'
ORDER  BY log_date DESC
FETCH FIRST 2 ROWS ONLY;
