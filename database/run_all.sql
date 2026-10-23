-- =====================================================================
-- run_all.sql  -  builds and tests the whole database in one go.
-- Run as LEDGERCORE from the project root, for example with SQLcl:
--   sql ledgercore@localhost:1521/XEPDB1 @database/run_all.sql
-- Output is saved to docs/test_results/run_all_output.txt
-- WARNING: 01_schema.sql drops and recreates all tables.
-- =====================================================================
SET ECHO OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SPOOL docs/test_results/run_all_output.txt

@@01_schema.sql
@@02_constraints_indexes.sql
@@03_sample_data.sql
@@04_functions.sql
@@05_procedures.sql
@@06_packages.sql
@@07_triggers.sql
@@07b_demo_activity.sql
@@08_test_cases.sql
@@08b_concurrency_test.sql
@@09_query_plan_tests.sql

-- Any compile errors left?
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

SPOOL OFF
