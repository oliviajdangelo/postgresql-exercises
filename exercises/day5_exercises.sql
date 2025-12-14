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

-- ----------------------------------------------------------------------------
-- Demo: Viewing Current Locks
-- ----------------------------------------------------------------------------

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
