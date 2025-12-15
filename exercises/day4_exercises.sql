-- ============================================================================
-- DAY 4 HANDS-ON LAB: Query Analysis & Optimization
-- Intermediate PostgreSQL Course
-- Duration: ~2 hours (instructor-led with exercises)
-- Database: movies_db
--
-- TIMING:
--   Section 1: EXPLAIN Basics (20 min)
--   Section 2: Diagnosing Slow Queries (40 min)
--   Section 3: Fixing Problems (40 min)
--   Section 4: Challenge Queries (20 min)
--   Total: ~120 minutes
-- ============================================================================


-- ============================================================================
-- SECTION 1: EXPLAIN Basics (20 min)
-- ============================================================================

-- ============================================================================
-- KEY CONCEPT: PLANNING VS EXECUTION
-- ============================================================================
--
-- Before Postgres runs your query, it must PLAN how to execute it:
--   1. PLANNING: Postgres estimates row counts, chooses scan types, join order
--   2. EXECUTION: The query runs using that plan
--
-- EXPLAIN shows you the PLAN (what Postgres intends to do)
-- EXPLAIN ANALYZE shows you PLAN + ACTUAL RESULTS (what really happened)
--
-- Why does this matter?
-- If the plan was based on bad estimates, the query will be slow.
-- EXPLAIN ANALYZE reveals the mismatch so you can fix it.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Demo: EXPLAIN vs EXPLAIN ANALYZE
-- ----------------------------------------------------------------------------

-- EXPLAIN shows the plan without running
EXPLAIN
SELECT * FROM movies WHERE release_year = 2020;

-- EXPLAIN ANALYZE actually runs the query
EXPLAIN ANALYZE
SELECT * FROM movies WHERE release_year = 2020;

-- Notice the difference:
-- • EXPLAIN: estimated rows, cost only
-- • EXPLAIN ANALYZE: estimated AND actual rows, actual time


-- ----------------------------------------------------------------------------
-- Demo: Reading the Numbers
-- ----------------------------------------------------------------------------

-- ============================================================================
-- UNDERSTANDING EXPLAIN OUTPUT
-- ============================================================================
--
-- Every line in EXPLAIN output contains key information:
--
--   Seq Scan on movies  (cost=0.00..15.50 rows=3 width=285)
--                        ▲              ▲        ▲
--                        │              │        └─ width: avg bytes per row
--                        │              └─ rows: ESTIMATED row count
--                        └─ cost: startup..total (arbitrary units, not milliseconds!)
--
-- With EXPLAIN ANALYZE, you also see:
--
--   (actual time=0.015..0.089 rows=5 loops=1)
--                 ▲              ▲       ▲
--                 │              │       └─ loops: times this node executed
--                 │              └─ rows: ACTUAL row count
--                 └─ time: ACTUAL milliseconds (startup..total)
--
-- COST vs TIME:
--   • cost is a relative estimate (used to compare plans)
--   • time is actual milliseconds (what users feel)
--
-- LOOPS:
--   • Usually 1 for simple queries
--   • Higher in nested loops (inner side runs once per outer row)
--   • Multiply time × loops for true total time of that node
-- ============================================================================

-- Let's break down what we see
EXPLAIN ANALYZE
SELECT * FROM movies WHERE release_year = 2020;

/*
What to look for:

Seq Scan on movies  (cost=0.00..15.50 rows=3 width=285)
                     ^^^^^^^^^^^^^^^^^^^^
                     startup..total cost (arbitrary units)
                                   ^^^^
                                   estimated rows

(actual time=0.015..0.089 rows=5 loops=1)
              ^^^^^^^^^^^^^^^^^^^
              real time in milliseconds
                           ^^^^
                           actual rows returned
*/


-- ----------------------------------------------------------------------------
-- Demo: BUFFERS Option
-- ----------------------------------------------------------------------------

-- ============================================================================
-- UNDERSTANDING BUFFERS OUTPUT
-- ============================================================================
--
-- BUFFERS shows how data was accessed:
--
--   Buffers: shared hit=5 read=2
--            ▲           ▲
--            │           └─ read: pages fetched from DISK (slow)
--            └─ hit: pages found in MEMORY cache (fast)
--
-- What is a "page"?
--   • PostgreSQL stores data in 8KB pages
--   • Each buffer hit/read = one 8KB page
--
-- Why this matters:
--   • Disk reads are ~100x slower than memory hits
--   • High "read" count = query might be slow on cold cache
--   • High "hit" count = data was already cached, fast!
--
-- First run vs. repeated runs:
--   • First run: mostly "read" (loading from disk)
--   • Repeated runs: mostly "hit" (already in cache)
--   • Test with cold cache to see real-world performance
-- ============================================================================

-- Shows how much data was read
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM movies WHERE release_year = 2020;

/*
Buffers: shared hit=5 read=2
         ^^^^^^^^^^^ ^^^^^^^
         from cache  from disk

Lower "read" is better - means data was cached
*/


-- ----------------------------------------------------------------------------
-- Demo: Plan Structure
-- ----------------------------------------------------------------------------

-- More complex query - shows tree structure
EXPLAIN ANALYZE
SELECT m.title, COUNT(*) as rating_count
FROM movies m
JOIN ratings r ON m.movie_id = r.movie_id
WHERE m.release_year >= 2015
GROUP BY m.movie_id, m.title
ORDER BY rating_count DESC
LIMIT 10;

-- Read bottom-up, inside-out!
-- Inner nodes execute first, results flow up


-- ----------------------------------------------------------------------------
-- Exercise 1: Your Turn - Reading Plans
-- Time: 10 minutes
-- ----------------------------------------------------------------------------

-- ** ESSENTIAL ** Exercise 1a: Run this and identify:
-- 1. What type of scan is used?
-- 2. Estimated vs actual rows?
-- 3. Execution time?

EXPLAIN ANALYZE
SELECT * FROM ratings WHERE rating = 5;

-- Write your answers here:
-- Scan type:
-- Estimated rows:
-- Actual rows:
-- Time:


-- (Optional) Exercise 1b: Run this query and identify the JOIN type
EXPLAIN ANALYZE
SELECT m.title, r.rating
FROM movies m
JOIN ratings r ON m.movie_id = r.movie_id
WHERE m.movie_id = 1;

-- JOIN type used:



-- ============================================================================
-- SECTION 2: Diagnosing Slow Queries (40 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo: Finding the Bottleneck
-- ----------------------------------------------------------------------------

-- This query is slow - let's diagnose it
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    u.username,
    COUNT(*) as review_count,
    AVG(r.rating) as avg_rating
FROM users u
JOIN ratings r ON u.user_id = r.user_id
GROUP BY u.user_id, u.username
ORDER BY review_count DESC
LIMIT 20;

-- Questions to ask:
-- 1. Which node takes the longest?
-- 2. Are estimates accurate?
-- 3. Any sequential scans on large tables?


-- ----------------------------------------------------------------------------
-- Demo: Estimate vs Actual Mismatch
-- ----------------------------------------------------------------------------

-- ============================================================================
-- WHY JSONB ESTIMATES ARE OFTEN WRONG
-- ============================================================================
--
-- PostgreSQL statistics work well for regular columns, but JSONB is tricky:
--
--   • Regular column: Postgres samples values, builds histogram
--   • JSONB column: Postgres knows it's JSONB, but doesn't look INSIDE
--
-- When you query metadata->>'language' = 'French':
--   • Postgres doesn't know how many rows have language='French'
--   • It uses a default estimate (often 0.1% or 1% of rows)
--   • This guess can be wildly wrong!
--
-- Result: estimated rows might say 5, actual rows might be 500
--         Postgres chose a plan for 5 rows, but got 500 = slow!
--
-- Solutions:
--   1. Run ANALYZE (helps a little)
--   2. Create expression index: CREATE INDEX ON movies((metadata->>'language'))
--   3. Create extended statistics (PostgreSQL 12+)
-- ============================================================================

-- When estimates are wrong, plans can be terrible
-- Let's create a scenario with bad estimates

-- First, check a query
EXPLAIN ANALYZE
SELECT * FROM movies
WHERE metadata->>'language' = 'French';

-- The estimate might be way off because Postgres
-- doesn't know the distribution of JSONB values


-- ----------------------------------------------------------------------------
-- Demo: Fixing with ANALYZE
-- ----------------------------------------------------------------------------

-- Update statistics
ANALYZE movies;

-- Try the query again
EXPLAIN ANALYZE
SELECT * FROM movies
WHERE metadata->>'language' = 'French';

-- Estimates should be better now


-- ----------------------------------------------------------------------------
-- Demo: Identifying Missing Indexes
-- ----------------------------------------------------------------------------

-- This query does a Seq Scan - should it?
EXPLAIN ANALYZE
SELECT * FROM ratings
WHERE rated_at > CURRENT_DATE - INTERVAL '6 months';

-- Many rows, filtered result - index would help
-- But first, check if data is ordered (for BRIN consideration)
SELECT rated_at FROM ratings ORDER BY ctid LIMIT 100;


-- ----------------------------------------------------------------------------
-- Exercise 2: Your Turn - Diagnosis
-- Time: 20 minutes
-- ----------------------------------------------------------------------------

-- ** ESSENTIAL ** Exercise 2a: Diagnose this slow query
-- Find the bottleneck and explain why it's slow

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    g.name as genre,
    COUNT(DISTINCT m.movie_id) as movie_count,
    ROUND(AVG(r.rating), 2) as avg_rating
FROM genres g
JOIN movie_genres mg ON g.genre_id = mg.genre_id
JOIN movies m ON mg.movie_id = m.movie_id
JOIN ratings r ON m.movie_id = r.movie_id
GROUP BY g.genre_id, g.name
ORDER BY avg_rating DESC;

-- What's the bottleneck?
-- YOUR ANSWER:



-- (Optional) Exercise 2b: This query has a large estimate vs actual mismatch
-- Run it and identify where the mismatch is

EXPLAIN ANALYZE
SELECT m.title, u.username, r.rating
FROM movies m
JOIN ratings r ON m.movie_id = r.movie_id
JOIN users u ON r.user_id = u.user_id
WHERE m.tags @> ARRAY['cult-classic']
  AND r.rating >= 4;

-- Where is the mismatch?
-- YOUR ANSWER:



-- (Optional) Exercise 2c: Analyze this query and list all the node types used

EXPLAIN ANALYZE
SELECT
    m.title,
    STRING_AGG(DISTINCT g.name, ', ') as genres,
    COUNT(r.rating_id) as rating_count
FROM movies m
LEFT JOIN movie_genres mg ON m.movie_id = mg.movie_id
LEFT JOIN genres g ON mg.genre_id = g.genre_id
LEFT JOIN ratings r ON m.movie_id = r.movie_id
WHERE m.release_year BETWEEN 2010 AND 2020
GROUP BY m.movie_id, m.title
HAVING COUNT(r.rating_id) > 50
ORDER BY rating_count DESC;

-- List the node types:
-- YOUR ANSWER:




-- ============================================================================
-- SECTION 3: Fixing Problems (40 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo: Adding Missing Index
-- ----------------------------------------------------------------------------

-- Before: Seq Scan
EXPLAIN ANALYZE
SELECT * FROM ratings WHERE user_id = 100;

-- Create index
CREATE INDEX idx_ratings_user ON ratings(user_id);

-- After: Index Scan
EXPLAIN ANALYZE
SELECT * FROM ratings WHERE user_id = 100;

-- How much faster?


-- ----------------------------------------------------------------------------
-- Demo: Covering Index for Index-Only Scan
-- ----------------------------------------------------------------------------

-- This query needs to fetch from table
EXPLAIN ANALYZE
SELECT user_id, rating FROM ratings WHERE user_id = 100;

-- Create covering index
CREATE INDEX idx_ratings_user_covering ON ratings(user_id) INCLUDE (rating);

-- Now it's Index Only Scan - no table access needed
EXPLAIN ANALYZE
SELECT user_id, rating FROM ratings WHERE user_id = 100;


-- ----------------------------------------------------------------------------
-- Demo: Rewriting Subqueries
-- ----------------------------------------------------------------------------

-- Correlated subquery - can be slow
EXPLAIN ANALYZE
SELECT m.title,
    (SELECT COUNT(*) FROM ratings r WHERE r.movie_id = m.movie_id) as cnt
FROM movies m
WHERE m.release_year = 2020;

-- Rewrite as JOIN - often faster
EXPLAIN ANALYZE
SELECT m.title, COUNT(r.rating_id) as cnt
FROM movies m
LEFT JOIN ratings r ON m.movie_id = r.movie_id
WHERE m.release_year = 2020
GROUP BY m.movie_id, m.title;

-- Compare the plans and times


-- ----------------------------------------------------------------------------
-- Demo: EXISTS vs IN
-- ----------------------------------------------------------------------------

-- ============================================================================
-- EXISTS VS IN: WHEN TO USE WHICH
-- ============================================================================
--
-- Both check "does a matching row exist?" but work differently:
--
-- IN (subquery):
--   • Executes subquery first, builds list of values
--   • Then checks if each row's value is in that list
--   • Good when: subquery returns FEW rows
--   • Bad when: subquery returns MANY rows (huge list to check)
--
-- EXISTS (correlated subquery):
--   • For each outer row, checks if subquery returns ANY row
--   • Stops as soon as it finds ONE match (short-circuit)
--   • Good when: subquery would return MANY rows per match
--   • Good when: you just need to know "does it exist?"
--
-- Modern PostgreSQL is smart:
--   • Often converts IN to a semi-join (same as EXISTS)
--   • But not always! Check your EXPLAIN output
--
-- Rule of thumb:
--   • Few subquery results → IN is fine
--   • Many subquery results → EXISTS may be faster
--   • When in doubt → test both with EXPLAIN ANALYZE
-- ============================================================================

-- IN with large list
EXPLAIN ANALYZE
SELECT * FROM movies m
WHERE m.movie_id IN (SELECT movie_id FROM ratings WHERE rating = 5);

-- EXISTS - often better
EXPLAIN ANALYZE
SELECT * FROM movies m
WHERE EXISTS (SELECT 1 FROM ratings r WHERE r.movie_id = m.movie_id AND r.rating = 5);

-- Compare which is faster for your data


-- ----------------------------------------------------------------------------
-- Exercise 3: Your Turn - Fixing
-- Time: 20 minutes
-- ----------------------------------------------------------------------------

-- (Optional) Exercise 3a: This query is slow. Diagnose and fix it.

-- ============================================================================
-- WHY LEADING WILDCARDS CAN'T USE B-TREE INDEXES
-- ============================================================================
--
-- B-tree indexes are like a phone book - sorted alphabetically.
-- You can quickly find "Smith" because you know where 'S' entries start.
--
-- But searching for '%smith' (ends with 'smith') is different:
--   • You can't jump to a starting point
--   • You must scan EVERY entry to check the ending
--   • Index is useless → Seq Scan
--
-- Pattern types and index usage:
--   'smith%'   → CAN use B-tree index (knows where to start)
--   '%smith'   → CANNOT use B-tree (must check all rows)
--   '%smith%'  → CANNOT use B-tree (must check all rows)
--
-- Solutions for leading wildcard searches:
--   1. pg_trgm extension with GIN index (trigram matching)
--   2. Full-text search with tsvector
--   3. Reverse the string: CREATE INDEX ON users(reverse(email))
--      Then search: WHERE reverse(email) LIKE reverse('%@example.com')
-- ============================================================================

EXPLAIN ANALYZE
SELECT * FROM users WHERE email LIKE '%@example.com';

-- Why is it slow?
-- YOUR ANSWER:

-- How would you fix it? (Hint: pattern matching limitations)
-- YOUR ANSWER:



-- ** ESSENTIAL ** Exercise 3b: Optimize this query by adding an appropriate index

EXPLAIN ANALYZE
SELECT m.title, r.rated_at, r.rating
FROM movies m
JOIN ratings r ON m.movie_id = r.movie_id
WHERE r.rated_at > CURRENT_DATE - INTERVAL '3 months'
ORDER BY r.rated_at DESC
LIMIT 100;

-- YOUR CODE HERE (create index):



-- (Optional) Exercise 3c: Rewrite this correlated subquery as a JOIN

SELECT
    u.username,
    (SELECT AVG(rating) FROM ratings r WHERE r.user_id = u.user_id) as avg_rating
FROM users u
WHERE u.created_at > CURRENT_DATE - INTERVAL '1 year';

-- YOUR CODE HERE (rewritten query):




-- ============================================================================
-- SECTION 4: Challenge Queries (20 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (Optional) Challenge 1: The Slow Dashboard Query
-- ----------------------------------------------------------------------------

-- This powers a dashboard and runs every 5 seconds
-- It's too slow - optimize it!

EXPLAIN ANALYZE
SELECT
    g.name as genre,
    COUNT(DISTINCT m.movie_id) as movies,
    COUNT(r.rating_id) as total_ratings,
    ROUND(AVG(r.rating), 2) as avg_rating,
    MAX(r.rated_at) as last_rating
FROM genres g
LEFT JOIN movie_genres mg ON g.genre_id = mg.genre_id
LEFT JOIN movies m ON mg.movie_id = m.movie_id
LEFT JOIN ratings r ON m.movie_id = r.movie_id
GROUP BY g.genre_id, g.name
ORDER BY total_ratings DESC;

-- What indexes would help?
-- YOUR ANSWER:



-- ----------------------------------------------------------------------------
-- (Optional) Challenge 2: User Activity Report
-- ----------------------------------------------------------------------------

-- Find the top 10 most active users this month with their favorite genre

EXPLAIN ANALYZE
SELECT
    u.username,
    COUNT(*) as ratings_count,
    MODE() WITHIN GROUP (ORDER BY g.name) as favorite_genre
FROM users u
JOIN ratings r ON u.user_id = r.user_id
JOIN movies m ON r.movie_id = m.movie_id
JOIN movie_genres mg ON m.movie_id = mg.movie_id
JOIN genres g ON mg.genre_id = g.genre_id
WHERE r.rated_at > CURRENT_DATE - INTERVAL '30 days'
GROUP BY u.user_id, u.username
ORDER BY ratings_count DESC
LIMIT 10;

-- Identify bottlenecks and suggest optimizations
-- YOUR ANSWER:




-- ============================================================================
-- SECTION 5: Wrap-up & Key Takeaways
-- ============================================================================

/*
KEY TAKEAWAYS:

1. EXPLAIN ANALYZE is your best friend
   - Always use ANALYZE for real numbers
   - Add BUFFERS to see I/O

2. Read plans bottom-up, inside-out
   - Inner/lower nodes execute first
   - Results flow up to parent nodes

3. Watch for warning signs:
   - Seq Scan on large table + small result
   - Large estimate vs actual mismatch
   - Nested Loop with high row counts
   - Sort using external merge

4. Common fixes:
   - Missing index → CREATE INDEX
   - Bad estimates → ANALYZE table
   - Correlated subquery → Rewrite as JOIN
   - IN with many values → Use EXISTS

5. Test your fixes!
   - Re-run EXPLAIN ANALYZE after changes
   - Measure actual improvement
*/


-- ============================================================================
-- SOLUTIONS (For Instructor Reference)
-- ============================================================================

/*
-- Solution 1a: Reading the plan
-- Scan type: Seq Scan (no index on rating column)
-- Estimated rows: varies
-- Actual rows: varies
-- Time: varies

-- Solution 1b: JOIN type
-- Likely: Nested Loop with Index Scan on movies

-- Solution 2a: Bottleneck
-- The largest time is usually in the Hash Join or
-- Aggregate step due to the many-to-many relationships

-- Solution 2b: Estimate mismatch
-- The tags @> condition likely shows estimate vs actual mismatch
-- because array statistics are limited

-- Solution 2c: Node types
-- Typically: Sort, Aggregate, Hash Join, Seq Scan/Index Scan,
-- Nested Loop

-- Solution 3a: LIKE '%@example.com'
-- Leading wildcard can't use B-tree index
-- Options: Full-text search, pg_trgm extension,
-- or reverse() with function-based index

-- Solution 3b: Index for rated_at query
CREATE INDEX idx_ratings_rated_at ON ratings(rated_at DESC);
-- Or covering index:
CREATE INDEX idx_ratings_rated_at_covering
ON ratings(rated_at DESC) INCLUDE (movie_id, rating);

-- Solution 3c: Rewritten as JOIN
SELECT
    u.username,
    AVG(r.rating) as avg_rating
FROM users u
LEFT JOIN ratings r ON r.user_id = u.user_id
WHERE u.created_at > CURRENT_DATE - INTERVAL '1 year'
GROUP BY u.user_id, u.username;

-- Challenge solutions will vary based on current indexes
-- and data distribution
*/
