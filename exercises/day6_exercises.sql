-- ============================================================================
-- DAY 6 HANDS-ON LAB: Architecture & Performance Tuning
-- Intermediate PostgreSQL Course
-- Duration: ~1 hour 50 min (instructor-led with exercises)
-- Database: movies_db
--
-- TIMING:
--   Section 1: Final Challenge - Capstone (50 min) ** ESSENTIAL **
--   Section 2: Exploring Architecture (25 min)
--   Section 3: Memory and Caching (25 min)
--   Student Survey (10 min)
--   Total: ~110 minutes
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
--
-- ******************************************************************************
-- **  REMINDER: Student survey at end of class!                               **
-- ******************************************************************************
-- ============================================================================


-- ============================================================================
-- SECTION 1: Final Challenge - Capstone (50 min) ** ESSENTIAL **
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
** THIS IS THE CAPSTONE EXERCISE **

SCENARIO: You inherit a "slow" database and need to fix it.

Follow the diagnostic workflow from Days 4-5:
  1. FIND    - Use pg_stat_statements to identify slow queries
  2. DIAGNOSE - Use EXPLAIN ANALYZE to understand WHY they're slow
  3. FIX     - Add index, refresh stats, or rewrite query
  4. VERIFY  - Confirm the improvement
*/


-- ============================================================================
-- STEP 1: RESET THE ENVIRONMENT
-- ============================================================================

-- Drop ALL custom indexes so everyone starts fresh.
DO $$
DECLARE
    idx RECORD;
BEGIN
    FOR idx IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname NOT LIKE '%_pkey'
          AND indexname NOT LIKE '%_key'
    LOOP
        EXECUTE 'DROP INDEX IF EXISTS ' || idx.indexname;
        RAISE NOTICE 'Dropped index: %', idx.indexname;
    END LOOP;
END $$;

-- Drop temp tables from previous runs
DROP TABLE IF EXISTS recent_signups;

-- Refresh table statistics
ANALYZE users;
ANALYZE ratings;
ANALYZE movies;
ANALYZE watchlist;


-- ============================================================================
-- STEP 2: SEED SLOW QUERIES
-- ============================================================================

-- Run the seed script to simulate production query activity:
\i datasets/seed_slow_queries.sql

-- This runs various problematic queries so pg_stat_statements has data.


-- ============================================================================
-- STEP 3: FIND - Identify the slow queries
-- ============================================================================

-- Query pg_stat_statements to find the slowest queries.
-- Look at total_exec_time, calls, and mean_exec_time.

SELECT
    substring(query, 1, 80) AS query_preview,
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
  AND query NOT LIKE '%pg_catalog%'
  AND query NOT LIKE 'SELECT $1 AS status'
ORDER BY total_exec_time DESC
LIMIT 10;

-- You should see 6 slow queries. Now let's diagnose and fix each one.


-- ============================================================================
-- STEP 4: DIAGNOSE → FIX → VERIFY
-- ============================================================================
--
-- For each query below:
--   a) DIAGNOSE: Run the EXPLAIN ANALYZE to see the problem
--   b) FIX: Apply the appropriate solution
--   c) VERIFY: Re-run EXPLAIN ANALYZE to confirm improvement
-- ============================================================================


-- ----------------------------------------------------------------------------
-- QUERY 1: Large sort spilling to disk
-- ----------------------------------------------------------------------------

-- DIAGNOSE (look for "Sort Method: external merge Disk"):
EXPLAIN ANALYZE
SELECT * FROM ratings ORDER BY rating DESC;

-- What's the problem?
-- YOUR DIAGNOSIS:

-- FIX:
-- YOUR CODE HERE:

-- VERIFY (should show "Sort Method: quicksort Memory"):
EXPLAIN ANALYZE
SELECT * FROM ratings ORDER BY rating DESC;


-- ----------------------------------------------------------------------------
-- QUERY 2: Join without index
-- ----------------------------------------------------------------------------

-- DIAGNOSE (look for Seq Scan on ratings):
EXPLAIN ANALYZE
SELECT m.title, m.release_year, COUNT(r.rating_id)
FROM movies m
JOIN ratings r ON r.movie_id = m.movie_id
WHERE m.release_year >= 2020
GROUP BY m.movie_id, m.title, m.release_year
ORDER BY COUNT(r.rating_id) DESC
LIMIT 10;

-- What's the problem?
-- YOUR DIAGNOSIS:

-- FIX:
-- YOUR CODE HERE:

-- VERIFY:
EXPLAIN ANALYZE
SELECT m.title, m.release_year, COUNT(r.rating_id)
FROM movies m
JOIN ratings r ON r.movie_id = m.movie_id
WHERE m.release_year >= 2020
GROUP BY m.movie_id, m.title, m.release_year
ORDER BY COUNT(r.rating_id) DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- QUERY 3: Function on column prevents index use
-- ----------------------------------------------------------------------------

-- DIAGNOSE (look for Seq Scan):
EXPLAIN ANALYZE
SELECT * FROM users WHERE EXTRACT(YEAR FROM created_at) = 2024;

-- What's the problem?
-- YOUR DIAGNOSIS:

-- FIX (hint: rewrite the query, don't create an index):
-- YOUR CODE HERE:


-- ----------------------------------------------------------------------------
-- QUERY 4: Missing index on email
-- ----------------------------------------------------------------------------

-- DIAGNOSE:
EXPLAIN ANALYZE
SELECT * FROM users WHERE email = 'user500@example.com';

-- What's the problem?
-- YOUR DIAGNOSIS:

-- FIX:
-- YOUR CODE HERE:

-- VERIFY:
EXPLAIN ANALYZE
SELECT * FROM users WHERE email = 'user500@example.com';


-- ----------------------------------------------------------------------------
-- QUERY 5: JSONB expression without index
-- ----------------------------------------------------------------------------

-- DIAGNOSE:
EXPLAIN ANALYZE
SELECT title, metadata->>'streaming' FROM movies
WHERE metadata->>'streaming' = 'Streamly';

-- What's the problem?
-- YOUR DIAGNOSIS:

-- FIX:
-- YOUR CODE HERE:

-- VERIFY:
EXPLAIN ANALYZE
SELECT title, metadata->>'streaming' FROM movies
WHERE metadata->>'streaming' = 'Streamly';


-- ----------------------------------------------------------------------------
-- QUERY 6: Array containment without GIN index
-- ----------------------------------------------------------------------------

-- DIAGNOSE:
EXPLAIN ANALYZE
SELECT title, tags FROM movies WHERE tags @> ARRAY['indie'];

-- What's the problem?
-- YOUR DIAGNOSIS:

-- FIX:
-- YOUR CODE HERE:

-- VERIFY (note: with only 500 rows, Postgres may still choose Seq Scan):
EXPLAIN ANALYZE
SELECT title, tags FROM movies WHERE tags @> ARRAY['indie'];




-- ============================================================================
-- BONUS CHALLENGES (if time permits)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Bonus 1: Stale Statistics Scenario
-- ----------------------------------------------------------------------------

-- Create a new table WITHOUT running ANALYZE:
DROP TABLE IF EXISTS recent_signups;
CREATE TABLE recent_signups AS
SELECT user_id, username, email, created_at
FROM users
WHERE created_at >= '2024-01-01';

-- Check that Postgres has no stats yet:
SELECT relname, n_live_tup, last_analyze
FROM pg_stat_user_tables
WHERE relname = 'recent_signups';

-- Look at the row estimate vs actual:
EXPLAIN ANALYZE
SELECT * FROM recent_signups WHERE created_at >= '2024-06-01';

-- Fix it and verify the estimates improve:
-- YOUR CODE HERE:



-- ----------------------------------------------------------------------------
-- Bonus 2: Function Preventing Index Use
-- ----------------------------------------------------------------------------

-- Create an index on created_at:
CREATE INDEX IF NOT EXISTS idx_users_created ON users(created_at);

-- This query CAN'T use the index (function wraps the column):
EXPLAIN ANALYZE
SELECT * FROM users WHERE EXTRACT(YEAR FROM created_at) = 2024;

-- Rewrite the query so it CAN use the index:
-- YOUR CODE HERE:



-- ----------------------------------------------------------------------------
-- Bonus 3: Check for Lock Contention
-- ----------------------------------------------------------------------------

-- Are any queries blocking each other right now?
SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.query AS blocked_query,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.query AS blocking_query
FROM pg_locks blocked_locks
JOIN pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted AND blocking_locks.granted;




-- ============================================================================
-- ******************************************************************************
-- **                  REMINDER: Student survey at end of class!              **
-- ******************************************************************************
-- ============================================================================


-- ============================================================================
-- SECTION 2: Exploring Architecture (25 min)
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
-- SECTION 3: Memory and Caching (25 min)
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

-- ============================================================================
-- CAPSTONE SOLUTIONS (For Instructor Reference)
-- ============================================================================
-- These are the queries seeded by seed_slow_queries.sql and their fixes.
-- Students should discover these by querying pg_stat_statements.

-- SLOW QUERY: SELECT * FROM users WHERE email = $1
-- Diagnosis: Seq Scan on users (5K rows), filtering by email
-- Fix: B-Tree index on email column
CREATE INDEX idx_users_email ON users(email);


-- SLOW QUERY: SELECT title, tags FROM movies WHERE tags @> $1
-- Diagnosis: Seq Scan on movies, array containment check
-- Fix: GIN index for array operations
CREATE INDEX idx_movies_tags ON movies USING GIN(tags);
-- Note: With only 500 rows, Postgres may still choose Seq Scan. That's OK!


-- SLOW QUERY: SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = $1
-- Diagnosis: Seq Scan, JSONB expression in WHERE clause
-- Fix: Expression index on the extracted value
CREATE INDEX idx_movies_streaming ON movies((metadata->>'streaming'));


-- SLOW QUERY: SELECT * FROM users WHERE EXTRACT(YEAR FROM created_at) = $1
-- Diagnosis: Seq Scan - function on column prevents index use
-- Fix: Rewrite query to use a range instead of EXTRACT()
SELECT * FROM users
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';
-- This allows the index on created_at to be used


-- SLOW QUERY: SELECT m.title, m.release_year, COUNT(r.rating_id) FROM movies m JOIN ratings r...
-- Diagnosis: Seq Scan on ratings in the join (57K rows)
-- Fix: Index on the join column
CREATE INDEX idx_ratings_movie_id ON ratings(movie_id);


-- SLOW QUERY: SELECT * FROM ratings ORDER BY rating DESC
-- Diagnosis: Sort Method: external merge  Disk: XXkB (spilling to disk!)
-- Fix: Increase work_mem for this session
SET work_mem = '64MB';  -- or higher
-- Then re-run: Sort Method: quicksort  Memory: XXkB (in-memory, much faster)
-- Note: This is a session-level change. Reset with: RESET work_mem;


-- BONUS 1: Stale Statistics
-- Fix: Run ANALYZE on the new table
ANALYZE recent_signups;


-- BONUS 2: Function Preventing Index Use
-- Rewrite: Use range query instead of EXTRACT()
SELECT * FROM users
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';
*/
