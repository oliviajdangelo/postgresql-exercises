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

-- Enable timing to see actual execution time
\timing on

-- Let's try some queries that would benefit from indexes
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

-- Notice: Index Scan instead of Seq Scan!
-- Compare the execution time


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

-- Look for "Index Only Scan" - fastest possible!


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

-- Create GIN index on search vector
CREATE INDEX idx_movies_search ON movies USING GIN (search_vector);

-- Full-text search now uses the index
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

-- ** ESSENTIAL ** Exercise 2a: The users table has a JSONB 'preferences' column
-- Create an index to speed up this query:
EXPLAIN ANALYZE
SELECT * FROM users WHERE preferences @> '{"theme": "dark"}';

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

-- ----------------------------------------------------------------------------
-- Demo: Checking Index Usage
-- ----------------------------------------------------------------------------

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


-- ----------------------------------------------------------------------------
-- Demo: Finding Unused Indexes
-- ----------------------------------------------------------------------------

-- Indexes with zero scans might be candidates for removal
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

-- Warning: Stats reset on server restart, so zero might just mean "recently"


-- ----------------------------------------------------------------------------
-- Demo: Index Size vs Table Size
-- ----------------------------------------------------------------------------

-- Compare table and index sizes
SELECT
    t.relname AS table_name,
    pg_size_pretty(pg_relation_size(t.oid)) AS table_size,
    pg_size_pretty(pg_indexes_size(t.oid)) AS total_index_size,
    (SELECT COUNT(*) FROM pg_index WHERE indrelid = t.oid) AS index_count
FROM pg_class t
JOIN pg_namespace n ON t.relnamespace = n.oid
WHERE n.nspname = 'public'
  AND t.relkind = 'r'
ORDER BY pg_relation_size(t.oid) DESC;


-- ----------------------------------------------------------------------------
-- Demo: Duplicate/Redundant Indexes
-- ----------------------------------------------------------------------------

-- Find indexes that might be redundant
-- (index on (a) is redundant if you have index on (a, b))
SELECT
    idx1.indexrelid::regclass AS index1,
    idx2.indexrelid::regclass AS index2,
    idx1.indkey AS columns1,
    idx2.indkey AS columns2
FROM pg_index idx1
JOIN pg_index idx2 ON idx1.indrelid = idx2.indrelid
    AND idx1.indexrelid != idx2.indexrelid
    AND idx1.indkey <@ idx2.indkey  -- idx1 columns are subset of idx2
WHERE idx1.indrelid::regclass::text LIKE 'public.%'
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Exercise 3: Your Turn - Index Analysis
-- Time: 15 minutes
-- ----------------------------------------------------------------------------

-- ** ESSENTIAL ** Exercise 3a: Find the three largest indexes in the database
-- Show: index name, table name, size

-- YOUR CODE HERE:



-- (Optional) Exercise 3b: Find indexes that have been used fewer than 10 times
-- These might be candidates for review

-- YOUR CODE HERE:



-- (Optional) Exercise 3c: For the 'ratings' table specifically:
-- 1. How many indexes does it have?
-- 2. What's the total size of all its indexes?
-- 3. Which index is used most?

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

TOMORROW: We'll use EXPLAIN to see these indexes in query plans
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

-- Solution 2a: GIN index on preferences
CREATE INDEX idx_users_preferences ON users USING GIN (preferences);

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
