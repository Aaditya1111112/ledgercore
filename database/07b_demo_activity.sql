-- =====================================================================
-- 07b_demo_activity.sql
-- Realistic demo activity for the dashboard, done ONLY through LEDGER_PKG.
-- Includes one rejected attempt so the logs have something to show.
-- Run as: LEDGERCORE, after 07 (run once)
-- =====================================================================
SET SERVEROUTPUT ON

DECLARE
  v_txn NUMBER;

  FUNCTION acc (p_no VARCHAR2) RETURN NUMBER IS
    v_id NUMBER;
  BEGIN
    SELECT account_id INTO v_id FROM accounts WHERE account_no = p_no;
    RETURN v_id;
  END;
BEGIN
  -- Opening deposits
  ledger_pkg.deposit_funds(acc('LC0000000001'),  85000,   v_txn, 'Opening deposit');
  ledger_pkg.deposit_funds(acc('LC0000000002'), 250000,   v_txn, 'Opening deposit');
  ledger_pkg.deposit_funds(acc('LC0000000003'),  42000,   v_txn, 'Opening deposit');
  ledger_pkg.deposit_funds(acc('LC0000000004'),  15500,   v_txn, 'Opening deposit');
  ledger_pkg.deposit_funds(acc('LC0000000005'), 120000,   v_txn, 'Opening deposit');
  ledger_pkg.deposit_funds(acc('LC0000000006'),  64000,   v_txn, 'Opening deposit');
  ledger_pkg.deposit_funds(acc('LC0000000007'),   9000,   v_txn, 'Opening deposit');

  -- Everyday activity
  ledger_pkg.withdraw_funds(acc('LC0000000001'),  4500,    v_txn, 'ATM withdrawal');
  ledger_pkg.transfer_funds(acc('LC0000000002'), acc('LC0000000003'), 18000, v_txn, 'Rent share');
  ledger_pkg.transfer_funds(acc('LC0000000005'), acc('LC0000000002'), 60000, v_txn, 'Supplier payment');
  ledger_pkg.deposit_funds(acc('LC0000000004'),   7250.75, v_txn, 'Salary credit');
  ledger_pkg.withdraw_funds(acc('LC0000000006'),  2300.40, v_txn, 'Card payment');
  ledger_pkg.transfer_funds(acc('LC0000000006'), acc('LC0000000007'),  5000, v_txn, 'Gift');
  ledger_pkg.transfer_funds(acc('LC0000000001'), acc('LC0000000002'), 20000, v_txn, 'Move to current');
  COMMIT;

  -- A rejected attempt (insufficient funds). The package rolls back its
  -- own work and the autonomous logger keeps a REJECTED record.
  BEGIN
    ledger_pkg.withdraw_funds(acc('LC0000000007'), 99999, v_txn, 'Too large');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Expected rejection: ' || SQLERRM);
  END;

  -- Freeze one account to show status rules
  ledger_pkg.set_account_status(acc('LC0000000004'), 'FROZEN');
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Demo activity committed');
END;
/
