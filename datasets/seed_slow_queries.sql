-- seed_slow_queries.sql
-- Purpose: Generate slow queries that show up clearly in pg_stat_statements
--
-- Unlike the DO-block version, these queries appear as readable SQL
-- in pg_stat_statements, making them easier for students to identify.
--
-- Run this script, then query pg_stat_statements to see the results.
-- ============================================================================

-- Reset pg_stat_statements to start fresh
SELECT pg_stat_statements_reset();


-- ============================================================================
-- 1. MISSING INDEX ON FILTER COLUMN (Problem 1: email lookup)
-- ============================================================================
-- Filtering on email without an index

SELECT * FROM users WHERE email = 'user100@example.com';
SELECT * FROM users WHERE email = 'user100@example.com';
SELECT * FROM users WHERE email = 'user100@example.com';
SELECT * FROM users WHERE email = 'user200@example.com';
SELECT * FROM users WHERE email = 'user200@example.com';
SELECT * FROM users WHERE email = 'user200@example.com';
SELECT * FROM users WHERE email = 'user300@example.com';
SELECT * FROM users WHERE email = 'user300@example.com';
SELECT * FROM users WHERE email = 'user300@example.com';


-- ============================================================================
-- 2. ARRAY CONTAINMENT (Problem 2: no GIN index on tags)
-- ============================================================================
-- Searching for movies with specific tags

SELECT title, tags FROM movies WHERE tags @> ARRAY['indie'];
SELECT title, tags FROM movies WHERE tags @> ARRAY['indie'];
SELECT title, tags FROM movies WHERE tags @> ARRAY['indie'];
SELECT title, tags FROM movies WHERE tags @> ARRAY['blockbuster'];
SELECT title, tags FROM movies WHERE tags @> ARRAY['blockbuster'];
SELECT title, tags FROM movies WHERE tags @> ARRAY['blockbuster'];


-- ============================================================================
-- 3. JSONB LOOKUPS (Problem 3: no index on JSON path)
-- ============================================================================
-- Searching inside JSONB without an expression index

SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'Streamly';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'Streamly';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'Streamly';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'FlixNet';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'FlixNet';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'FlixNet';


-- ============================================================================
-- 4. FUNCTION ON INDEXED COLUMN (Problem 5: prevents index use)
-- ============================================================================
-- Using EXTRACT() on a column prevents index usage

SELECT * FROM users WHERE EXTRACT(YEAR FROM created_at) = 2024;
SELECT * FROM users WHERE EXTRACT(YEAR FROM created_at) = 2024;
SELECT * FROM users WHERE EXTRACT(YEAR FROM created_at) = 2024;
SELECT * FROM users WHERE EXTRACT(YEAR FROM created_at) = 2023;
SELECT * FROM users WHERE EXTRACT(YEAR FROM created_at) = 2023;
SELECT * FROM users WHERE EXTRACT(YEAR FROM created_at) = 2023;


-- ============================================================================
-- 5. JOIN QUERY (no index on join column)
-- ============================================================================
-- Joining movies and ratings without index on ratings.movie_id

SELECT m.title, m.release_year, COUNT(r.rating_id)
FROM movies m
JOIN ratings r ON r.movie_id = m.movie_id
WHERE m.release_year >= 2020
GROUP BY m.movie_id, m.title, m.release_year
ORDER BY COUNT(r.rating_id) DESC
LIMIT 10;

SELECT m.title, m.release_year, COUNT(r.rating_id)
FROM movies m
JOIN ratings r ON r.movie_id = m.movie_id
WHERE m.release_year >= 2020
GROUP BY m.movie_id, m.title, m.release_year
ORDER BY COUNT(r.rating_id) DESC
LIMIT 10;

SELECT m.title, m.release_year, COUNT(r.rating_id)
FROM movies m
JOIN ratings r ON r.movie_id = m.movie_id
WHERE m.release_year >= 2020
GROUP BY m.movie_id, m.title, m.release_year
ORDER BY COUNT(r.rating_id) DESC
LIMIT 10;


-- ============================================================================
-- 6. LARGE SORT (spills to disk with default work_mem)
-- ============================================================================
-- Sorting the entire ratings table - with default work_mem (4MB), this
-- spills to disk. Increasing work_mem allows in-memory quicksort.

SELECT * FROM ratings ORDER BY rating DESC;
SELECT * FROM ratings ORDER BY rating DESC;
SELECT * FROM ratings ORDER BY rating DESC;


-- ============================================================================
-- Done!
-- ============================================================================
-- Note: Problem 4 (stale statistics) is demonstrated in the exercises by
-- creating a new table without running ANALYZE - no seed queries needed.

SELECT 'Slow queries seeded! Now query pg_stat_statements to see them.' AS status;

-- Preview the results
SELECT
    substring(query, 1, 60) AS query_preview,
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
  AND query NOT LIKE 'SELECT pg_stat_statements_reset%'
ORDER BY total_exec_time DESC
LIMIT 10;
