-- ============================================================================
-- DAY 6 HANDS-ON LAB: Architecture & Performance Tuning
-- Intermediate PostgreSQL Course
-- Duration: ~1 hour 50 min (instructor-led with exercises)
-- Database: movies_db
--
-- TIMING:
--   Section 1: Exploring Architecture (25 min)
--   Section 2: Memory and Caching (25 min)
--   Section 3: Final Challenge - Full Diagnostic (50 min)
--   Section 4: Course Wrap-up (10 min)
--   ** SURVEY: 10 min reserved for student evaluations **
--   Total: ~110 minutes + 10 min survey
--
-- TABLE SIZES (approximate):
--   movies           ~500 rows      (small - often uses Seq Scan)
--   people           ~300 rows      (small)
--   users            ~5,000 rows    (medium)
--   genres           15 rows        (very small)
--   movie_genres     ~1,000 rows    (1-4 per movie)
--   movie_cast       ~3,000 rows    (3-8 per movie)
--   ratings          ~50,000+ rows  (large - good for index demos)
--   watchlist        ~75,000 rows   (large)
--   popularity_cache 500 rows       (one per movie)
-- ============================================================================


-- ============================================================================
-- SECTION 1: Exploring Architecture (30 min)
-- ============================================================================

-- ============================================================================
-- KEY CONCEPT: PostgreSQL Memory Settings
-- ============================================================================
--
-- Shared Memory (shared by all connections):
--   shared_buffers     - Main data cache (start with 25% of RAM)
--   wal_buffers        - Write-ahead log buffer
--
-- Per-Connection Memory (multiplied by number of connections!):
--   work_mem           - Memory for sorts, hashes, joins (default 4MB)
--   maintenance_work_mem - Memory for VACUUM, CREATE INDEX
--
-- IMPORTANT: work_mem is per-OPERATION, not per-query!
--   A complex query with 5 sorts could use 5 × work_mem
--   100 connections × 5 operations × 64MB work_mem = 32GB!
--
-- Context values (from pg_settings):
--   'postmaster' = requires restart to change
--   'user' = can change per-session with SET
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo: PostgreSQL Configuration
-- ----------------------------------------------------------------------------

-- View all current settings
SELECT name, setting, unit, context, short_desc
FROM pg_settings
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'random_page_cost',
    'seq_page_cost',
    'max_connections'
)
ORDER BY name;


-- ----------------------------------------------------------------------------
-- Demo: Database Size Information
-- ----------------------------------------------------------------------------

-- Database size
SELECT
    datname,
    pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
WHERE datname = current_database();

-- Table sizes
SELECT
    relname AS table_name,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
    pg_size_pretty(pg_relation_size(relid)) AS data_size,
    pg_size_pretty(pg_indexes_size(relid)) AS index_size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;


-- ----------------------------------------------------------------------------
-- Demo: Process Information
-- ----------------------------------------------------------------------------

-- Current connections
SELECT
    count(*) AS total_connections,
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle,
    count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_tx
FROM pg_stat_activity
WHERE backend_type = 'client backend';

-- Background workers
SELECT pid, backend_type, state
FROM pg_stat_activity
WHERE backend_type != 'client backend';


-- ----------------------------------------------------------------------------
-- Demo: WAL Information
-- ----------------------------------------------------------------------------

-- Current WAL position
SELECT pg_current_wal_lsn();

-- WAL statistics
SELECT * FROM pg_stat_wal;


-- ----------------------------------------------------------------------------
-- Exercise 1: Your Turn - Architecture Exploration
-- Time: 15 minutes
-- ----------------------------------------------------------------------------

-- ** ESSENTIAL ** Exercise 1a: Find the total size of all tables and indexes combined
-- Hint: Use pg_stat_user_tables and pg_total_relation_size()

-- YOUR CODE HERE:



-- (Optional) Exercise 1b: What is the current value of random_page_cost?
-- Is it appropriate for SSD storage?

-- YOUR CODE HERE:



-- (Optional) Exercise 1c: How many backend processes are currently running?
-- What types are they?

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 2: Memory and Caching (30 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo: Buffer Cache Hit Ratio
-- ----------------------------------------------------------------------------

-- Overall cache hit ratio
SELECT
    sum(blks_hit) AS hits,
    sum(blks_read) AS reads,
    round(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2) AS hit_ratio
FROM pg_stat_database
WHERE datname = current_database();


-- ----------------------------------------------------------------------------
-- Demo: Per-Table Cache Statistics
-- ----------------------------------------------------------------------------

-- Which tables have low cache hit rates?
SELECT
    relname,
    heap_blks_hit,
    heap_blks_read,
    CASE
        WHEN heap_blks_hit + heap_blks_read = 0 THEN 100
        ELSE round(100.0 * heap_blks_hit / (heap_blks_hit + heap_blks_read), 2)
    END AS cache_hit_pct
FROM pg_statio_user_tables
WHERE heap_blks_hit + heap_blks_read > 100
ORDER BY cache_hit_pct;


-- ----------------------------------------------------------------------------
-- Demo: Checking work_mem Usage
-- ----------------------------------------------------------------------------

-- See if sorts are spilling to disk
-- Run a query that needs sorting
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ratings ORDER BY rating DESC;

-- Look for "Sort Method: external merge"
-- That means work_mem was too small


-- ----------------------------------------------------------------------------
-- Demo: Testing work_mem Impact
-- ----------------------------------------------------------------------------

-- Current work_mem
SHOW work_mem;

-- Increase for this session
SET work_mem = '64MB';

-- Run the same query
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM ratings ORDER BY rating DESC;

-- Did it change from external merge to quicksort?

-- Reset to default
RESET work_mem;


-- ----------------------------------------------------------------------------
-- Exercise 2: Your Turn - Memory Analysis
-- Time: 15 minutes
-- ----------------------------------------------------------------------------

-- (Optional) Exercise 2a: What's the cache hit ratio for the 'ratings' table specifically?

-- YOUR CODE HERE:



-- (Optional) Exercise 2b: Run a complex query and check if it uses disk for sorting
-- Try with default work_mem, then increase it

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    movie_id,
    AVG(rating) as avg_rating,
    COUNT(*) as cnt
FROM ratings
GROUP BY movie_id
ORDER BY avg_rating DESC;

-- Does increasing work_mem change the plan?
-- YOUR CODE HERE:



-- (Optional) Exercise 2c: Check the index hit ratio for all indexes

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 3: Final Challenge - Full Diagnostic (50 min) ** ESSENTIAL **
-- ============================================================================

-- ============================================================================
-- KEY CONCEPT: The Diagnostic Workflow
-- ============================================================================
--
-- This is the workflow you'll use on the job:
--
--   ┌─────────────────────────────────────────────────────────────────────┐
--   │  1. FIND        →  2. DIAGNOSE     →  3. FIX        →  4. VERIFY   │
--   │  pg_stat_          EXPLAIN             Add index,       Re-run      │
--   │  statements         ANALYZE             ANALYZE,         EXPLAIN     │
--   │                                         rewrite                      │
--   └─────────────────────────────────────────────────────────────────────┘
--
-- What to look for in EXPLAIN ANALYZE:
--   • Seq Scan on large table - needs index?
--   • rows=100 (actual rows=50000) - stale statistics, run ANALYZE
--   • Sort Method: external merge - work_mem too low
--   • Nested Loop with high row counts - might need Hash Join
--
-- Common fixes:
--   • CREATE INDEX on filtered/joined columns
--   • ANALYZE table_name to refresh statistics
--   • Rewrite query (avoid correlated subqueries, leading wildcards)
-- ============================================================================

/*
** THIS IS THE CAPSTONE EXERCISE - COMPLETE ALL STEPS **

SCENARIO: You're troubleshooting a slow database.
First, use pg_stat_statements to FIND the slow queries.
Then, use EXPLAIN ANALYZE to DIAGNOSE why they're slow.
Finally, FIX them and VERIFY the improvement.
*/


-- ============================================================================
-- STEP 0: RESET THE ENVIRONMENT (run this first!)
-- ============================================================================

-- Drop any indexes created during previous exercises so everyone starts fresh.
-- This ensures you'll see Seq Scans where expected.

DROP INDEX IF EXISTS idx_users_email;
DROP INDEX IF EXISTS idx_ratings_movie_id;
DROP INDEX IF EXISTS idx_ratings_rated_at;
DROP INDEX IF EXISTS idx_movies_streaming;

-- Reset pg_stat_statements so we start with clean data
SELECT pg_stat_statements_reset();

-- Refresh table statistics
ANALYZE users;
ANALYZE ratings;
ANALYZE movies;
ANALYZE watchlist;


-- ============================================================================
-- STEP 1: SEED SLOW QUERIES
-- ============================================================================

-- Run the seed script to generate slow query data:
--   \i datasets/seed_slow_queries.sql
--
-- This runs various slow queries so pg_stat_statements has data to analyze.


-- ============================================================================
-- STEP 2: FIND - Use pg_stat_statements
-- ============================================================================

-- Find the slowest queries by total execution time
SELECT
    substring(query, 1, 60) AS query_preview,
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY total_exec_time DESC
LIMIT 10;

-- What patterns do you see? Which queries are taking the most time?
-- YOUR NOTES:



-- ============================================================================
-- STEP 3: DIAGNOSE & FIX - Work through these problem queries
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Problem Query 1: Slow user lookup
-- ----------------------------------------------------------------------------

-- "Finding users by email is really slow"
EXPLAIN ANALYZE
SELECT * FROM users WHERE email = 'user500@example.com';

-- What's the problem?
-- YOUR DIAGNOSIS:


-- What's the fix?
-- YOUR CODE HERE:


-- Verify improvement:
-- YOUR CODE HERE:



-- ----------------------------------------------------------------------------
-- Problem Query 2: Slow rating aggregation
-- ----------------------------------------------------------------------------

-- "Getting average ratings per movie takes forever"
EXPLAIN ANALYZE
SELECT movie_id, AVG(rating), COUNT(*)
FROM ratings
GROUP BY movie_id
ORDER BY AVG(rating) DESC
LIMIT 20;

-- What's the problem? (Check: Seq Scan? Sort method?)
-- YOUR DIAGNOSIS:


-- What's the fix?
-- YOUR CODE HERE:


-- Verify improvement:
-- YOUR CODE HERE:



-- ----------------------------------------------------------------------------
-- Problem Query 3: Slow JSONB lookup
-- ----------------------------------------------------------------------------

-- "Searching movies by streaming platform is slow"
-- NOTE: movies table is small (500 rows), so Postgres may choose Seq Scan anyway.
-- The expression index becomes important as the table grows.
EXPLAIN ANALYZE
SELECT title, metadata->>'streaming' AS platform
FROM movies
WHERE metadata->>'streaming' = 'Streamly';

-- What's the problem?
-- YOUR DIAGNOSIS:


-- What's the fix? (Hint: What kind of index helps JSONB expressions?)
-- YOUR CODE HERE:


-- Verify improvement:
-- YOUR CODE HERE:




-- ----------------------------------------------------------------------------
-- Problem Query 4: Slow date range query
-- ----------------------------------------------------------------------------

-- "Finding ratings from a specific month is slow"
EXPLAIN ANALYZE
SELECT * FROM ratings
WHERE rated_at >= '2024-06-01' AND rated_at < '2024-07-01';

-- What's the problem?
-- YOUR DIAGNOSIS:


-- What's the fix? (Hint: What column is being filtered?)
-- YOUR CODE HERE:


-- Verify improvement:
-- YOUR CODE HERE:



-- ----------------------------------------------------------------------------
-- Bonus: Check Table Statistics
-- ----------------------------------------------------------------------------

-- Are statistics fresh? (Check last_analyze column)
SELECT relname, last_analyze, n_live_tup
FROM pg_stat_user_tables
ORDER BY last_analyze NULLS FIRST;




-- ----------------------------------------------------------------------------
-- (Optional) Bonus Challenge: Lock Investigation
-- ----------------------------------------------------------------------------

-- Check if there are any blocking queries (joins through pg_locks to find actual blocker)
SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.query AS blocked_query,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.query AS blocking_query
FROM pg_locks blocked_locks
JOIN pg_stat_activity blocked_activity
    ON blocked_activity.pid = blocked_locks.pid
JOIN pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_stat_activity blocking_activity
    ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted
  AND blocking_locks.granted;

-- Check for long-running transactions
SELECT
    pid,
    NOW() - xact_start AS duration,
    state,
    substring(query, 1, 50)
FROM pg_stat_activity
WHERE state IN ('active', 'idle in transaction')
  AND xact_start < NOW() - INTERVAL '5 minutes';


-- ============================================================================
-- SECTION 4: Course Wrap-up (10 min)
-- ============================================================================

/*
=== 6-DAY COURSE SUMMARY ===

DAY 1: Advanced Data Types
- JSONB for flexible schema
- Arrays for multi-value fields
- HSTORE for simple key-value
- Full-text search basics

DAY 2: Functions & Triggers
- PL/pgSQL function structure
- Parameters, variables, control flow
- EXCEPTION blocks for error handling
- Triggers for automatic actions

DAY 3: Indexing Strategies
- B-Tree for equality and ranges
- GIN for arrays, JSONB, full-text
- BRIN for large ordered data
- Monitoring index usage

DAY 4: Query Analysis
- EXPLAIN and EXPLAIN ANALYZE
- Reading execution plans
- Finding bottlenecks
- Common fixes

DAY 5: Monitoring & Locking
- pg_stat_statements for query profiling
- pg_stat_activity for live monitoring
- Lock types and contention
- VACUUM and ANALYZE

DAY 6: Architecture & Tuning
- PostgreSQL process model
- Memory configuration
- Cost-based optimizer
- Performance checklist


=== THE WORKFLOW ===

1. FIND: Use pg_stat_statements to identify slow queries
2. DIAGNOSE: Use EXPLAIN ANALYZE to understand why
3. FIX: Add index, update stats, rewrite query
4. VERIFY: Re-run EXPLAIN to confirm improvement
5. MONITOR: Watch for regressions


=== RESOURCES ===

PostgreSQL Docs: postgresql.org/docs/current/
Books: "PostgreSQL 14 Internals" (free), "The Art of PostgreSQL"
Tools: pgBadger, auto_explain, pg_stat_statements


Thank you for attending! Questions?
*/


-- ============================================================================
-- SOLUTIONS (For Instructor Reference)
-- ============================================================================

/*
-- Solution 1a: Total size
SELECT pg_size_pretty(sum(pg_total_relation_size(relid)))
FROM pg_stat_user_tables;

-- Solution 1b: random_page_cost
SHOW random_page_cost;
-- Default 4.0 is for spinning disk
-- For SSD, should be ~1.1-2.0

-- Solution 1c: Backend processes
SELECT backend_type, count(*)
FROM pg_stat_activity
GROUP BY backend_type;

-- Solution 2a: Ratings cache hit ratio
SELECT
    relname,
    round(100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0), 2)
FROM pg_statio_user_tables
WHERE relname = 'ratings';

-- Solution 2b: work_mem testing
SET work_mem = '128MB';
-- Re-run query and compare Sort Method

-- Solution 2c: Index hit ratio
SELECT
    indexrelname,
    idx_blks_hit,
    idx_blks_read,
    CASE WHEN idx_blks_hit + idx_blks_read = 0 THEN 100
         ELSE round(100.0 * idx_blks_hit / (idx_blks_hit + idx_blks_read), 2)
    END AS hit_ratio
FROM pg_statio_user_indexes
WHERE idx_blks_hit + idx_blks_read > 0
ORDER BY hit_ratio;

-- Capstone Problem Query Solutions:

-- Problem 1: Slow user lookup
-- Problem: Seq Scan on users table
-- Fix:
CREATE INDEX idx_users_email ON users(email);

-- Problem 2: Slow rating aggregation
-- Problem: Seq Scan on ratings, possibly disk sort
-- Fix: Index on movie_id helps the GROUP BY
CREATE INDEX idx_ratings_movie_id ON ratings(movie_id);
-- Also try: SET work_mem = '64MB'; if sort spills to disk

-- Problem 3: Slow JSONB lookup
-- Problem: Seq Scan, can't use regular index on JSONB expression
-- Fix: Expression index on the JSONB path
CREATE INDEX idx_movies_streaming ON movies((metadata->>'streaming'));

-- Problem 4: Slow date range query
-- Problem: Seq Scan on ratings (57K rows), filtering by rated_at
-- Fix: Index on the date column
CREATE INDEX idx_ratings_rated_at ON ratings(rated_at);
*/
