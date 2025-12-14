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
-- ============================================================================


-- ============================================================================
-- SECTION 1: Exploring Architecture (30 min)
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

/*
** THIS IS THE CAPSTONE EXERCISE - COMPLETE ALL STEPS **

SCENARIO: You're brought in to troubleshoot a slow database.
Use everything you've learned this week to diagnose and fix the problems.

Work through these steps:
1. Find the slow queries
2. Diagnose why they're slow
3. Implement fixes
4. Verify improvements
*/

-- ----------------------------------------------------------------------------
-- Step 1: Find the Problem Queries
-- ----------------------------------------------------------------------------

-- Use pg_stat_statements to find slow queries
-- YOUR CODE HERE:




-- ----------------------------------------------------------------------------
-- Step 2: Pick Your Top Target
-- ----------------------------------------------------------------------------

-- Choose one slow query and run EXPLAIN ANALYZE on it
-- YOUR CODE HERE:




-- ----------------------------------------------------------------------------
-- Step 3: Diagnose the Problem
-- ----------------------------------------------------------------------------

/*
Ask yourself:
- Is there a sequential scan on a large table?
- Are the row estimates accurate?
- Is there a missing index?
- Are statistics up to date?
- Any sorts using disk?
*/

-- Check table statistics freshness
SELECT relname, last_analyze, n_live_tup
FROM pg_stat_user_tables;

-- Check for missing indexes (columns frequently filtered but not indexed)
-- YOUR ANALYSIS HERE:




-- ----------------------------------------------------------------------------
-- Step 4: Implement Fixes
-- ----------------------------------------------------------------------------

-- Based on your diagnosis, implement fixes
-- Examples:
-- CREATE INDEX ...
-- ANALYZE table_name;
-- Rewrite query

-- YOUR CODE HERE:




-- ----------------------------------------------------------------------------
-- Step 5: Verify Improvement
-- ----------------------------------------------------------------------------

-- Re-run EXPLAIN ANALYZE on your target query
-- Compare before and after

-- YOUR CODE HERE:




-- ----------------------------------------------------------------------------
-- (Optional) Bonus Challenge: Lock Investigation
-- ----------------------------------------------------------------------------

-- Check if there are any blocking queries
SELECT
    blocked.pid AS blocked_pid,
    blocked.query AS blocked_query,
    blocking.pid AS blocking_pid,
    blocking.query AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid != blocked.pid
WHERE blocked.wait_event_type = 'Lock';

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

-- Final challenge solutions will vary based on
-- which queries students choose to optimize
*/
