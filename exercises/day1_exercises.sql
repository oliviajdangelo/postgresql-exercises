-- ============================================================================
-- DAY 1 HANDS-ON LAB: Foundation & Advanced Data Types
-- Intermediate PostgreSQL Course
-- Duration: ~2 hours (instructor-led with exercises)
-- Database: movies_db
--
-- Run this lab AFTER the lecture.
-- Key learning moments: seeing the gotchas in action with real output.
-- ============================================================================

-- ============================================================================
-- SECTION 1: Environment Check & Warmup (10 min)
-- ============================================================================

-- Verify connection and setup
SELECT version();
SELECT current_database();

-- Verify all tables loaded
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- Quick row count verification
SELECT
    (SELECT COUNT(*) FROM movies) AS movies,
    (SELECT COUNT(*) FROM users) AS users,
    (SELECT COUNT(*) FROM ratings) AS ratings,
    (SELECT COUNT(*) FROM people) AS people;
-- Expected: 500 movies, 5000 users, ~75,000 ratings, 308 people

-- Explore the movies table structure
\d movies

-- Your first query - find all movies released in 2020
SELECT title, release_year, imdb_rating
FROM movies
WHERE release_year = 2020
LIMIT 10;


-- ============================================================================
-- SECTION 2: JOIN Types - Code Along & Exercises (30 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo: INNER JOIN
-- ----------------------------------------------------------------------------

-- Only movies that have ratings
SELECT
    m.title,
    m.release_year,
    COUNT(r.rating_id) AS num_ratings,
    ROUND(AVG(r.rating)::numeric, 1) AS avg_rating
FROM movies m
INNER JOIN ratings r ON m.movie_id = r.movie_id
GROUP BY m.movie_id, m.title, m.release_year
ORDER BY num_ratings DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Demo: LEFT JOIN
-- ----------------------------------------------------------------------------

-- All movies, whether they have ratings or not
SELECT
    m.title,
    m.release_year,
    COUNT(r.rating_id) AS num_ratings,
    ROUND(AVG(r.rating)::numeric, 1) AS avg_rating
FROM movies m
LEFT JOIN ratings r ON m.movie_id = r.movie_id
GROUP BY m.movie_id, m.title, m.release_year
HAVING COUNT(r.rating_id) = 0  -- Movies with NO ratings
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Demo: Multi-table JOIN
-- ----------------------------------------------------------------------------

-- Movies with their cast and genres
SELECT
    m.title,
    p.full_name AS actor,
    mc.character_name,
    array_agg(DISTINCT g.name ORDER BY g.name) AS genres
FROM movies m
INNER JOIN movie_cast mc ON m.movie_id = mc.movie_id
INNER JOIN people p ON mc.person_id = p.person_id
INNER JOIN movie_genres mg ON m.movie_id = mg.movie_id
INNER JOIN genres g ON mg.genre_id = g.genre_id
WHERE m.release_year = 2020
GROUP BY m.movie_id, m.title, p.full_name, mc.character_name
LIMIT 20;


-- ----------------------------------------------------------------------------
-- EXERCISE 1: Your Turn - JOINs
-- Time: 15 minutes
-- ----------------------------------------------------------------------------

-- Exercise 1a: Find all movies with their cast
-- Use INNER JOIN to get movies, people, and their roles
-- Include: movie title, person name, role, character name
-- Order by movie title, then billing order
-- Limit to first 20 rows

-- YOUR CODE HERE:




-- Exercise 1b: Find movies with NO cast members
-- Use LEFT JOIN to find movies that don't have anyone in movie_cast
-- Show: title, release_year
-- Order by release_year DESC

-- YOUR CODE HERE:




-- Exercise 1c: Count ratings per user
-- JOIN users with ratings
-- Show: username, number of ratings, average rating given
-- Only show users with more than 10 ratings
-- Order by number of ratings DESC

-- YOUR CODE HERE:




-- Exercise 1d: Top-rated movies by genre (CHALLENGE)
-- Join movies, ratings, movie_genres, genres
-- For each genre, show the top 3 highest-rated movies
-- Include: genre name, movie title, avg rating, number of ratings
-- Hint: Use ROW_NUMBER() window function

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 3: JSONB - Code Along & Exercises (30 min)
-- ============================================================================

/*
The metadata column structure:
{
  "age_rating": "PG-13",
  "language": "English",
  "streaming": "FlixNet",
  "budget_millions": 120,
  "box_office_millions": 350,
  "awards": {
    "oscars": 3,
    "golden_globes": 2,
    "nominated": true
  }
}
*/

-- ----------------------------------------------------------------------------
-- Demo: The -> vs ->> Gotcha (THIS IS IMPORTANT!)
-- ----------------------------------------------------------------------------

-- Let's see WHY the arrow operators matter

-- First, what does -> return?
SELECT
    title,
    metadata->'age_rating' AS with_single_arrow,
    pg_typeof(metadata->'age_rating') AS type_single
FROM movies
LIMIT 3;
-- Notice: returns JSON type with quotes!

-- Now with ->>
SELECT
    title,
    metadata->>'age_rating' AS with_double_arrow,
    pg_typeof(metadata->>'age_rating') AS type_double
FROM movies
LIMIT 3;
-- Notice: returns TEXT without quotes!

-- THE GOTCHA: This WHERE clause returns NO ROWS (silent failure!)
SELECT title FROM movies
WHERE metadata->'age_rating' = 'PG-13'
LIMIT 5;
-- Why? You're comparing JSON type to text!

-- CORRECT version:
SELECT title FROM movies
WHERE metadata->>'age_rating' = 'PG-13'
LIMIT 5;

-- ----------------------------------------------------------------------------
-- Demo: JSONB Operators
-- ----------------------------------------------------------------------------

-- Extract text value with ->>
SELECT
    title,
    metadata->>'age_rating' AS rating,
    metadata->>'language' AS language,
    metadata->>'streaming' AS platform
FROM movies
LIMIT 10;

-- Extract nested values
SELECT
    title,
    metadata->'awards'->>'oscars' AS oscar_count,
    metadata->'awards'->>'golden_globes' AS globe_count
FROM movies
WHERE metadata->'awards'->>'oscars' IS NOT NULL
LIMIT 10;

-- Query by JSONB value
SELECT title, metadata->>'streaming' AS platform
FROM movies
WHERE metadata->>'streaming' = 'Streamly'
LIMIT 10;

-- Contains operator @>
SELECT title, metadata->'awards'
FROM movies
WHERE metadata @> '{"awards": {"nominated": true}}'::jsonb
LIMIT 10;

-- Numeric comparisons
SELECT
    title,
    (metadata->>'budget_millions')::int AS budget,
    (metadata->>'box_office_millions')::int AS box_office
FROM movies
WHERE (metadata->>'budget_millions')::int > 150
ORDER BY (metadata->>'budget_millions')::int DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Demo: NULL Behavior Gotcha
-- ----------------------------------------------------------------------------

-- This returns NULL safely (no error):
SELECT
    title,
    metadata->'awards'->>'oscars' AS oscars
FROM movies
LIMIT 5;

-- But THIS can cause problems when casting:
-- (Some movies don't have awards, so we get NULL)
SELECT
    title,
    (metadata->'awards'->>'oscars')::int AS oscars_int
FROM movies
WHERE metadata->'awards' IS NOT NULL
LIMIT 5;

-- SAFE pattern with COALESCE:
SELECT
    title,
    COALESCE((metadata->'awards'->>'oscars')::int, 0) AS oscars
FROM movies
LIMIT 5;


-- ----------------------------------------------------------------------------
-- Demo: Modifying JSONB
-- ----------------------------------------------------------------------------

-- Add a new key with jsonb_set
-- (Demo only - we'll rollback)
BEGIN;

UPDATE movies
SET metadata = jsonb_set(
    metadata,
    '{director_approved}',
    'true'::jsonb
)
WHERE release_year = 2020;

SELECT title, metadata->'director_approved'
FROM movies
WHERE release_year = 2020
LIMIT 5;

ROLLBACK;


-- ----------------------------------------------------------------------------
-- EXERCISE 2: Your Turn - JSONB
-- Time: 15 minutes
-- ----------------------------------------------------------------------------

-- Exercise 2a: Find all R-rated movies
-- Query metadata for age_rating = 'R'
-- Show: title, release_year, language, streaming platform
-- Order by release_year DESC
-- Limit 20

-- YOUR CODE HERE:




-- Exercise 2b: High-budget international films
-- Find movies with budget > 100 million
-- AND language != 'English'
-- Show: title, budget, language, box_office
-- Order by budget DESC

-- YOUR CODE HERE:




-- Exercise 2c: Award winners
-- Find movies with at least 1 Oscar OR 1 Golden Globe
-- Show: title, oscar count, golden globe count
-- Order by total awards DESC
-- Hint: Use COALESCE to handle NULLs

-- YOUR CODE HERE:




-- Exercise 2d: Streaming platform analysis
-- Count movies per streaming platform
-- Show: platform name, count
-- Order by count DESC

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 4: Arrays - Code Along & Exercises (25 min)
-- ============================================================================

-- The tags column structure: TEXT[]
-- Example: ['heartwarming', 'award-winner', 'family-friendly']

-- ----------------------------------------------------------------------------
-- Demo: The 1-Indexed Gotcha (THIS TRIPS EVERYONE UP!)
-- ----------------------------------------------------------------------------

-- In most languages, arrays start at 0. NOT in PostgreSQL!

SELECT
    title,
    tags,
    tags[0] AS index_zero,   -- What do you expect?
    tags[1] AS index_one
FROM movies
LIMIT 3;
-- tags[0] returns NULL! No error, just silent failure.

-- This matters when building queries programmatically
-- If your app uses 0-based indexing, you'll get NULLs everywhere

-- Also: array_length returns NULL for empty arrays, not 0!
SELECT
    array_length(ARRAY[]::text[], 1) AS empty_array_length,
    array_length(ARRAY['a','b'], 1) AS normal_length;

-- SAFE pattern:
SELECT COALESCE(array_length(tags, 1), 0) AS safe_length
FROM movies
LIMIT 3;


-- ----------------------------------------------------------------------------
-- Demo: Array Operators (@> vs &&)
-- ----------------------------------------------------------------------------

-- @> means "contains ALL" (AND logic)
-- && means "overlaps ANY" (OR logic)

-- Contains ALL (must have BOTH tags)
SELECT title, tags
FROM movies
WHERE tags @> ARRAY['thrilling', 'award-winner']
LIMIT 5;

-- Overlaps ANY (has at least ONE of these)
SELECT title, tags
FROM movies
WHERE tags && ARRAY['thrilling', 'award-winner']
LIMIT 5;
-- Notice: more results because OR is less restrictive


-- ----------------------------------------------------------------------------
-- Demo: More Array Operations
-- ----------------------------------------------------------------------------

-- Basic array access
SELECT
    title,
    tags,
    tags[1] AS first_tag,
    tags[2] AS second_tag,
    array_length(tags, 1) AS num_tags
FROM movies
LIMIT 10;

-- Check if array contains value with @>
SELECT title, tags
FROM movies
WHERE tags @> ARRAY['heartwarming']
LIMIT 10;

-- Check if arrays overlap with &&
SELECT title, tags
FROM movies
WHERE tags && ARRAY['thrilling', 'suspenseful', 'mind-bending']
LIMIT 10;

-- Unnest array to rows
SELECT
    m.title,
    unnest(m.tags) AS tag
FROM movies m
WHERE m.movie_id = 1;

-- Aggregate tags across movies
SELECT
    tag,
    COUNT(*) AS count
FROM movies, unnest(tags) AS tag
GROUP BY tag
ORDER BY count DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- EXERCISE 3: Your Turn - Arrays
-- Time: 12 minutes
-- ----------------------------------------------------------------------------

-- Exercise 3a: Find movies with multiple specific tags
-- Find movies that have BOTH 'thrilling' AND 'mind-bending' tags
-- Show: title, tags, release_year
-- Order by imdb_rating DESC

-- YOUR CODE HERE:




-- Exercise 3b: Tag popularity analysis
-- Count how many movies have each tag
-- Show: tag name, count
-- Only show tags that appear in at least 50 movies
-- Order by count DESC

-- YOUR CODE HERE:




-- Exercise 3c: Movies with exactly 3 tags
-- Find movies that have exactly 3 tags
-- Show: title, tags
-- Limit 20

-- YOUR CODE HERE:




-- Exercise 3d: Family-friendly movies
-- Find movies with 'family-friendly' tag OR 'heartwarming' tag
-- Exclude movies with 'dark' or 'gritty' tags
-- Show: title, tags, age_rating (from metadata)
-- Order by release_year DESC

-- YOUR CODE HERE:




-- Exercise 3e: Create a tag cloud (CHALLENGE)
-- Find the top 20 most common tags
-- For each tag, show count and array of up to 5 sample movie titles
-- Show: tag, movie_count, sample_titles (array)

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 5: HSTORE - Code Along & Exercises (20 min)
-- ============================================================================

-- The preferences column structure (HSTORE):
-- 'theme=>dark, language=>en, notifications=>all, autoplay=>true, quality=>1080p'

-- ----------------------------------------------------------------------------
-- Demo: HSTORE Basics
-- ----------------------------------------------------------------------------

-- Extract single value
SELECT
    username,
    preferences->'theme' AS theme,
    preferences->'language' AS language,
    preferences->'quality' AS quality
FROM users
LIMIT 10;

-- Query by value
SELECT username, preferences->'theme' AS theme
FROM users
WHERE preferences->'theme' = 'dark'
LIMIT 10;

-- Get all keys
SELECT
    username,
    akeys(preferences) AS all_keys
FROM users
LIMIT 5;

-- Convert to JSON
SELECT
    username,
    hstore_to_json(preferences) AS preferences_json
FROM users
LIMIT 5;


-- ----------------------------------------------------------------------------
-- EXERCISE 4: Your Turn - HSTORE
-- Time: 10 minutes
-- ----------------------------------------------------------------------------

-- Exercise 4a: User preference analysis
-- Count users by theme preference
-- Show: theme, user_count
-- Order by user_count DESC

-- YOUR CODE HERE:




-- Exercise 4b: Quality preference distribution
-- Find how many users prefer each quality setting
-- Show: quality setting, count
-- Order by count DESC

-- YOUR CODE HERE:




-- Exercise 4c: Autoplay enabled users
-- Find users who have autoplay enabled
-- Show: username, theme, quality, autoplay
-- Order by username
-- Limit 20

-- YOUR CODE HERE:




-- Exercise 4d: Multi-preference filter
-- Find users with:
--   - Dark theme
--   - Autoplay enabled
--   - Quality 1080p or 4k
-- Show: username, all preferences
-- Limit 20

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 6: Wrap-up & Key Takeaways (5 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Review: Common mistakes to avoid
-- ----------------------------------------------------------------------------

-- Summary of the gotchas we saw in action:

-- 1. Arrays are 1-indexed
--    tags[0] = NULL (silent failure)
--    tags[1] = first element

-- 2. JSONB arrow operators
--    -> returns JSON (for chaining)
--    ->> returns TEXT (for WHERE clauses)

-- 3. Wrong arrow = silent failure
--    WHERE metadata->'rating' = 'PG-13'  -- returns NO rows, no error!
--    WHERE metadata->>'rating' = 'PG-13' -- correct

-- 4. NULL gotchas
--    array_length(ARRAY[]::text[], 1) = NULL (not 0!)
--    metadata->'missing_key' = NULL (no error)
--    Use COALESCE when casting JSONB values

-- Questions before we wrap up Day 1?


-- ============================================================================
-- BONUS CHALLENGES (If Time Permits)
-- ============================================================================

-- Challenge 1: Combine ALL concepts
-- Find movies that:
-- 1. Are in the 'Sci-Fi' genre
-- 2. Have budget > 50 million (JSONB)
-- 3. Have tags 'mind-bending' OR 'thrilling' (Array)
-- 4. Have been rated by users who prefer dark theme (HSTORE)
-- Show: title, budget, avg rating, number of ratings

-- YOUR CODE HERE:




-- Challenge 2: User recommendation engine
-- For a given user (pick user_id = 1):
-- Find movies they haven't rated yet
-- That match genres of their highly-rated movies (rating >= 8)
-- And have tags similar to movies they liked
-- Show: title, genres, tags, predicted interest score

-- YOUR CODE HERE:




-- ============================================================================
-- SOLUTIONS (For Instructor Reference)
-- ============================================================================

/*
-- Solution 1a: Movies with cast
SELECT
    m.title,
    p.full_name,
    mc.role,
    mc.character_name,
    mc.billing_order
FROM movies m
INNER JOIN movie_cast mc ON m.movie_id = mc.movie_id
INNER JOIN people p ON mc.person_id = p.person_id
ORDER BY m.title, mc.billing_order
LIMIT 20;

-- Solution 1b: Movies with no cast
SELECT m.title, m.release_year
FROM movies m
LEFT JOIN movie_cast mc ON m.movie_id = mc.movie_id
WHERE mc.movie_id IS NULL
ORDER BY m.release_year DESC;

-- Solution 1c: Ratings per user
SELECT
    u.username,
    COUNT(r.rating_id) AS num_ratings,
    ROUND(AVG(r.rating)::numeric, 1) AS avg_rating_given
FROM users u
INNER JOIN ratings r ON u.user_id = r.user_id
GROUP BY u.user_id, u.username
HAVING COUNT(r.rating_id) > 10
ORDER BY num_ratings DESC
LIMIT 20;

-- Solution 1d: Top-rated by genre
WITH movie_ratings AS (
    SELECT
        g.name AS genre,
        m.title,
        AVG(r.rating) AS avg_rating,
        COUNT(r.rating_id) AS num_ratings
    FROM genres g
    INNER JOIN movie_genres mg ON g.genre_id = mg.genre_id
    INNER JOIN movies m ON mg.movie_id = m.movie_id
    INNER JOIN ratings r ON m.movie_id = r.movie_id
    GROUP BY g.genre_id, g.name, m.movie_id, m.title
    HAVING COUNT(r.rating_id) >= 10
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY genre ORDER BY avg_rating DESC) AS rank
    FROM movie_ratings
)
SELECT genre, title, ROUND(avg_rating::numeric, 1) AS avg_rating, num_ratings
FROM ranked
WHERE rank <= 3
ORDER BY genre, rank;

-- Solution 2a: R-rated movies
SELECT
    title,
    release_year,
    metadata->>'language' AS language,
    metadata->>'streaming' AS streaming
FROM movies
WHERE metadata->>'age_rating' = 'R'
ORDER BY release_year DESC
LIMIT 20;

-- Solution 2b: High-budget international
SELECT
    title,
    (metadata->>'budget_millions')::int AS budget,
    metadata->>'language' AS language,
    (metadata->>'box_office_millions')::int AS box_office
FROM movies
WHERE (metadata->>'budget_millions')::int > 100
  AND metadata->>'language' != 'English'
ORDER BY (metadata->>'budget_millions')::int DESC;

-- Solution 2c: Award winners
SELECT
    title,
    COALESCE((metadata->'awards'->>'oscars')::int, 0) AS oscars,
    COALESCE((metadata->'awards'->>'golden_globes')::int, 0) AS golden_globes
FROM movies
WHERE
    COALESCE((metadata->'awards'->>'oscars')::int, 0) >= 1
    OR COALESCE((metadata->'awards'->>'golden_globes')::int, 0) >= 1
ORDER BY
    COALESCE((metadata->'awards'->>'oscars')::int, 0) +
    COALESCE((metadata->'awards'->>'golden_globes')::int, 0) DESC
LIMIT 20;

-- Solution 2d: Platform analysis
SELECT
    metadata->>'streaming' AS platform,
    COUNT(*) AS movie_count
FROM movies
WHERE metadata->>'streaming' IS NOT NULL
GROUP BY metadata->>'streaming'
ORDER BY movie_count DESC;

-- Solution 3a: Multiple tags
SELECT title, tags, release_year
FROM movies
WHERE tags @> ARRAY['thrilling', 'mind-bending']
ORDER BY imdb_rating DESC;

-- Solution 3b: Tag popularity
SELECT
    tag,
    COUNT(*) AS movie_count
FROM movies, unnest(tags) AS tag
GROUP BY tag
HAVING COUNT(*) >= 50
ORDER BY movie_count DESC;

-- Solution 3c: Exactly 3 tags
SELECT title, tags
FROM movies
WHERE array_length(tags, 1) = 3
LIMIT 20;

-- Solution 3d: Family-friendly
SELECT
    title,
    tags,
    metadata->>'age_rating' AS age_rating
FROM movies
WHERE (tags && ARRAY['family-friendly', 'heartwarming'])
  AND NOT (tags && ARRAY['dark', 'gritty'])
ORDER BY release_year DESC
LIMIT 20;

-- Solution 3e: Tag cloud
WITH tag_counts AS (
    SELECT
        tag,
        COUNT(*) AS movie_count,
        array_agg(m.title ORDER BY random()) AS all_titles
    FROM movies m, unnest(m.tags) AS tag
    GROUP BY tag
)
SELECT
    tag,
    movie_count,
    all_titles[1:5] AS sample_titles
FROM tag_counts
ORDER BY movie_count DESC
LIMIT 20;

-- Solution 4a: Theme analysis
SELECT
    preferences->'theme' AS theme,
    COUNT(*) AS user_count
FROM users
WHERE preferences ? 'theme'
GROUP BY preferences->'theme'
ORDER BY user_count DESC;

-- Solution 4b: Quality distribution
SELECT
    preferences->'quality' AS quality,
    COUNT(*) AS user_count
FROM users
WHERE preferences ? 'quality'
GROUP BY preferences->'quality'
ORDER BY user_count DESC;

-- Solution 4c: Autoplay users
SELECT
    username,
    preferences->'theme' AS theme,
    preferences->'quality' AS quality,
    preferences->'autoplay' AS autoplay
FROM users
WHERE preferences->'autoplay' = 'true'
ORDER BY username
LIMIT 20;

-- Solution 4d: Multi-preference
SELECT
    username,
    preferences
FROM users
WHERE preferences->'theme' = 'dark'
  AND preferences->'autoplay' = 'true'
  AND preferences->'quality' IN ('1080p', '4k')
LIMIT 20;
*/
