-- ============================================================================
-- DAY 5 HANDS-ON LAB: Monitoring, Maintenance & Locking
-- Intermediate PostgreSQL Course
-- Duration: ~2 hours (instructor-led with exercises)
-- Database: movies_db
--
-- TIMING:
--   Section 1: pg_stat_statements Analysis (30 min) ** HIGH VALUE **
--   Section 2: Locking Scenarios (40 min)
--   Section 3: Maintenance Operations (35 min)
--   Section 4: Wrap-up (5 min)
--   Total: ~110 minutes
--
-- NOTE: Locking demos require TWO terminal/pgAdmin sessions!
-- ============================================================================


-- ============================================================================
-- SECTION 1: pg_stat_statements Analysis (30 min) ** HIGH VALUE **
-- ============================================================================

-- ============================================================================
-- KEY CONCEPT: pg_stat_statements
-- ============================================================================
--
-- pg_stat_statements is PostgreSQL's built-in query profiler.
-- It tracks statistics for EVERY query executed on the database.
--
-- This is "Step 1: Find" in our diagnostic workflow (Day 4):
--   1. FIND slow queries    ← pg_stat_statements (today!)
--   2. DIAGNOSE with EXPLAIN ANALYZE (Day 4)
--   3. FIX with indexes (Day 3) or query rewrites
--
-- Key columns in pg_stat_statements:
--   • query           - The SQL text (normalized, parameters as $1, $2)
--   • calls           - Number of times executed
--   • total_exec_time - Total milliseconds spent (cumulative)
--   • mean_exec_time  - Average milliseconds per call
--   • rows            - Total rows returned
--   • shared_blks_hit - Pages found in cache (fast)
--   • shared_blks_read- Pages read from disk (slow)
--
-- Two ways to find problem queries:
--   • High total_exec_time = burning the most total time
--   • High mean_exec_time = slowest per-call (may need EXPLAIN)
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Demo: Checking pg_stat_statements is Enabled
-- ----------------------------------------------------------------------------

-- Verify the extension is installed
SELECT * FROM pg_available_extensions WHERE name = 'pg_stat_statements';

-- Check if it's loaded
SHOW shared_preload_libraries;

-- View some basic stats
SELECT COUNT(*) FROM pg_stat_statements;


-- ----------------------------------------------------------------------------
-- Demo: Finding Slow Queries
-- ----------------------------------------------------------------------------

-- ============================================================================
-- UNDERSTANDING THE OUTPUT
-- ============================================================================
--
-- Example output:
--
--   query_preview                      | calls | total_ms  | avg_ms | percent | rows
--   -----------------------------------+-------+-----------+--------+---------+------
--   SELECT * FROM ratings WHERE mov... |  5000 | 125000.00 |  25.00 |   45.2  | 50000
--   SELECT m.*, r.rating FROM movie... |   200 |  40000.00 | 200.00 |   14.5  |  2000
--                                        ▲           ▲         ▲         ▲
--                             Ran 5000x  │   125 sec  │   25ms  │   45% of
--                                        │   total    │   each  │   all time
--
-- Query 1: Fast per-call (25ms) but runs so often it dominates
-- Query 2: Slow per-call (200ms) - good candidate for EXPLAIN ANALYZE
-- ============================================================================

-- Top 10 queries by total execution time
SELECT
    substring(query, 1, 60) AS query_preview,
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    round((100 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 2) AS percent_total,
    rows
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'  -- Exclude our monitoring queries
ORDER BY total_exec_time DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Demo: Finding Frequently Called Queries
-- ----------------------------------------------------------------------------

-- Most frequently executed queries
SELECT
    substring(query, 1, 60) AS query_preview,
    calls,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    rows / NULLIF(calls, 0) AS avg_rows
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY calls DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Demo: Queries with High I/O
-- ----------------------------------------------------------------------------

-- ============================================================================
-- UNDERSTANDING CACHE HIT RATE
-- ============================================================================
--
-- PostgreSQL caches data pages in shared_buffers (memory).
--
--   shared_blks_hit  = Pages found in memory (fast, ~0.1ms)
--   shared_blks_read = Pages loaded from disk (slow, ~1-10ms)
--
-- Cache hit rate = hit / (hit + read) × 100
--
-- What's a good cache hit rate?
--   • 99%+ = Excellent (almost everything in memory)
--   • 95-99% = Good (typical for well-tuned systems)
--   • <90% = Investigate (data too large for cache, or bad access patterns)
--
-- Low cache hit on a specific query might mean:
--   • Missing index (scanning lots of pages)
--   • Query returns too much data
--   • Data accessed rarely (not cached)
-- ============================================================================

-- Queries reading the most data
SELECT
    substring(query, 1, 60) AS query_preview,
    calls,
    shared_blks_hit + shared_blks_read AS total_blocks,
    round(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 2) AS cache_hit_pct
FROM pg_stat_statements
WHERE shared_blks_hit + shared_blks_read > 0
ORDER BY shared_blks_read DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Exercise 1: Your Turn - Query Analysis
-- Time: 15 minutes
-- ----------------------------------------------------------------------------

-- ** ESSENTIAL ** Exercise 1a: Find the top 5 queries that return the most rows on average

-- YOUR CODE HERE:



-- (Optional) Exercise 1b: Find queries with less than 90% cache hit rate
-- These might benefit from indexing or more shared_buffers

-- YOUR CODE HERE:



-- (Optional) Exercise 1c: Calculate the total time spent in the top 10 queries
-- as a percentage of all query time

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 2: Locking Scenarios (40 min)
-- ============================================================================

/*
IMPORTANT: This section requires TWO database sessions!

Option 1: Two pgAdmin query windows
Option 2: Two terminal windows with psql
Option 3: pgAdmin + terminal

Label them SESSION A and SESSION B
*/

-- ============================================================================
-- KEY CONCEPT: WHY LOCKING MATTERS
-- ============================================================================
--
-- PostgreSQL uses locks to prevent data corruption when multiple
-- connections access the same data simultaneously.
--
-- Common symptoms of locking problems:
--   • Queries "hang" and don't return
--   • Application timeouts
--   • Deadlock errors in logs
--   • "idle in transaction" connections piling up
--
-- Key insight: Locks are held until COMMIT or ROLLBACK
--   → Long transactions = long lock hold times = more contention
--
-- Lock modes (simplified):
--   • ROW EXCLUSIVE  - Normal INSERT/UPDATE/DELETE (rarely conflicts)
--   • FOR UPDATE     - Explicit row lock (blocks other FOR UPDATE)
--   • ACCESS EXCLUSIVE - DDL like ALTER TABLE (blocks everything!)
--
-- Most applications: Row-level locks rarely conflict.
-- Problems happen with: Long transactions, explicit FOR UPDATE, DDL.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Demo: Viewing Current Locks
-- ----------------------------------------------------------------------------

-- ============================================================================
-- UNDERSTANDING pg_locks OUTPUT
-- ============================================================================
--
--   locktype | relation | mode           | granted | pid
--   ---------+----------+----------------+---------+-----
--   relation | movies   | RowExclusiveLock| t       | 1234
--   relation | movies   | RowExclusiveLock| f       | 5678  ← Waiting!
--                                          ▲
--                          granted = false means this process is BLOCKED
--
-- Key columns:
--   • relation   - Which table is locked
--   • mode       - Type of lock (RowExclusive, AccessExclusive, etc.)
--   • granted    - true = has the lock, false = waiting for it
--   • pid        - Process ID (use to find query in pg_stat_activity)
-- ============================================================================

-- See all current locks
SELECT
    locktype,
    relation::regclass,
    mode,
    granted,
    pid
FROM pg_locks
WHERE relation IS NOT NULL
ORDER BY relation;

-- See who's waiting for locks
SELECT
    pid,
    wait_event_type,
    wait_event,
    state,
    substring(query, 1, 40) AS query
FROM pg_stat_activity
WHERE wait_event_type = 'Lock';


-- ----------------------------------------------------------------------------
-- Demo: Row-Level Lock Conflict
-- ----------------------------------------------------------------------------

/*
=== SESSION A ===
*/
-- Start transaction and update a row
BEGIN;
UPDATE movies SET title = title || ' (Updated)' WHERE movie_id = 1;
-- DON'T COMMIT YET!

/*
=== SESSION B ===
*/
-- Try to update the same row - THIS WILL BLOCK!
UPDATE movies SET title = title || ' (Also Updated)' WHERE movie_id = 1;
-- Session B is now waiting...

/*
=== SESSION A (or new session) ===
*/
-- See the blocking situation
SELECT
    blocked.pid AS blocked_pid,
    blocked.query AS blocked_query,
    blocking.pid AS blocking_pid,
    blocking.query AS blocking_query,
    blocked.wait_event
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid != blocked.pid
WHERE blocked.wait_event_type = 'Lock'
  AND blocked.state = 'active';

/*
=== SESSION A ===
*/
-- Release the lock
COMMIT;

/*
=== SESSION B ===
*/
-- Now session B completes!
-- Rollback to restore original title
ROLLBACK;


-- ----------------------------------------------------------------------------
-- Demo: Detecting Idle-in-Transaction
-- ----------------------------------------------------------------------------

-- ============================================================================
-- WHY "IDLE IN TRANSACTION" IS DANGEROUS
-- ============================================================================
--
-- "idle in transaction" means:
--   • A connection ran BEGIN
--   • Did some work
--   • Is now sitting there doing nothing
--   • But hasn't COMMITted or ROLLBACKed
--
-- Why is this bad?
--   1. Holds locks - other queries may be blocked waiting
--   2. Prevents VACUUM - dead tuples can't be cleaned up
--   3. Wastes connections - connection pool exhaustion
--   4. Can cause transaction ID wraparound (extreme cases)
--
-- Common causes:
--   • Application bug (forgot to commit)
--   • User opened transaction in pgAdmin and walked away
--   • Connection pool not releasing properly
--
-- Fix: Find and kill these connections, then fix the application code
-- ============================================================================

-- Find connections that started a transaction but are doing nothing
SELECT
    pid,
    state,
    xact_start,
    NOW() - xact_start AS transaction_duration,
    substring(query, 1, 50) AS last_query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND xact_start < NOW() - INTERVAL '1 minute';


-- ----------------------------------------------------------------------------
-- Demo: Finding Lock Chains
-- ----------------------------------------------------------------------------

-- Who is blocking whom? (shows chain of blocking)
SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.query AS blocked_query,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.query AS blocking_query
FROM pg_locks blocked_locks
JOIN pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;


-- ----------------------------------------------------------------------------
-- Exercise 2: Your Turn - Locking
-- Time: 10 minutes
-- ----------------------------------------------------------------------------

-- ** ESSENTIAL ** Exercise 2a: Create a lock conflict scenario
-- In SESSION A: Start a transaction and DELETE a rating
-- In SESSION B: Try to UPDATE the same rating
-- In SESSION A (or C): Query to see the blocked process

/*
Your commands for SESSION A:
*/



/*
Your commands for SESSION B:
*/



/*
Query to see the blocking:
*/



-- (Optional) Exercise 2b: SELECT FOR UPDATE
-- This explicitly locks rows for later update

/*
SESSION A:
*/
BEGIN;
SELECT * FROM users WHERE user_id = 1 FOR UPDATE;
-- This locks the row

/*
SESSION B:
*/
-- Try to also lock it
SELECT * FROM users WHERE user_id = 1 FOR UPDATE;
-- What happens?

/*
SESSION A:
*/
COMMIT;


-- (Optional) Exercise 2c: Use NOWAIT to fail fast instead of waiting

/*
SESSION A:
*/
BEGIN;
SELECT * FROM users WHERE user_id = 2 FOR UPDATE;

/*
SESSION B:
*/
-- This will error immediately instead of waiting
SELECT * FROM users WHERE user_id = 2 FOR UPDATE NOWAIT;


-- ----------------------------------------------------------------------------
-- Demo: Deadlock Scenario (Instructor-led demo)
-- ----------------------------------------------------------------------------

/*
This demonstrates how deadlocks happen - both transactions block each other.
PostgreSQL will detect and kill one transaction automatically.

SESSION A:
*/
BEGIN;
UPDATE users SET username = username WHERE user_id = 1;
-- Now try to update user 2 (after SESSION B has locked it)
-- UPDATE users SET username = username WHERE user_id = 2;

/*
SESSION B:
*/
BEGIN;
UPDATE users SET username = username WHERE user_id = 2;
-- Now try to update user 1 (SESSION A has it locked)
-- UPDATE users SET username = username WHERE user_id = 1;
-- One session will get: ERROR: deadlock detected

-- ============================================================================
-- WHAT A DEADLOCK ERROR LOOKS LIKE
-- ============================================================================
--
-- ERROR:  deadlock detected
-- DETAIL: Process 12345 waits for ShareLock on transaction 67890;
--         blocked by process 11111.
--         Process 11111 waits for ShareLock on transaction 12345;
--         blocked by process 12345.
-- HINT:  See server log for query details.
-- CONTEXT: while updating tuple (0,1) in relation "users"
--
-- PostgreSQL automatically:
--   1. Detects the circular wait
--   2. Picks one transaction to abort (victim)
--   3. Rolls back the victim
--   4. Other transaction proceeds
--
-- Your application should: Catch this error and retry the transaction
-- ============================================================================

/*
IMPORTANT: Notice the error message includes which transaction was rolled back.
Prevention: Always access tables/rows in the same order across all code paths.
*/


-- ----------------------------------------------------------------------------
-- Demo: Isolation Levels in Action
-- ----------------------------------------------------------------------------

-- Check current isolation level
SHOW transaction_isolation;

-- Most applications use READ COMMITTED (default) - this is usually correct
-- Only escalate if you have a specific need

-- Example: REPEATABLE READ prevents non-repeatable reads
/*
SESSION A:
*/
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT * FROM movies WHERE movie_id = 1;
-- Keep transaction open, note the title

/*
SESSION B:
*/
UPDATE movies SET title = title || ' (Modified)' WHERE movie_id = 1;
COMMIT;

/*
SESSION A (continued):
*/
-- In REPEATABLE READ, you see the SAME data as before (snapshot)
SELECT * FROM movies WHERE movie_id = 1;
ROLLBACK;

-- Reset any changes
UPDATE movies SET title = REPLACE(title, ' (Modified)', '') WHERE title LIKE '% (Modified)';


-- ============================================================================
-- SECTION 3: Maintenance Operations (35 min)
-- ============================================================================

-- ============================================================================
-- KEY CONCEPT: VACUUM AND DEAD TUPLES
-- ============================================================================
--
-- PostgreSQL's MVCC model keeps old row versions around:
--   • UPDATE creates new row version, old one becomes "dead tuple"
--   • DELETE marks row as dead, doesn't remove it
--
-- Why? Other transactions might still need to see the old data.
--
-- VACUUM cleans up dead tuples:
--   • Marks space as reusable (doesn't shrink file)
--   • Prevents "table bloat" (wasted space)
--   • Updates visibility map (enables Index Only Scan)
--
-- Autovacuum runs automatically, but after bulk operations you may want
-- to run VACUUM manually for immediate cleanup.
--
-- VACUUM vs VACUUM FULL:
--   • VACUUM        - Marks space reusable, doesn't lock table
--   • VACUUM FULL   - Rewrites table, reclaims disk space, LOCKS TABLE!
--                     Only use VACUUM FULL for severe bloat.
-- ============================================================================


-- ============================================================================
-- KEY CONCEPT: pg_stat_user_tables COLUMNS
-- ============================================================================
--
--   relname        - Table name
--   n_live_tup     - Estimated live rows
--   n_dead_tup     - Estimated dead rows (need vacuum)
--   last_vacuum    - Last manual VACUUM
--   last_autovacuum- Last automatic VACUUM
--   last_analyze   - Last manual ANALYZE
--   last_autoanalyze - Last automatic ANALYZE
--
-- High n_dead_tup / n_live_tup ratio = table needs vacuum
-- NULL last_analyze after bulk load = run ANALYZE manually
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Demo: Checking Table Statistics
-- ----------------------------------------------------------------------------

-- When were tables last vacuumed and analyzed?
SELECT
    relname,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    n_live_tup,
    n_dead_tup,
    round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;


-- ----------------------------------------------------------------------------
-- Demo: Creating Dead Tuples
-- ----------------------------------------------------------------------------

-- Let's create some dead tuples to see VACUUM in action
BEGIN;
-- Update a bunch of rows (creates dead tuples)
UPDATE ratings SET rating = rating WHERE movie_id = 1;
COMMIT;

-- Check dead tuples increased
SELECT relname, n_dead_tup, n_live_tup
FROM pg_stat_user_tables
WHERE relname = 'ratings';


-- ----------------------------------------------------------------------------
-- Demo: Running VACUUM
-- ----------------------------------------------------------------------------

-- Basic vacuum
VACUUM ratings;

-- Vacuum with verbose output
VACUUM VERBOSE ratings;

-- Check dead tuples are cleaned
SELECT relname, n_dead_tup, n_live_tup
FROM pg_stat_user_tables
WHERE relname = 'ratings';


-- ----------------------------------------------------------------------------
-- Demo: Running ANALYZE
-- ----------------------------------------------------------------------------

-- Update statistics for one table
ANALYZE ratings;

-- Check when it was analyzed
SELECT relname, last_analyze
FROM pg_stat_user_tables
WHERE relname = 'ratings';

-- ============================================================================
-- UNDERSTANDING pg_stats OUTPUT
-- ============================================================================
--
-- pg_stats shows what ANALYZE collected. This is what the planner uses!
--
--   attname          - Column name
--   n_distinct       - Estimated distinct values
--                      Positive = actual count, Negative = fraction of rows
--                      e.g., -0.5 means ~50% of rows are distinct
--   most_common_vals - Array of most frequent values
--   most_common_freqs- Frequency of each (0.0 to 1.0)
--
-- Example output for 'rating' column:
--   n_distinct: 10 (ratings 1-10)
--   most_common_vals: {7,8,6,9,5}
--   most_common_freqs: {0.22, 0.18, 0.15, 0.12, 0.10}
--                       ▲
--                       22% of ratings are 7
--
-- This helps the planner estimate: "WHERE rating = 7" returns ~22% of rows
-- ============================================================================

-- See the statistics Postgres collected
SELECT
    attname,
    n_distinct,
    most_common_vals,
    most_common_freqs
FROM pg_stats
WHERE tablename = 'ratings'
  AND attname = 'rating';


-- ----------------------------------------------------------------------------
-- Demo: Table Bloat Estimation
-- ----------------------------------------------------------------------------

-- Estimate table bloat (simplified version)
SELECT
    relname,
    pg_size_pretty(pg_relation_size(relid)) AS size,
    n_live_tup,
    n_dead_tup,
    CASE WHEN n_live_tup > 0 THEN
        round(100.0 * n_dead_tup / n_live_tup, 2)
    ELSE 0 END AS dead_ratio
FROM pg_stat_user_tables
WHERE n_live_tup > 1000
ORDER BY n_dead_tup DESC;


-- ----------------------------------------------------------------------------
-- Exercise 3: Your Turn - Maintenance
-- Time: 20 minutes
-- ----------------------------------------------------------------------------

-- ** ESSENTIAL ** Exercise 3a: Find the table with the most dead tuples

-- YOUR CODE HERE:



-- (Optional) Exercise 3b: Check the statistics for the 'movies' table
-- What's the most common release_year?

-- YOUR CODE HERE:



-- (Optional) Exercise 3c: Run VACUUM ANALYZE on a table and verify it worked

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 4: Wrap-up & Key Takeaways (5 min)
-- ============================================================================

/*
KEY TAKEAWAYS:

1. pg_stat_statements is your query profiler
   - Find slow queries by total_exec_time
   - Find hot queries by calls
   - Reset periodically for fresh data

2. pg_stat_activity shows what's happening NOW
   - Find blocked queries
   - Find idle-in-transaction problems
   - Use pg_cancel_backend/pg_terminate_backend carefully

3. Locking best practices:
   - Keep transactions short
   - Access resources in consistent order
   - Use FOR UPDATE NOWAIT or SKIP LOCKED when appropriate
   - Monitor with pg_locks and pg_stat_activity

4. Maintenance:
   - Autovacuum handles most cases
   - Run ANALYZE after bulk loads
   - Monitor dead tuples for bloat
   - VACUUM FULL only when really needed (locks table)

TOMORROW: Architecture and performance tuning!
*/


-- ============================================================================
-- SOLUTIONS (For Instructor Reference)
-- ============================================================================

/*
-- Solution 1a: Top 5 by average rows returned
SELECT
    substring(query, 1, 60) AS query_preview,
    calls,
    rows / NULLIF(calls, 0) AS avg_rows
FROM pg_stat_statements
ORDER BY rows / NULLIF(calls, 0) DESC
LIMIT 5;

-- Solution 1b: Low cache hit rate
SELECT
    substring(query, 1, 60) AS query_preview,
    round(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 2) AS cache_hit_pct
FROM pg_stat_statements
WHERE shared_blks_hit + shared_blks_read > 100
  AND 100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0) < 90
ORDER BY cache_hit_pct;

-- Solution 1c: Top 10 percentage
WITH total AS (
    SELECT SUM(total_exec_time) AS total_time FROM pg_stat_statements
),
top10 AS (
    SELECT SUM(total_exec_time) AS top10_time
    FROM (
        SELECT total_exec_time
        FROM pg_stat_statements
        ORDER BY total_exec_time DESC
        LIMIT 10
    ) t
)
SELECT round(100.0 * top10_time / total_time, 2) AS top10_percent
FROM total, top10;

-- Solution 2a: Lock conflict
-- SESSION A: BEGIN; DELETE FROM ratings WHERE rating_id = 1;
-- SESSION B: UPDATE ratings SET rating = 5 WHERE rating_id = 1;
-- Query the blocking as shown in demos

-- Solution 3a: Most dead tuples
SELECT relname, n_dead_tup
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 1;

-- Solution 3b: Most common release_year
SELECT most_common_vals
FROM pg_stats
WHERE tablename = 'movies' AND attname = 'release_year';

-- Solution 3c: VACUUM ANALYZE verification
VACUUM ANALYZE movies;
SELECT relname, last_vacuum, last_analyze
FROM pg_stat_user_tables
WHERE relname = 'movies';
*/
