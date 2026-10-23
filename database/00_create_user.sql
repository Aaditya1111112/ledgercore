-- =====================================================================
-- 00_create_user.sql
-- Run ONCE as SYSTEM (or another DBA user) connected to the pluggable
-- database XEPDB1, not the root container.
--   sql system@localhost:1521/XEPDB1 @database/00_create_user.sql
-- It asks for the password you want for the LEDGERCORE user.
-- =====================================================================
SET VERIFY OFF
ACCEPT app_password CHAR PROMPT 'Choose a password for LEDGERCORE: ' HIDE

CREATE USER ledgercore IDENTIFIED BY "&app_password"
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;

GRANT CREATE SESSION,
      CREATE TABLE,
      CREATE SEQUENCE,
      CREATE VIEW,
      CREATE PROCEDURE,
      CREATE TRIGGER,
      CREATE JOB            -- needed by 08b_concurrency_test.sql
TO ledgercore;

PROMPT User LEDGERCORE created. Now connect as LEDGERCORE and run run_all.sql
