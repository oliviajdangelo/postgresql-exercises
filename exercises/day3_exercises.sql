-- ============================================================================
-- DAY 3 HANDS-ON LAB: Indexing Strategies
-- Intermediate PostgreSQL Course
-- Duration: ~2 hours (instructor-led with exercises)
-- Database: movies_db
--
-- TIMING:
--   Section 1: Baseline Measurements (15 min)
--   Section 2: B-Tree Indexes (30 min)
--   Section 3: GIN Indexes (30 min)
--   Section 4: Index Analysis (30 min)
--   Section 5: Wrap-up (5 min)
--   Total: ~110 minutes (buffer for questions)
-- ============================================================================


-- ============================================================================
-- SECTION 1: Baseline Measurements (15 min)
-- ============================================================================

-- First, let's see what indexes already exist
SELECT
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- ----------------------------------------------------------------------------
-- Demo: Query Without Indexes
-- ----------------------------------------------------------------------------

-- UNDERSTANDING EXPLAIN ANALYZE OUTPUT
-- Before we start, let's understand what EXPLAIN ANALYZE shows us.
-- Run this query and look at the output:

EXPLAIN ANALYZE
SELECT * FROM movies WHERE release_year = 2020;

-- SAMPLE OUTPUT (yours will vary):
-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ Seq Scan on movies  (cost=0.00..125.00 rows=50 width=200)                   │
-- │                     (actual time=0.015..2.456 rows=48 loops=1)              │
-- │   Filter: (release_year = 2020)                                             │
-- │   Rows Removed by Filter: 4952                                              │
-- │ Planning Time: 0.089 ms                                                     │
-- │ Execution Time: 2.501 ms                                                    │
-- └─────────────────────────────────────────────────────────────────────────────┘
--
-- HOW TO READ THIS:
--
-- "Seq Scan on movies" = Scan type (Sequential Scan = reading every row)
--
-- cost=0.00..125.00 = Estimated cost (arbitrary units, for comparison only)
--   - First number (0.00) = startup cost before first row returns
--   - Second number (125.00) = total estimated cost
--
-- rows=50 = Postgres's ESTIMATE of rows returned (before running)
-- actual rows=48 = REAL rows returned (after running)
--   - When these differ wildly, statistics might be stale (run ANALYZE)
--
-- loops=1 = How many times this step ran (important for joins)
--
-- Execution Time: 2.501 ms = Total query time (this is what users feel)

-- Enable timing to see actual execution time in psql
\timing on

-- Now let's run queries that would benefit from indexes
-- Note the execution time!

-- Query 1: Find movies from a specific year
EXPLAIN ANALYZE
SELECT * FROM movies WHERE release_year = 2020;

-- Query 2: Find ratings for a specific movie
EXPLAIN ANALYZE
SELECT * FROM ratings WHERE movie_id = 42;

-- Query 3: Find movies with a specific tag
EXPLAIN ANALYZE
SELECT * FROM movies WHERE tags @> ARRAY['sci-fi'];

-- Query 4: Search JSONB metadata
EXPLAIN ANALYZE
SELECT * FROM movies WHERE metadata @> '{"streaming": "Netflix"}';

-- What do you notice about these plans?
-- All are Seq Scans - reading every row!


-- ============================================================================
-- SECTION 2: B-Tree Indexes (30 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo: Creating B-Tree Indexes
-- ----------------------------------------------------------------------------

-- Create index on release_year
CREATE INDEX idx_movies_release_year ON movies(release_year);

-- Now try the same query
EXPLAIN ANALYZE
SELECT * FROM movies WHERE release_year = 2020;

-- SAMPLE OUTPUT WITH INDEX:
-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ Index Scan using idx_movies_release_year on movies                          │
-- │                     (cost=0.28..8.50 rows=50 width=200)                      │
-- │                     (actual time=0.025..0.156 rows=48 loops=1)               │
-- │   Index Cond: (release_year = 2020)                                          │
-- │ Planning Time: 0.152 ms                                                      │
-- │ Execution Time: 0.187 ms                                                     │
-- └─────────────────────────────────────────────────────────────────────────────┘
--
-- WHAT CHANGED:
-- ✓ "Index Scan" instead of "Seq Scan" - using the index!
-- ✓ "Index Cond" instead of "Filter" - condition pushed to index
-- ✓ cost dropped from 125.00 to 8.50 (estimated 15x faster)
-- ✓ Execution Time dropped from ~2.5ms to ~0.2ms (actual 10x faster)
-- ✓ No "Rows Removed by Filter" - only read matching rows


-- ----------------------------------------------------------------------------
-- WHY YOU MIGHT STILL SEE SEQ SCAN AFTER ADDING AN INDEX
-- ----------------------------------------------------------------------------

-- Sometimes Postgres ignores your index and does a Seq Scan anyway.
-- This is usually INTENTIONAL - the planner thinks Seq Scan is faster!

-- Common reasons:

-- 1. SMALL TABLE - For tiny tables, Seq Scan is faster than index overhead
EXPLAIN ANALYZE SELECT * FROM movies WHERE release_year = 2020;
-- If movies table has <1000 rows, Seq Scan might be chosen

-- 2. QUERY RETURNS MOST ROWS - Index isn't helpful if you need 50% of table
EXPLAIN ANALYZE SELECT * FROM movies WHERE release_year > 1990;
-- If most movies are after 1990, Seq Scan is faster

-- 3. STALE STATISTICS - Planner has wrong info about data distribution
-- Fix: Run ANALYZE to update statistics
ANALYZE movies;

-- 4. SSD VS SPINNING DISK - Default settings assume slow random reads
-- On SSD, random reads are fast, so indexes are more attractive
-- Check/adjust: SHOW random_page_cost;  (default 4.0, try 1.1 for SSD)

-- REMEMBER: Seq Scan isn't always bad!
-- Trust the planner - it usually makes good choices.
-- Only investigate if queries are actually slow.

-- MEMORY VS DISK - DO INDEXES MATTER IF DATA IS CACHED?
--
-- Postgres keeps frequently-used data in memory (shared_buffers).
-- But memory caching and index usage are SEPARATE decisions:
--
--   - Caching = WHERE data lives (memory or disk)
--   - Index   = HOW MUCH data to read (few pages or all pages)
--
-- Even if your entire table is in memory:
--   - Seq Scan still reads ALL pages (just from memory instead of disk)
--   - Index Scan still reads FEWER pages (and those come from memory too)
--
-- So indexes help regardless of caching!
--
-- To see where data came from, add BUFFERS to your EXPLAIN:
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM movies WHERE release_year = 2020;
--
-- Output will show:
--   Buffers: shared hit=10      ← 10 pages read from memory cache (fast)
--   Buffers: shared read=5      ← 5 pages read from disk (slower)
--
-- "hit" = memory, "read" = disk. More hits = faster query.


-- ----------------------------------------------------------------------------
-- Demo: Composite Indexes
-- ----------------------------------------------------------------------------

-- Create composite index on ratings
CREATE INDEX idx_ratings_movie_user ON ratings(movie_id, user_id);

-- This index helps queries filtering by movie_id
EXPLAIN ANALYZE
SELECT * FROM ratings WHERE movie_id = 42;

-- And queries filtering by BOTH columns
EXPLAIN ANALYZE
SELECT * FROM ratings WHERE movie_id = 42 AND user_id = 100;

-- But NOT queries filtering only by user_id!
EXPLAIN ANALYZE
SELECT * FROM ratings WHERE user_id = 100;
-- Still a Seq Scan - column order matters!


-- ----------------------------------------------------------------------------
-- Demo: Index-Only Scans
-- ----------------------------------------------------------------------------

-- If all columns we need are in the index, Postgres can skip the table
CREATE INDEX idx_movies_year_title ON movies(release_year, title);

-- Query only needs columns in the index
EXPLAIN ANALYZE
SELECT release_year, title FROM movies WHERE release_year = 2020;

-- SAMPLE OUTPUT - INDEX ONLY SCAN:
-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ Index Only Scan using idx_movies_year_title on movies                       │
-- │                     (cost=0.28..4.50 rows=50 width=45)                       │
-- │                     (actual time=0.020..0.098 rows=48 loops=1)               │
-- │   Index Cond: (release_year = 2020)                                          │
-- │   Heap Fetches: 0                                                            │
-- │ Execution Time: 0.121 ms                                                     │
-- └─────────────────────────────────────────────────────────────────────────────┘
--
-- KEY INDICATORS:
-- ✓ "Index Only Scan" - the fastest scan type!
-- ✓ "Heap Fetches: 0" - didn't need to read the table at all
--   (If Heap Fetches > 0, table was accessed for visibility checks - run VACUUM)
-- ✓ Even lower cost than regular Index Scan


-- ----------------------------------------------------------------------------
-- Exercise 1: Your Turn - B-Tree Indexes
-- Time: 15 minutes
-- ----------------------------------------------------------------------------

-- ** ESSENTIAL ** Exercise 1a: Create an index to speed up this query
EXPLAIN ANALYZE
SELECT * FROM users WHERE username = 'user_42';

-- YOUR CODE HERE:



-- Verify it's faster with:
-- EXPLAIN ANALYZE SELECT * FROM users WHERE username = 'user_42';


-- (Optional) Exercise 1b: Create a composite index for this query pattern
-- Users often search ratings by user_id and filter by rating value
EXPLAIN ANALYZE
SELECT * FROM ratings WHERE user_id = 100 AND rating >= 4;

-- YOUR CODE HERE:



-- (Optional) Exercise 1c: This query is slow - why doesn't our idx_ratings_movie_user help?
EXPLAIN ANALYZE
SELECT * FROM ratings WHERE user_id = 500;

-- Explain why and create an appropriate index:

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 3: GIN Indexes (30 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo: GIN Index for Arrays
-- ----------------------------------------------------------------------------

-- Create GIN index on tags array
CREATE INDEX idx_movies_tags ON movies USING GIN (tags);

-- Now the array containment query uses the index
EXPLAIN ANALYZE
SELECT * FROM movies WHERE tags @> ARRAY['sci-fi'];

-- Also works for overlap
EXPLAIN ANALYZE
SELECT * FROM movies WHERE tags && ARRAY['action', 'adventure'];


-- ----------------------------------------------------------------------------
-- Demo: GIN Index for JSONB
-- ----------------------------------------------------------------------------

-- Create GIN index on JSONB metadata
CREATE INDEX idx_movies_metadata ON movies USING GIN (metadata);

-- Containment queries now use the index
EXPLAIN ANALYZE
SELECT * FROM movies WHERE metadata @> '{"streaming": "Netflix"}';

-- Key exists queries also use it
EXPLAIN ANALYZE
SELECT * FROM movies WHERE metadata ? 'budget';


-- ----------------------------------------------------------------------------
-- Demo: GIN for Full-Text Search
-- ----------------------------------------------------------------------------

-- WHAT IS A TSVECTOR?
-- A tsvector is text that's been preprocessed for fast searching.
-- Let's see what it looks like:

SELECT to_tsvector('english', 'The Dark Knight Rises');
-- Returns: 'dark':2 'knight':3 'rise':4
--
-- What happened:
--   - "The" was removed (it's a common "stop word")
--   - "Rises" became "rise" (stemming - reduces words to their root)
--   - Numbers show word positions (useful for phrase searches)

-- The movies table has a pre-computed search_vector column
-- Let's see what's stored in it:
SELECT title, search_vector
FROM movies
LIMIT 3;

-- WHY USE A STORED COLUMN?
-- Converting text to tsvector is expensive. By storing it in a column,
-- we do the conversion once when data is inserted, not on every search.

-- HOW TO CREATE A SEARCH VECTOR COLUMN (for reference):
-- 1. Add the column:
--    ALTER TABLE movies ADD COLUMN search_vector tsvector;
--
-- 2. Populate it from text columns:
--    UPDATE movies SET search_vector =
--        to_tsvector('english', title || ' ' || COALESCE(description, ''));
--
-- 3. Keep it updated with a trigger (we'll cover triggers on Day 2)

-- NOW CREATE THE GIN INDEX
-- Without this index, every search would scan all rows
CREATE INDEX idx_movies_search ON movies USING GIN (search_vector);

-- SEARCHING WITH TSQUERY
-- to_tsquery converts your search terms into a searchable format
-- The @@ operator means "matches"

-- Simple search for one word
EXPLAIN ANALYZE
SELECT title FROM movies
WHERE search_vector @@ to_tsquery('english', 'adventure');

-- Search with AND (&) - must contain both words
EXPLAIN ANALYZE
SELECT title FROM movies
WHERE search_vector @@ to_tsquery('english', 'adventure & space');

-- Search with OR (|) - contains either word
EXPLAIN ANALYZE
SELECT title FROM movies
WHERE search_vector @@ to_tsquery('english', 'adventure | comedy');

-- RANKING RESULTS
-- ts_rank scores how well each row matches (higher = better match)
EXPLAIN ANALYZE
SELECT title, ts_rank(search_vector, query) AS rank
FROM movies, to_tsquery('adventure & space') query
WHERE search_vector @@ query
ORDER BY rank DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Exercise 2: Your Turn - GIN Indexes
-- Time: 15 minutes
-- ----------------------------------------------------------------------------

-- ** ESSENTIAL ** Exercise 2a: The movies table has a JSONB 'metadata' column
-- Create a GIN index to speed up this query:
EXPLAIN ANALYZE
SELECT * FROM movies WHERE metadata @> '{"streaming": "Netflix"}';

-- YOUR CODE HERE:



-- (Optional) Exercise 2b: Find all movies that have ANY of these tags: 'comedy', 'romance'
-- First, run without index and note the plan:
EXPLAIN ANALYZE
SELECT title, tags FROM movies
WHERE tags && ARRAY['comedy', 'romance'];

-- The index we created should help - verify it's being used


-- (Optional) Exercise 2c: Search for movies with "battle" in the title using full-text search
-- Write a query using the search_vector column:

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 4: Index Analysis (30 min)
-- ============================================================================

-- WHY MONITOR INDEXES?
-- Indexes speed up reads but slow down writes (INSERT/UPDATE/DELETE).
-- Every index must be updated when data changes.
-- Unused indexes waste disk space AND slow down writes for no benefit.
--
-- This section teaches you how to find:
--   1. Which indexes are actually being used
--   2. Which indexes might be candidates for removal
--   3. How much space indexes consume

-- ----------------------------------------------------------------------------
-- Demo: Checking Index Usage
-- ----------------------------------------------------------------------------

-- PostgreSQL tracks how often each index is used in pg_stat_user_indexes
-- Key columns:
--   idx_scan       = How many times the index was used for lookups
--   idx_tup_read   = How many index entries were read
--   idx_tup_fetch  = How many table rows were fetched via the index

-- See all indexes and their usage statistics
SELECT
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    idx_scan AS times_used,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- INTERPRETING THE RESULTS:
-- - High idx_scan = index is heavily used (good!)
-- - idx_scan = 0 = index has never been used (investigate!)
-- - Large size + low usage = wasting space


-- ----------------------------------------------------------------------------
-- Demo: Finding Unused Indexes
-- ----------------------------------------------------------------------------

-- UNUSED INDEXES ARE A PROBLEM
-- They take up disk space AND slow down every INSERT/UPDATE/DELETE
-- because Postgres must update all indexes when data changes.

-- Find indexes that have never been used (idx_scan = 0)
SELECT
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    idx_scan AS times_used,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;

-- IMPORTANT CAVEATS before dropping "unused" indexes:
-- 1. Stats reset on server restart - zero might mean "not used since restart"
-- 2. Some indexes are for rare but critical queries (monthly reports, etc.)
-- 3. Primary key and unique indexes enforce constraints - don't drop these!
-- 4. Foreign key indexes speed up DELETE on parent tables
--
-- SAFE APPROACH: Monitor for at least one full business cycle (week/month)
-- before deciding an index is truly unused.


-- ----------------------------------------------------------------------------
-- Demo: Index Size vs Table Size
-- ----------------------------------------------------------------------------

-- HOW MUCH SPACE DO INDEXES USE?
-- It's common for indexes to be larger than the table itself!
-- Each index duplicates some data in a different structure.

-- Compare table and index sizes
SELECT
    t.relname AS table_name,
    pg_size_pretty(pg_relation_size(t.oid)) AS table_size,
    pg_size_pretty(pg_indexes_size(t.oid)) AS total_index_size,
    (SELECT COUNT(*) FROM pg_index WHERE indrelid = t.oid) AS index_count,
    CASE
        WHEN pg_relation_size(t.oid) > 0
        THEN ROUND(100.0 * pg_indexes_size(t.oid) / pg_relation_size(t.oid))
        ELSE 0
    END AS index_percent_of_table
FROM pg_class t
JOIN pg_namespace n ON t.relnamespace = n.oid
WHERE n.nspname = 'public'
  AND t.relkind = 'r'
ORDER BY pg_relation_size(t.oid) DESC;

-- WHAT'S NORMAL?
-- - 50-150% of table size in indexes is typical for OLTP
-- - Higher ratios might indicate over-indexing
-- - Very low ratios might mean missing indexes (but check query patterns first)


-- ----------------------------------------------------------------------------
-- Demo: Duplicate/Redundant Indexes
-- ----------------------------------------------------------------------------

-- WHAT ARE REDUNDANT INDEXES?
-- If you have an index on (a, b), you DON'T need a separate index on (a).
-- The composite index handles both cases:
--   WHERE a = ?           → Uses (a, b) index
--   WHERE a = ? AND b = ? → Uses (a, b) index
--
-- But (a, b) does NOT help with: WHERE b = ?
-- So an index on (b) alone is NOT redundant.

-- Find indexes that might be redundant
-- This query finds indexes whose columns are a prefix of another index
SELECT
    idx1.indexrelid::regclass AS potentially_redundant,
    idx2.indexrelid::regclass AS covered_by,
    idx1.indkey AS columns1,
    idx2.indkey AS columns2
FROM pg_index idx1
JOIN pg_index idx2 ON idx1.indrelid = idx2.indrelid
    AND idx1.indexrelid != idx2.indexrelid
    AND idx1.indkey <@ idx2.indkey  -- idx1 columns are subset of idx2
WHERE idx1.indrelid::regclass::text LIKE 'public.%'
LIMIT 10;

-- BEFORE DROPPING: Check if the "redundant" index is:
-- 1. A UNIQUE constraint (needed for data integrity)
-- 2. Smaller and faster for common queries (sometimes worth keeping)
-- 3. Used by the query planner for specific access patterns


-- ----------------------------------------------------------------------------
-- Exercise 3: Your Turn - Index Analysis
-- Time: 15 minutes
-- ----------------------------------------------------------------------------

-- ** ESSENTIAL ** Exercise 3a: Find the three largest indexes in the database
-- Show: index name, table name, size
--
-- HINT: Use pg_stat_user_indexes and pg_relation_size()
-- ORDER BY size descending, LIMIT to 3

-- YOUR CODE HERE:



-- (Optional) Exercise 3b: Find indexes that have been used fewer than 10 times
-- These might be candidates for review (but remember the caveats above!)
--
-- HINT: Filter on idx_scan < 10

-- YOUR CODE HERE:



-- (Optional) Exercise 3c: For the 'ratings' table specifically:
-- 1. How many indexes does it have?
-- 2. What's the total size of all its indexes?
-- 3. Which index is used most?
--
-- HINT: Filter pg_stat_user_indexes WHERE relname = 'ratings'
-- Use COUNT(*) and SUM() for aggregates

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 5: Wrap-up & Key Takeaways (5 min)
-- ============================================================================

/*
KEY TAKEAWAYS:

1. B-Tree is the default - use for equality, ranges, ORDER BY
   CREATE INDEX name ON table(column);

2. GIN is for complex types - arrays, JSONB, full-text search
   CREATE INDEX name ON table USING GIN (column);

3. BRIN is for large ordered data - timestamps, sequential IDs
   CREATE INDEX name ON table USING BRIN (column);

4. Composite index column order matters!
   (a, b) helps: WHERE a = ?, WHERE a = ? AND b = ?
   Does NOT help: WHERE b = ?

5. Monitor index usage with pg_stat_user_indexes
   Remove unused indexes - they slow down writes

QUICK REFERENCE - EXPLAIN ANALYZE OUTPUT:

Scan Types (from slowest to fastest):
┌───────────────────┬───────────────────────────────────────────────┐
│ Seq Scan          │ Reads every row - bad for large tables        │
│ Bitmap Index Scan │ Builds bitmap from index, then fetches rows   │
│ Index Scan        │ Uses index to find rows, fetches from table   │
│ Index Only Scan   │ Answers entirely from index - fastest!        │
└───────────────────┴───────────────────────────────────────────────┘

Key Numbers to Watch:
• actual time - Real execution time in milliseconds
• rows - How many rows returned (compare to estimate)
• loops - Times this step ran (multiply by time for total)
• Heap Fetches - Table accesses in Index Only Scan (0 = perfect)

Red Flags:
• Seq Scan on large table with small result set → add index
• rows estimate wildly different from actual → run ANALYZE
• Filter removing most rows → index on filter column

TOMORROW: We'll dive deeper into EXPLAIN and query optimization
*/


-- Clean up: Drop test indexes we created (optional)
-- DROP INDEX IF EXISTS idx_movies_release_year;
-- DROP INDEX IF EXISTS idx_ratings_movie_user;
-- etc.


-- ============================================================================
-- SOLUTIONS (For Instructor Reference)
-- ============================================================================

/*
-- Solution 1a: Index on username
CREATE INDEX idx_users_username ON users(username);

-- Solution 1b: Composite index for user_id + rating
CREATE INDEX idx_ratings_user_rating ON ratings(user_id, rating);

-- Solution 1c: The composite index (movie_id, user_id) doesn't help
-- because user_id is the second column. Need separate index:
CREATE INDEX idx_ratings_user_id ON ratings(user_id);

-- Solution 2a: GIN index on metadata JSONB column
CREATE INDEX idx_movies_metadata ON movies USING GIN (metadata);

-- Solution 2b: The idx_movies_tags GIN index helps with &&
-- Query is already shown in exercise

-- Solution 2c: Full-text search for "battle"
SELECT title, ts_rank(search_vector, to_tsquery('battle')) AS rank
FROM movies
WHERE search_vector @@ to_tsquery('battle')
ORDER BY rank DESC
LIMIT 10;

-- Solution 3a: Three largest indexes
SELECT
    indexrelname AS index_name,
    relname AS table_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 3;

-- Solution 3b: Indexes used fewer than 10 times
SELECT
    indexrelname AS index_name,
    relname AS table_name,
    idx_scan AS times_used
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND idx_scan < 10
ORDER BY idx_scan ASC;

-- Solution 3c: Ratings table index analysis
SELECT
    COUNT(*) AS index_count,
    pg_size_pretty(SUM(pg_relation_size(indexrelid))) AS total_size
FROM pg_stat_user_indexes
WHERE relname = 'ratings';

SELECT
    indexrelname,
    idx_scan
FROM pg_stat_user_indexes
WHERE relname = 'ratings'
ORDER BY idx_scan DESC
LIMIT 1;
*/
