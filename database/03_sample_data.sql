-- =====================================================================
-- 03_sample_data.sql
-- Fictional customers and accounts. All accounts start at balance 0.
-- Money is added later only through the package (07b_demo_activity.sql),
-- so the ledger and balances always agree.
-- Run as: LEDGERCORE, after 02
-- =====================================================================

INSERT INTO customers (full_name, email, phone) VALUES ('Aarav Mehta',   'aarav.mehta@example.com',   '9000000001');
INSERT INTO customers (full_name, email, phone) VALUES ('Diya Nair',     'diya.nair@example.com',     '9000000002');
INSERT INTO customers (full_name, email, phone) VALUES ('Kabir Rao',     'kabir.rao@example.com',     '9000000003');
INSERT INTO customers (full_name, email, phone) VALUES ('Meera Iyer',    'meera.iyer@example.com',    '9000000004');
INSERT INTO customers (full_name, email, phone) VALUES ('Rohan Kulkarni','rohan.kulkarni@example.com', NULL);

-- Two accounts for some customers, one for others
INSERT INTO accounts (account_no, customer_id, account_type)
  SELECT 'LC' || LPAD(account_no_seq.NEXTVAL, 10, '0'), customer_id, 'SAVINGS'
  FROM customers WHERE email = 'aarav.mehta@example.com';
INSERT INTO accounts (account_no, customer_id, account_type)
  SELECT 'LC' || LPAD(account_no_seq.NEXTVAL, 10, '0'), customer_id, 'CURRENT'
  FROM customers WHERE email = 'aarav.mehta@example.com';
INSERT INTO accounts (account_no, customer_id, account_type)
  SELECT 'LC' || LPAD(account_no_seq.NEXTVAL, 10, '0'), customer_id, 'SAVINGS'
  FROM customers WHERE email = 'diya.nair@example.com';
INSERT INTO accounts (account_no, customer_id, account_type)
  SELECT 'LC' || LPAD(account_no_seq.NEXTVAL, 10, '0'), customer_id, 'SAVINGS'
  FROM customers WHERE email = 'kabir.rao@example.com';
INSERT INTO accounts (account_no, customer_id, account_type)
  SELECT 'LC' || LPAD(account_no_seq.NEXTVAL, 10, '0'), customer_id, 'CURRENT'
  FROM customers WHERE email = 'kabir.rao@example.com';
INSERT INTO accounts (account_no, customer_id, account_type)
  SELECT 'LC' || LPAD(account_no_seq.NEXTVAL, 10, '0'), customer_id, 'SAVINGS'
  FROM customers WHERE email = 'meera.iyer@example.com';
INSERT INTO accounts (account_no, customer_id, account_type)
  SELECT 'LC' || LPAD(account_no_seq.NEXTVAL, 10, '0'), customer_id, 'SAVINGS'
  FROM customers WHERE email = 'rohan.kulkarni@example.com';

COMMIT;

PROMPT 03_sample_data.sql done: 5 customers, 7 accounts
