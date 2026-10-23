-- =====================================================================
-- 06_packages.sql
-- LEDGER_PKG: the ONLY place where balances are changed.
--
-- Transaction ownership rule:
--   These procedures NEVER COMMIT. Each one sets a SAVEPOINT at the
--   start. If anything fails it rolls back to that savepoint (undoing
--   only its own work), logs the failure, and re-raises the error.
--   The caller (Flask API or a test script) decides COMMIT or ROLLBACK.
--
-- Error codes (also mapped to HTTP codes in the Flask API):
--   -20001 invalid amount            -20004 insufficient funds
--   -20002 account/customer missing  -20005 transfer to same account
--   -20003 account not ACTIVE        -20006 invalid input
--   -20099 simulated failure (test hook only)
-- Run as: LEDGERCORE, after 05
-- =====================================================================

CREATE OR REPLACE PACKAGE ledger_pkg AS

  c_err_invalid_amount  CONSTANT PLS_INTEGER := -20001;
  c_err_not_found       CONSTANT PLS_INTEGER := -20002;
  c_err_not_active      CONSTANT PLS_INTEGER := -20003;
  c_err_insufficient    CONSTANT PLS_INTEGER := -20004;
  c_err_self_transfer   CONSTANT PLS_INTEGER := -20005;
  c_err_invalid_input   CONSTANT PLS_INTEGER := -20006;
  c_err_test_failure    CONSTANT PLS_INTEGER := -20099;

  PROCEDURE create_customer (
    p_full_name    IN  VARCHAR2,
    p_email        IN  VARCHAR2,
    p_phone        IN  VARCHAR2,
    p_customer_id  OUT NUMBER
  );

  PROCEDURE create_account (
    p_customer_id   IN  NUMBER,
    p_account_type  IN  VARCHAR2,
    p_account_id    OUT NUMBER,
    p_account_no    OUT VARCHAR2
  );

  PROCEDURE deposit_funds (
    p_account_id      IN  NUMBER,
    p_amount          IN  NUMBER,
    p_transaction_id  OUT NUMBER,
    p_description     IN  VARCHAR2 DEFAULT NULL
  );

  PROCEDURE withdraw_funds (
    p_account_id      IN  NUMBER,
    p_amount          IN  NUMBER,
    p_transaction_id  OUT NUMBER,
    p_description     IN  VARCHAR2 DEFAULT NULL
  );

  PROCEDURE transfer_funds (
    p_source_account_id       IN  NUMBER,
    p_destination_account_id  IN  NUMBER,
    p_amount                  IN  NUMBER,
    p_transaction_id          OUT NUMBER,
    p_description             IN  VARCHAR2 DEFAULT NULL
  );

  -- ACTIVE <-> FROZEN, or -> CLOSED (only with zero balance, permanent)
  PROCEDURE set_account_status (
    p_account_id  IN NUMBER,
    p_new_status  IN VARCHAR2
  );

  -- Test hooks. They only affect the current session.
  PROCEDURE set_fail_after_debit (p_flag IN BOOLEAN);
  PROCEDURE set_delay_after_lock (p_seconds IN NUMBER);

END ledger_pkg;
/
SHOW ERRORS

CREATE OR REPLACE PACKAGE BODY ledger_pkg AS

  -- Session-level test switches (each database session has its own copy)
  g_fail_after_debit  BOOLEAN := FALSE;
  g_delay_after_lock  NUMBER  := 0;

  PROCEDURE set_fail_after_debit (p_flag IN BOOLEAN) IS
  BEGIN
    g_fail_after_debit := NVL(p_flag, FALSE);
  END;

  PROCEDURE set_delay_after_lock (p_seconds IN NUMBER) IS
  BEGIN
    g_delay_after_lock := NVL(p_seconds, 0);
  END;

  -- ===================== private helpers ===========================

  -- Lock one account row (SELECT ... FOR UPDATE) and read it.
  -- Any other session that tries to lock the same row now has to wait
  -- until we COMMIT or ROLLBACK.
  PROCEDURE lock_account (
    p_account_id  IN  NUMBER,
    p_balance     OUT NUMBER,
    p_status      OUT VARCHAR2
  ) IS
  BEGIN
    SELECT balance, status
    INTO   p_balance, p_status
    FROM   accounts
    WHERE  account_id = p_account_id
    FOR UPDATE;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(c_err_not_found,
        'Account ' || NVL(TO_CHAR(p_account_id), 'NULL') || ' does not exist');
  END lock_account;

  PROCEDURE check_amount (p_amount IN NUMBER) IS
  BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
      RAISE_APPLICATION_ERROR(c_err_invalid_amount, 'Amount must be greater than zero');
    END IF;
    IF p_amount <> ROUND(p_amount, 2) THEN
      RAISE_APPLICATION_ERROR(c_err_invalid_amount, 'Amount can have at most 2 decimal places');
    END IF;
  END check_amount;

  PROCEDURE check_active (p_account_id IN NUMBER, p_status IN VARCHAR2) IS
  BEGIN
    IF p_status <> 'ACTIVE' THEN
      RAISE_APPLICATION_ERROR(c_err_not_active,
        'Account ' || p_account_id || ' is ' || p_status || ', operation not allowed');
    END IF;
  END check_active;

  -- Used only by the concurrency test, to hold the lock for a while
  PROCEDURE pause_if_testing IS
  BEGIN
    IF g_delay_after_lock > 0 THEN
      DBMS_SESSION.SLEEP(g_delay_after_lock);
    END IF;
  END pause_if_testing;

  FUNCTION is_business_error (p_code IN NUMBER) RETURN BOOLEAN IS
  BEGIN
    RETURN p_code BETWEEN -20006 AND -20001;
  END is_business_error;

  -- Called from every exception handler AFTER rolling back to the
  -- savepoint. Business rule errors -> REJECTED, everything else -> ERROR.
  PROCEDURE log_failure (
    p_code        IN NUMBER,
    p_message     IN VARCHAR2,
    p_txn_type    IN VARCHAR2,
    p_amount      IN NUMBER,
    p_account_id  IN NUMBER
  ) IS
  BEGIN
    IF is_business_error(p_code) THEN
      record_rejection(p_txn_type, p_amount, p_account_id, p_message);
    ELSE
      log_system_error(p_txn_type, p_account_id, p_message);
    END IF;
  END log_failure;

  -- ===================== public procedures =========================

  PROCEDURE create_customer (
    p_full_name    IN  VARCHAR2,
    p_email        IN  VARCHAR2,
    p_phone        IN  VARCHAR2,
    p_customer_id  OUT NUMBER
  ) IS
  BEGIN
    SAVEPOINT sp_create_customer;

    IF TRIM(p_full_name) IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_invalid_input, 'Full name is required');
    END IF;
    IF TRIM(p_email) IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_invalid_input, 'Email is required');
    END IF;

    INSERT INTO customers (full_name, email, phone)
    VALUES (TRIM(p_full_name), LOWER(TRIM(p_email)), TRIM(p_phone))
    RETURNING customer_id INTO p_customer_id;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      ROLLBACK TO SAVEPOINT sp_create_customer;
      RAISE_APPLICATION_ERROR(c_err_invalid_input, 'Email ' || p_email || ' is already registered');
    WHEN OTHERS THEN
      ROLLBACK TO SAVEPOINT sp_create_customer;
      IF SQLCODE = -2290 THEN  -- check constraint (bad email format)
        RAISE_APPLICATION_ERROR(c_err_invalid_input, 'Email format is not valid');
      END IF;
      RAISE;
  END create_customer;

  PROCEDURE create_account (
    p_customer_id   IN  NUMBER,
    p_account_type  IN  VARCHAR2,
    p_account_id    OUT NUMBER,
    p_account_no    OUT VARCHAR2
  ) IS
    v_exists NUMBER;
  BEGIN
    SAVEPOINT sp_create_account;

    IF UPPER(p_account_type) NOT IN ('SAVINGS', 'CURRENT') OR p_account_type IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_invalid_input, 'Account type must be SAVINGS or CURRENT');
    END IF;

    SELECT COUNT(*) INTO v_exists FROM customers WHERE customer_id = p_customer_id;
    IF v_exists = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_not_found, 'Customer ' || p_customer_id || ' does not exist');
    END IF;

    p_account_no := 'LC' || LPAD(account_no_seq.NEXTVAL, 10, '0');

    INSERT INTO accounts (account_no, customer_id, account_type)
    VALUES (p_account_no, p_customer_id, UPPER(p_account_type))
    RETURNING account_id INTO p_account_id;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO SAVEPOINT sp_create_account;
      RAISE;
  END create_account;

  PROCEDURE deposit_funds (
    p_account_id      IN  NUMBER,
    p_amount          IN  NUMBER,
    p_transaction_id  OUT NUMBER,
    p_description     IN  VARCHAR2 DEFAULT NULL
  ) IS
    v_balance      accounts.balance%TYPE;
    v_status       accounts.status%TYPE;
    v_new_balance  accounts.balance%TYPE;
    v_code         NUMBER;
    v_msg          VARCHAR2(4000);
  BEGIN
    SAVEPOINT sp_deposit;

    check_amount(p_amount);
    lock_account(p_account_id, v_balance, v_status);
    pause_if_testing;
    check_active(p_account_id, v_status);

    INSERT INTO transactions (transaction_type, amount, status, description)
    VALUES ('DEPOSIT', p_amount, 'COMPLETED', p_description)
    RETURNING transaction_id INTO p_transaction_id;

    UPDATE accounts
    SET    balance = balance + p_amount
    WHERE  account_id = p_account_id
    RETURNING balance INTO v_new_balance;

    INSERT INTO account_entries (transaction_id, account_id, entry_type, amount, balance_after)
    VALUES (p_transaction_id, p_account_id, 'CREDIT', p_amount, v_new_balance);

    INSERT INTO transaction_log (transaction_id, account_id, event_type, details)
    VALUES (p_transaction_id, p_account_id, 'COMPLETED',
            'Deposit of ' || TO_CHAR(p_amount, 'FM999999999990.00'));
  EXCEPTION
    WHEN OTHERS THEN
      v_code := SQLCODE;
      v_msg  := SQLERRM;
      ROLLBACK TO SAVEPOINT sp_deposit;
      p_transaction_id := NULL;
      log_failure(v_code, v_msg, 'DEPOSIT', p_amount, p_account_id);
      RAISE;
  END deposit_funds;

  PROCEDURE withdraw_funds (
    p_account_id      IN  NUMBER,
    p_amount          IN  NUMBER,
    p_transaction_id  OUT NUMBER,
    p_description     IN  VARCHAR2 DEFAULT NULL
  ) IS
    v_balance      accounts.balance%TYPE;
    v_status       accounts.status%TYPE;
    v_new_balance  accounts.balance%TYPE;
    v_code         NUMBER;
    v_msg          VARCHAR2(4000);
  BEGIN
    SAVEPOINT sp_withdraw;

    check_amount(p_amount);
    lock_account(p_account_id, v_balance, v_status);   -- row is now locked
    pause_if_testing;
    check_active(p_account_id, v_status);

    -- Safe to check here: nobody else can change this balance until we finish
    IF v_balance < p_amount THEN
      RAISE_APPLICATION_ERROR(c_err_insufficient,
        'Insufficient funds: balance ' || TO_CHAR(v_balance, 'FM999999999990.00')
        || ', requested ' || TO_CHAR(p_amount, 'FM999999999990.00'));
    END IF;

    INSERT INTO transactions (transaction_type, amount, status, description)
    VALUES ('WITHDRAWAL', p_amount, 'COMPLETED', p_description)
    RETURNING transaction_id INTO p_transaction_id;

    UPDATE accounts
    SET    balance = balance - p_amount
    WHERE  account_id = p_account_id
    RETURNING balance INTO v_new_balance;

    INSERT INTO account_entries (transaction_id, account_id, entry_type, amount, balance_after)
    VALUES (p_transaction_id, p_account_id, 'DEBIT', p_amount, v_new_balance);

    INSERT INTO transaction_log (transaction_id, account_id, event_type, details)
    VALUES (p_transaction_id, p_account_id, 'COMPLETED',
            'Withdrawal of ' || TO_CHAR(p_amount, 'FM999999999990.00'));
  EXCEPTION
    WHEN OTHERS THEN
      v_code := SQLCODE;
      v_msg  := SQLERRM;
      ROLLBACK TO SAVEPOINT sp_withdraw;
      p_transaction_id := NULL;
      log_failure(v_code, v_msg, 'WITHDRAWAL', p_amount, p_account_id);
      RAISE;
  END withdraw_funds;

  PROCEDURE transfer_funds (
    p_source_account_id       IN  NUMBER,
    p_destination_account_id  IN  NUMBER,
    p_amount                  IN  NUMBER,
    p_transaction_id          OUT NUMBER,
    p_description             IN  VARCHAR2 DEFAULT NULL
  ) IS
    v_src_balance   accounts.balance%TYPE;
    v_src_status    accounts.status%TYPE;
    v_dst_balance   accounts.balance%TYPE;
    v_dst_status    accounts.status%TYPE;
    v_new_src       accounts.balance%TYPE;
    v_new_dst       accounts.balance%TYPE;
    v_code          NUMBER;
    v_msg           VARCHAR2(4000);
  BEGIN
    SAVEPOINT sp_transfer;

    -- 1. Validate the request itself
    check_amount(p_amount);
    IF p_source_account_id IS NULL OR p_destination_account_id IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_invalid_input, 'Source and destination accounts are required');
    END IF;
    IF p_source_account_id = p_destination_account_id THEN
      RAISE_APPLICATION_ERROR(c_err_self_transfer, 'Cannot transfer to the same account');
    END IF;

    -- 2. Lock BOTH rows, always the lower account_id first.
    --    If two transfers A->B and B->A run together, both try to lock
    --    the same row first, so one simply waits instead of deadlocking.
    IF p_source_account_id < p_destination_account_id THEN
      lock_account(p_source_account_id,      v_src_balance, v_src_status);
      lock_account(p_destination_account_id, v_dst_balance, v_dst_status);
    ELSE
      lock_account(p_destination_account_id, v_dst_balance, v_dst_status);
      lock_account(p_source_account_id,      v_src_balance, v_src_status);
    END IF;
    pause_if_testing;

    -- 3. Business rules, checked while we hold the locks
    check_active(p_source_account_id, v_src_status);
    check_active(p_destination_account_id, v_dst_status);
    IF v_src_balance < p_amount THEN
      RAISE_APPLICATION_ERROR(c_err_insufficient,
        'Insufficient funds: balance ' || TO_CHAR(v_src_balance, 'FM999999999990.00')
        || ', requested ' || TO_CHAR(p_amount, 'FM999999999990.00'));
    END IF;

    -- 4. Record the transaction and its transfer details
    INSERT INTO transactions (transaction_type, amount, status, description)
    VALUES ('TRANSFER', p_amount, 'COMPLETED', p_description)
    RETURNING transaction_id INTO p_transaction_id;

    INSERT INTO transfer_details (transaction_id, source_account_id, destination_account_id)
    VALUES (p_transaction_id, p_source_account_id, p_destination_account_id);

    -- 5. Debit the source
    UPDATE accounts SET balance = balance - p_amount
    WHERE  account_id = p_source_account_id
    RETURNING balance INTO v_new_src;

    INSERT INTO account_entries (transaction_id, account_id, entry_type, amount, balance_after)
    VALUES (p_transaction_id, p_source_account_id, 'DEBIT', p_amount, v_new_src);

    -- Test hook: fail half way, after the debit and before the credit.
    -- Used by test T09 to prove the whole transfer is rolled back.
    IF g_fail_after_debit THEN
      RAISE_APPLICATION_ERROR(c_err_test_failure, 'Simulated failure after debit (test hook)');
    END IF;

    -- 6. Credit the destination
    UPDATE accounts SET balance = balance + p_amount
    WHERE  account_id = p_destination_account_id
    RETURNING balance INTO v_new_dst;

    INSERT INTO account_entries (transaction_id, account_id, entry_type, amount, balance_after)
    VALUES (p_transaction_id, p_destination_account_id, 'CREDIT', p_amount, v_new_dst);

    INSERT INTO transaction_log (transaction_id, account_id, event_type, details)
    VALUES (p_transaction_id, p_source_account_id, 'COMPLETED',
            'Transfer of ' || TO_CHAR(p_amount, 'FM999999999990.00')
            || ' from account ' || p_source_account_id
            || ' to account ' || p_destination_account_id);
    -- No COMMIT here: the caller commits.
  EXCEPTION
    WHEN OTHERS THEN
      v_code := SQLCODE;
      v_msg  := SQLERRM;
      ROLLBACK TO SAVEPOINT sp_transfer;   -- undoes debit, credit and all rows above
      p_transaction_id := NULL;
      log_failure(v_code, v_msg || ' (destination ' || p_destination_account_id || ')',
                  'TRANSFER', p_amount, p_source_account_id);
      RAISE;
  END transfer_funds;

  PROCEDURE set_account_status (
    p_account_id  IN NUMBER,
    p_new_status  IN VARCHAR2
  ) IS
    v_balance  accounts.balance%TYPE;
    v_status   accounts.status%TYPE;
    v_new      VARCHAR2(10) := UPPER(p_new_status);
  BEGIN
    SAVEPOINT sp_status;

    IF v_new IS NULL OR v_new NOT IN ('ACTIVE', 'FROZEN', 'CLOSED') THEN
      RAISE_APPLICATION_ERROR(c_err_invalid_input, 'Status must be ACTIVE, FROZEN or CLOSED');
    END IF;

    lock_account(p_account_id, v_balance, v_status);

    IF v_status = 'CLOSED' THEN
      RAISE_APPLICATION_ERROR(c_err_not_active, 'Account ' || p_account_id || ' is closed permanently');
    END IF;
    IF v_new = 'CLOSED' AND v_balance <> 0 THEN
      RAISE_APPLICATION_ERROR(c_err_invalid_input,
        'Balance must be zero before closing (current ' || TO_CHAR(v_balance, 'FM999999999990.00') || ')');
    END IF;

    UPDATE accounts
    SET    status    = v_new,
           closed_at = CASE WHEN v_new = 'CLOSED' THEN SYSTIMESTAMP END
    WHERE  account_id = p_account_id;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO SAVEPOINT sp_status;
      RAISE;
  END set_account_status;

END ledger_pkg;
/
SHOW ERRORS

PROMPT 06_packages.sql done
