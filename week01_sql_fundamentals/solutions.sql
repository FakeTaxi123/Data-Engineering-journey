/* =====================================================================
   WEEK 1 - SQL FUNDAMENTALS: SOLUTIONS (tasks 1-11)
   ---------------------------------------------------------------------
   Dataset : factory_dataset.sql (mini factory: 5 machines, 1 day)
   Tables  : machines, readings, machine_states, alarms
   Run in  : pgAdmin -> your database -> Query Tool
             Select one query and press F5 to run only that query.
   Notes   : My own solutions, with fixes from code review applied.
   ===================================================================== */


/* =====================================================================
   KEY TAKEAWAYS
   ---------------------------------------------------------------------
   1. Writing order : SELECT -> FROM -> WHERE -> GROUP BY -> HAVING
                      -> ORDER BY -> LIMIT
      Execution order: FROM -> WHERE -> GROUP BY -> HAVING -> SELECT
                      (window functions here) -> ORDER BY -> LIMIT
      => WHERE cannot see SELECT aliases or window functions.
      => ORDER BY can use SELECT aliases.

   2. GROUP BY defines what ONE output row means.
      Every SELECT column not inside COUNT/SUM/AVG/MIN/MAX
      must be in GROUP BY.
      WHERE filters rows BEFORE grouping, HAVING filters groups AFTER.

   3. NULL = "no value". Use IS NULL / IS NOT NULL, never = NULL.
      COUNT(*) counts rows, COUNT(col) skips NULLs.
      AVG/SUM/MIN/MAX ignore NULLs.
      ORDER BY ... DESC puts NULLs first in PostgreSQL -> NULLS LAST.
      Every condition joined with AND/OR must be complete:
      a IS NULL AND b IS NULL (not: a AND b IS NULL).

   4. JOIN keeps only matching rows.
      LEFT JOIN keeps all rows from the left table (NULLs where
      no match). Anti-join = LEFT JOIN + WHERE right_key IS NULL.
      Check a NOT NULL key column, never a column that can be NULL.

   5. Window function: FUNC() OVER (PARTITION BY ... ORDER BY ...)
      Like GROUP BY, but every row is kept.
      ROW_NUMBER = numbering, LAG/LEAD = previous/next row value.

   6. CTE: WITH name AS (...) SELECT ... FROM name
      Use it to filter or aggregate results of window functions.

   7. Timestamps: end - start = INTERVAL;
      EXTRACT(EPOCH FROM interval) / 60 = minutes.
      Ranges: ts >= start AND ts < end.

   8. Habits: always ORDER BY when order matters, descriptive aliases
      (AS readings_count), table prefixes (r.temperature),
      round once at the end: ROUND(SUM(x), 2).
   ===================================================================== */


/* =====================================================================
   DAY 1 - SELECT, WHERE, COUNT, GROUP BY, HAVING
   ===================================================================== */

-- ---------------------------------------------------------------------
-- Task 1: How many readings does each machine have?
-- Result: machines 2, 3, 5 -> 24; machine 1 -> 25; machine 4 -> 26
-- Lesson: first attempt grouped by machine_id AND reading_id.
--         reading_id is unique, so every group had exactly 1 row.
--         Group only by what should be unique in the output.
-- ---------------------------------------------------------------------
SELECT machine_id, COUNT(*) AS readings_count
FROM readings
GROUP BY machine_id
ORDER BY machine_id;


-- ---------------------------------------------------------------------
-- Task 5: How many readings have no temperature (NULL),
--         and from which machines?
-- Result: 2 readings, machines 2 and 4 (one each)
-- ---------------------------------------------------------------------
-- My first version (two queries):
SELECT COUNT(*) FROM readings WHERE temperature IS NULL;

SELECT machine_id
FROM readings
WHERE temperature IS NULL
GROUP BY machine_id;

-- Combined into one query:
SELECT machine_id, COUNT(*) AS null_count
FROM readings
WHERE temperature IS NULL
GROUP BY machine_id
ORDER BY machine_id;

-- Bonus: COUNT(*) vs COUNT(temperature) -> 123 vs 121.
-- COUNT(*) counts all rows, COUNT(temperature) skips NULLs.
-- Temperature completeness = 121 / 123 = 98.4% (a data quality metric).
-- Lesson: "COUNT(*) temperature" without AS silently creates an alias
--         named "temperature" -> misleading column header.
SELECT COUNT(*) AS all_rows, COUNT(temperature) AS non_null_temperature
FROM readings;


-- ---------------------------------------------------------------------
-- Task 6: Find duplicate readings (same machine and same ts).
-- Result: machine 1 at 03:00, machine 4 at 12:00 and 13:00
-- Why it matters: distributed systems often deliver data
--         "at-least-once", so duplicate checks are standard
--         data quality tests in pipelines.
-- Lesson: a duplicate is defined in GROUP BY (machine_id + ts),
--         not in WHERE. HAVING keeps only groups with > 1 row.
-- ---------------------------------------------------------------------
SELECT machine_id, ts, COUNT(*) AS readings_count
FROM readings
GROUP BY machine_id, ts
HAVING COUNT(*) > 1
ORDER BY machine_id, ts;


/* =====================================================================
   DAY 2 - JOIN, LEFT JOIN, AVG/MIN/MAX, anti-join
   ===================================================================== */

-- ---------------------------------------------------------------------
-- Warm-up: Which machines had more than 3 alarms?
-- Result: machines 2 and 4 (4 alarms each)
-- ---------------------------------------------------------------------
SELECT machine_id, COUNT(*) AS alarms_count
FROM alarms
GROUP BY machine_id
HAVING COUNT(*) > 3
ORDER BY machine_id;


-- ---------------------------------------------------------------------
-- Task 2: For each machine show name, line and avg / min / max
--         temperature (avg rounded to 1 decimal place).
-- Note: duplicates (task 6) are counted twice here, so averages for
--       Press P-01 and Furnace PZ-04 are slightly off -> see task 11.
-- ---------------------------------------------------------------------
SELECT m.machine_name,
       m.line,
       ROUND(AVG(r.temperature), 1) AS avg_temperature,
       MIN(r.temperature) AS min_temperature,
       MAX(r.temperature) AS max_temperature
FROM readings r
JOIN machines m ON m.machine_id = r.machine_id
GROUP BY m.machine_name, m.line
ORDER BY m.machine_name;


-- ---------------------------------------------------------------------
-- Task 3: Which machines had at least one priority 1 alarm?
--         Each machine only once, with its name.
-- Result: Furnace PZ-04 (2 alarms), Robot R-03 (1 alarm)
-- Alternative: SELECT DISTINCT m.machine_name ... (names only)
-- ---------------------------------------------------------------------
SELECT m.machine_name, COUNT(*) AS alarms_count, a.priority
FROM alarms a
JOIN machines m ON m.machine_id = a.machine_id
WHERE a.priority = 1
GROUP BY a.priority, m.machine_name
ORDER BY m.machine_name;


-- ---------------------------------------------------------------------
-- Task 4: Which machines had NO alarms? (LEFT JOIN, anti-join)
-- Result: Packer PK-05
-- Lesson: check a column that can never be NULL in the right table
--         (its key). "a.ts_end IS NULL" would ALSO return Furnace PZ-04,
--         because it has an alarm that is still active -> wrong result.
-- ---------------------------------------------------------------------
SELECT m.machine_name
FROM machines m
LEFT JOIN alarms a ON a.machine_id = m.machine_id
WHERE a.alarm_id IS NULL
ORDER BY m.machine_name;


/* =====================================================================
   DAY 3 - dates and time, window functions, CTE
   ===================================================================== */

-- ---------------------------------------------------------------------
-- Task 7: Duration of each alarm in minutes, top 5 longest.
-- Result: the longest finished alarm = 76.6 min (alarm 2)
-- Decision: the active alarm (ts_end IS NULL) is excluded explicitly,
--           because it has not ended yet, so its duration is unknown.
-- Business note: the active alarm (A101 overheating on Furnace PZ-04,
--           since 19:26) is in fact the longest one. For a production
--           manager it would be better to flag it instead of dropping
--           it, e.g. COALESCE(ts_end, '2026-11-03 00:00') + is_active.
-- ---------------------------------------------------------------------
SELECT alarm_id,
       ts_start,
       ts_end,
       ROUND(EXTRACT(EPOCH FROM (ts_end - ts_start)) / 60, 2) AS duration_min
FROM alarms
WHERE ts_end IS NOT NULL
ORDER BY duration_min DESC
LIMIT 5;


-- ---------------------------------------------------------------------
-- Task 8: How long did each machine state last? (LEAD)
-- Result: first RUNNING of machine 1 (06:00) lasted 173 min
-- Lesson: machine_states stores EVENTS (only the start of a state,
--         like a signal edge), alarms store INTERVALS (start + end).
--         The end of a state = start of the NEXT state of the same
--         machine -> LEAD(ts) OVER (PARTITION BY machine_id ORDER BY ts).
--         An alias (next_ts) cannot be used in the same SELECT,
--         so the CTE computes it first.
-- The last state of each machine has no duration: there is no next
-- state change in the data (the state is still ongoing or data ends).
-- ---------------------------------------------------------------------
WITH states_with_next AS (
    SELECT machine_id, ts, state,
           LEAD(ts) OVER (PARTITION BY machine_id ORDER BY ts) AS next_ts
    FROM machine_states
)
SELECT machine_id,
       ts,
       state,
       ROUND(EXTRACT(EPOCH FROM (next_ts - ts)) / 60, 2) AS duration_min
FROM states_with_next
ORDER BY machine_id, ts;


-- ---------------------------------------------------------------------
-- Task 9: Total minutes each machine spent in FAULT state.
-- Result: machine 1 -> 472, 2 -> 73, 3 -> 175, 5 -> 448
--         (machine 4 was never in FAULT)
-- Lesson: round once at the end: ROUND(SUM(...)), not SUM(ROUND(...)),
--         otherwise rounding errors add up.
-- TODO (bonus): show machine 4 with 0 minutes (LEFT JOIN + COALESCE).
-- ---------------------------------------------------------------------
WITH states_with_next AS (
    SELECT machine_id, ts, state,
           LEAD(ts) OVER (PARTITION BY machine_id ORDER BY ts) AS next_ts
    FROM machine_states
)
SELECT machine_id,
       ROUND(SUM(EXTRACT(EPOCH FROM (next_ts - ts)) / 60), 2) AS fault_minutes
FROM states_with_next
WHERE state = 'FAULT'
GROUP BY machine_id
ORDER BY machine_id;


-- ---------------------------------------------------------------------
-- Task 10: Top 3 temperature increases vs the previous hour.
-- Result: +13.1 (Furnace PZ-04, 10:00), +6.8 (Robot R-03, 16:00),
--         +6.6 (Injection Molder W-02, 06:00)
-- Lessons: - sort by the ranking column (temp_change), not by time
--          - NULLS LAST: the first reading of each machine has no
--            previous value, so its change is NULL
--          - do NOT filter "temperature IS NOT NULL" in WHERE: WHERE runs
--            before window functions, so LAG would skip the missing hour
--            and compare with 2 hours earlier
-- Style: LAG is written twice; in longer queries compute it once
--        in a CTE and reuse it.
-- ---------------------------------------------------------------------
SELECT machine_id,
       ts,
       temperature,
       LAG(temperature) OVER (PARTITION BY machine_id ORDER BY ts) AS prev_temp,
       temperature - LAG(temperature) OVER (PARTITION BY machine_id ORDER BY ts) AS temp_change
FROM readings
ORDER BY temp_change DESC NULLS LAST
LIMIT 3;


-- ---------------------------------------------------------------------
-- Task 11: Remove duplicates, then recompute average temperature.
-- Pattern: ROW_NUMBER() per (machine_id, ts) -> keep rn = 1.
--          This is the standard deduplication pattern in data
--          engineering (the "Silver layer" in the Medallion architecture).
-- ---------------------------------------------------------------------
-- Step 1: check that every reading is kept exactly once (expected: 120)
WITH numbered AS (
    SELECT reading_id, machine_id, ts, temperature,
           ROW_NUMBER() OVER (PARTITION BY machine_id, ts ORDER BY reading_id) AS rn
    FROM readings
)
SELECT COUNT(*) AS deduplicated_rows
FROM numbered
WHERE rn = 1;

-- Step 2: average temperature on deduplicated data
WITH numbered AS (
    SELECT reading_id, machine_id, ts, temperature,
           ROW_NUMBER() OVER (PARTITION BY machine_id, ts ORDER BY reading_id) AS rn
    FROM readings
)
SELECT machine_id,
       ROUND(AVG(temperature), 2) AS temp_avg
FROM numbered
WHERE rn = 1
GROUP BY machine_id
ORDER BY temp_avg;

/* Step 3: comparison with task 2 (raw data, 2 decimal places)
   machine 1: 45.26 -> 45.15
   machine 4: 80.21 -> 79.65
   TODO: write 2-3 sentences: which machines changed and why,
         and why machine 4 changed much more than machine 1
         (hint: at what time are its duplicates, and what was
         the temperature then?).
*/
