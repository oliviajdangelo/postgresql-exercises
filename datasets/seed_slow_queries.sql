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
-- 1. WILDCARD SEARCHES (can't use B-tree index)
-- ============================================================================
-- These use ILIKE '%...%' which forces a sequential scan

SELECT * FROM movies WHERE title ILIKE '%love%';
SELECT * FROM movies WHERE title ILIKE '%love%';
SELECT * FROM movies WHERE title ILIKE '%love%';
SELECT * FROM movies WHERE title ILIKE '%love%';
SELECT * FROM movies WHERE title ILIKE '%love%';

SELECT * FROM movies WHERE title ILIKE '%night%';
SELECT * FROM movies WHERE title ILIKE '%night%';
SELECT * FROM movies WHERE title ILIKE '%night%';
SELECT * FROM movies WHERE title ILIKE '%night%';
SELECT * FROM movies WHERE title ILIKE '%night%';

SELECT * FROM movies WHERE title ILIKE '%star%';
SELECT * FROM movies WHERE title ILIKE '%star%';
SELECT * FROM movies WHERE title ILIKE '%star%';
SELECT * FROM movies WHERE title ILIKE '%star%';
SELECT * FROM movies WHERE title ILIKE '%star%';


-- ============================================================================
-- 2. JSONB LOOKUPS (no index on JSON path)
-- ============================================================================
-- Searching inside JSONB without an expression index

SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'Streamly';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'Streamly';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'Streamly';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'Streamly';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'Streamly';

SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'FlixNet';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'FlixNet';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'FlixNet';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'FlixNet';
SELECT title, metadata->>'streaming' FROM movies WHERE metadata->>'streaming' = 'FlixNet';


-- ============================================================================
-- 3. MISSING INDEX ON FILTER COLUMN
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
SELECT * FROM users WHERE email = 'user400@example.com';
SELECT * FROM users WHERE email = 'user400@example.com';
SELECT * FROM users WHERE email = 'user400@example.com';


-- ============================================================================
-- 4. LARGE TABLE AGGREGATION
-- ============================================================================
-- Aggregating 50K+ rows in ratings table

SELECT movie_id, AVG(rating), COUNT(*) FROM ratings GROUP BY movie_id;
SELECT movie_id, AVG(rating), COUNT(*) FROM ratings GROUP BY movie_id;
SELECT movie_id, AVG(rating), COUNT(*) FROM ratings GROUP BY movie_id;

SELECT user_id, AVG(rating), COUNT(*) FROM ratings GROUP BY user_id;
SELECT user_id, AVG(rating), COUNT(*) FROM ratings GROUP BY user_id;
SELECT user_id, AVG(rating), COUNT(*) FROM ratings GROUP BY user_id;


-- ============================================================================
-- 5. MULTI-TABLE JOIN
-- ============================================================================
-- Joining multiple tables without optimal indexes

SELECT m.title, u.username, r.rating
FROM ratings r
JOIN movies m ON m.movie_id = r.movie_id
JOIN users u ON u.user_id = r.user_id
WHERE r.rating >= 9;

SELECT m.title, u.username, r.rating
FROM ratings r
JOIN movies m ON m.movie_id = r.movie_id
JOIN users u ON u.user_id = r.user_id
WHERE r.rating >= 9;

SELECT m.title, u.username, r.rating
FROM ratings r
JOIN movies m ON m.movie_id = r.movie_id
JOIN users u ON u.user_id = r.user_id
WHERE r.rating >= 9;


-- ============================================================================
-- 6. DATE RANGE QUERIES (no index on rated_at)
-- ============================================================================

SELECT * FROM ratings WHERE rated_at >= '2024-06-01' AND rated_at < '2024-07-01';
SELECT * FROM ratings WHERE rated_at >= '2024-06-01' AND rated_at < '2024-07-01';
SELECT * FROM ratings WHERE rated_at >= '2024-06-01' AND rated_at < '2024-07-01';

SELECT * FROM ratings WHERE rated_at >= '2024-01-01' AND rated_at < '2024-02-01';
SELECT * FROM ratings WHERE rated_at >= '2024-01-01' AND rated_at < '2024-02-01';
SELECT * FROM ratings WHERE rated_at >= '2024-01-01' AND rated_at < '2024-02-01';


-- ============================================================================
-- 7. CORRELATED SUBQUERY (inefficient pattern)
-- ============================================================================
-- Subquery runs once per row in outer query

SELECT title, imdb_rating
FROM movies m
WHERE imdb_rating > (
    SELECT AVG(imdb_rating) FROM movies m2 WHERE m2.release_year = m.release_year
);

SELECT title, imdb_rating
FROM movies m
WHERE imdb_rating > (
    SELECT AVG(imdb_rating) FROM movies m2 WHERE m2.release_year = m.release_year
);

SELECT title, imdb_rating
FROM movies m
WHERE imdb_rating > (
    SELECT AVG(imdb_rating) FROM movies m2 WHERE m2.release_year = m.release_year
);


-- ============================================================================
-- Done!
-- ============================================================================

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
