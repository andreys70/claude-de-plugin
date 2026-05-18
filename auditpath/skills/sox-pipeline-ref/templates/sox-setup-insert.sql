-- ============================================================
-- RPT_SOX_SETUP + RPT_SOX_METADATA INSERT TEMPLATE
-- Replace all <placeholders> before executing.
-- Execute via Databricks MCP after Checkpoint 2 engineer approval.
-- ============================================================

-- Step 1: Get next IDs (run first, capture output)
SELECT MAX(RPT_SOX_SETUP_ID) + 1    AS next_setup_id    FROM finance_mm_sandbox.RPT_SOX_SETUP;
SELECT MAX(RPT_SOX_METADATA_ID) + 1 AS next_metadata_id FROM finance_mm_sandbox.RPT_SOX_METADATA;

-- Step 2: Insert RPT_SOX_SETUP row
INSERT INTO finance_mm_sandbox.RPT_SOX_SETUP
  (RPT_SOX_SETUP_ID, TABLE_NAME, START_DATE, END_DATE, ACTIVE_FLAG, CREATED_TS, LAST_RUN_TS)
VALUES
  (
    <next_setup_id>,
    '<table_name>',
    date_trunc('month', add_months(current_date(), -1)),
    last_day(date_trunc('month', add_months(current_date(), -1))),
    true,
    current_timestamp(),
    current_timestamp()
  );

-- Step 3: Insert RPT_SOX_METADATA rows (one per validated column)
INSERT INTO finance_mm_sandbox.RPT_SOX_METADATA
  (RPT_SOX_METADATA_ID, RPT_SOX_SETUP_ID, TABLE_NAME, COLUMN_NAME, ACTIVE_FLAG, CREATED_TS)
VALUES
  (<next_metadata_id>,     <next_setup_id>, '<table_name>', '<col1>', true, current_timestamp()),
  (<next_metadata_id> + 1, <next_setup_id>, '<table_name>', '<col2>', true, current_timestamp()),
  (<next_metadata_id> + 2, <next_setup_id>, '<table_name>', '<col3>', true, current_timestamp()),
  (<next_metadata_id> + 3, <next_setup_id>, '<table_name>', '<col4>', true, current_timestamp()),
  (<next_metadata_id> + 4, <next_setup_id>, '<table_name>', '<col5>', true, current_timestamp());

-- Step 4: Verify
SELECT * FROM finance_mm_sandbox.RPT_SOX_SETUP    WHERE TABLE_NAME = '<table_name>';
SELECT * FROM finance_mm_sandbox.RPT_SOX_METADATA WHERE TABLE_NAME = '<table_name>';
