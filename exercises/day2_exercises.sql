-- ============================================================================
-- DAY 2 HANDS-ON LAB: Functions, Triggers & Error Handling
-- Intermediate PostgreSQL Course
-- Duration: ~2 hours (instructor-led with exercises)
-- Database: movies_db
--
-- TIMING:
--   Section 1: Built-in Functions Warmup (15 min)
--   Section 2: Writing Custom Functions (40 min)
--   Section 3: Error Handling (15 min)
--   Section 4: Triggers (40 min)
--   Section 5: Wrap-up (5 min)
--   Total: ~115 minutes (buffer for questions)
--
-- Run this lab AFTER the lecture.
-- We'll build progressively more complex functions and triggers.
-- ============================================================================

-- ============================================================================
-- SECTION 1: Built-in Functions Warmup (15 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo: String Functions
-- ----------------------------------------------------------------------------

-- Basic string manipulation
SELECT
    title,
    UPPER(title) AS shouting,
    LOWER(title) AS whisper,
    LENGTH(title) AS char_count,
    LEFT(title, 15) || '...' AS truncated
FROM movies
WHERE LENGTH(title) > 20
LIMIT 5;

-- String searching and replacing
SELECT
    title,
    POSITION('the' IN LOWER(title)) AS the_position,
    REPLACE(title, 'The', 'A') AS replaced
FROM movies
WHERE LOWER(title) LIKE '%the%'
LIMIT 5;

-- FORMAT function (like sprintf)
SELECT FORMAT('Movie: %s (Year: %s, Rating: %s)',
    title, release_year, imdb_rating) AS formatted
FROM movies
LIMIT 3;


-- ----------------------------------------------------------------------------
-- Demo: Aggregate Functions
-- ----------------------------------------------------------------------------

-- Basic aggregates with GROUP BY
SELECT
    EXTRACT(YEAR FROM rated_at) AS year,
    COUNT(*) AS total_ratings,
    ROUND(AVG(rating), 2) AS avg_rating,
    MIN(rating) AS lowest,
    MAX(rating) AS highest
FROM ratings
GROUP BY EXTRACT(YEAR FROM rated_at)
ORDER BY year;

-- FILTER clause for conditional aggregation
SELECT
    COUNT(*) AS total_movies,
    COUNT(*) FILTER (WHERE imdb_rating >= 8) AS excellent_count,
    COUNT(*) FILTER (WHERE imdb_rating >= 6 AND imdb_rating < 8) AS good_count,
    COUNT(*) FILTER (WHERE imdb_rating < 6) AS below_good_count
FROM movies;


-- ----------------------------------------------------------------------------
-- Demo: Date/Time Functions
-- ----------------------------------------------------------------------------

-- Extracting parts from timestamps
SELECT
    rated_at,
    EXTRACT(YEAR FROM rated_at) AS year,
    EXTRACT(MONTH FROM rated_at) AS month,
    EXTRACT(DOW FROM rated_at) AS day_of_week,  -- 0=Sunday
    TO_CHAR(rated_at, 'Day, Month DD, YYYY') AS formatted
FROM ratings
LIMIT 5;

-- Date arithmetic
SELECT
    title,
    release_year,
    CURRENT_DATE - make_date(release_year, 1, 1) AS days_since_release,
    AGE(CURRENT_DATE, make_date(release_year, 1, 1)) AS age
FROM movies
WHERE release_year IS NOT NULL
ORDER BY release_year DESC
LIMIT 5;


-- ----------------------------------------------------------------------------
-- Exercise 1: Your Turn - Built-in Functions
-- Time: 10 minutes
-- ----------------------------------------------------------------------------

-- Exercise 1a: Movie title analysis
-- Find movies where the title length is more than 30 characters
-- Show: title, length, first 25 chars with '...' appended
-- Order by length DESC
-- Limit 10

-- YOUR CODE HERE:




-- Exercise 1b: Rating statistics by month
-- Show rating statistics grouped by month (regardless of year)
-- Show: month name, total ratings, average rating (rounded to 2 decimals)
-- Order by total ratings DESC

-- YOUR CODE HERE:




-- Exercise 1c: Genre popularity with conditional counts
-- For each genre, count:
--   - Total movies
--   - Movies with rating >= 7
--   - Movies released after 2015
-- Order by total movies DESC

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 2: Writing Custom Functions (40 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo: Simple Function - Get Movie Rating
-- ----------------------------------------------------------------------------

-- Building on Day 1: remember dollar quoting? Here's where it really shines.
-- Let's create a function that gets the average rating for a movie
CREATE OR REPLACE FUNCTION get_movie_avg_rating(p_movie_id INT)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_avg_rating NUMERIC;
BEGIN
    SELECT AVG(rating)
    INTO v_avg_rating
    FROM ratings
    WHERE movie_id = p_movie_id;

    RETURN ROUND(COALESCE(v_avg_rating, 0), 2);
END;
$$;

-- Test it
SELECT get_movie_avg_rating(1);
SELECT title, get_movie_avg_rating(movie_id) AS avg_rating
FROM movies
LIMIT 5;


-- ----------------------------------------------------------------------------
-- Demo: Function with Multiple Return Values
-- ----------------------------------------------------------------------------

-- Return multiple values using OUT parameters
CREATE OR REPLACE FUNCTION get_movie_stats(
    p_movie_id INT,
    OUT avg_rating NUMERIC,
    OUT rating_count INT,
    OUT highest_rating INT,
    OUT lowest_rating INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
        ROUND(AVG(rating), 2),
        COUNT(*)::INT,
        MAX(rating),
        MIN(rating)
    INTO avg_rating, rating_count, highest_rating, lowest_rating
    FROM ratings
    WHERE movie_id = p_movie_id;
END;
$$;

-- Test it - returns a record
SELECT * FROM get_movie_stats(1);

-- Use in a query
SELECT
    m.title,
    (get_movie_stats(m.movie_id)).*
FROM movies m
WHERE m.movie_id <= 5;


-- ----------------------------------------------------------------------------
-- Demo: Function Returning a Table
-- ----------------------------------------------------------------------------

-- Return multiple rows
CREATE OR REPLACE FUNCTION get_top_movies_by_genre(
    p_genre_name TEXT,
    p_limit INT DEFAULT 5
)
RETURNS TABLE(
    title TEXT,
    release_year INT,
    avg_rating NUMERIC,
    rating_count BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.title,
        m.release_year,
        ROUND(AVG(r.rating), 2) AS avg_rating,
        COUNT(r.rating_id) AS rating_count
    FROM movies m
    JOIN movie_genres mg ON m.movie_id = mg.movie_id
    JOIN genres g ON mg.genre_id = g.genre_id
    JOIN ratings r ON m.movie_id = r.movie_id
    WHERE g.name = p_genre_name
    GROUP BY m.movie_id, m.title, m.release_year
    HAVING COUNT(r.rating_id) >= 10
    ORDER BY AVG(r.rating) DESC
    LIMIT p_limit;
END;
$$;

-- Test it
SELECT * FROM get_top_movies_by_genre('Action');
SELECT * FROM get_top_movies_by_genre('Comedy', 3);


-- ----------------------------------------------------------------------------
-- Demo: Function with Control Flow
-- ----------------------------------------------------------------------------

-- More complex logic with IF statements
CREATE OR REPLACE FUNCTION get_rating_summary(p_movie_id INT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_avg NUMERIC;
    v_count INT;
    v_label TEXT;
BEGIN
    -- Get the stats
    SELECT AVG(rating), COUNT(*)
    INTO v_avg, v_count
    FROM ratings
    WHERE movie_id = p_movie_id;

    -- Check if we have any ratings
    IF v_count = 0 THEN
        RETURN 'No ratings yet';
    END IF;

    -- Determine the label
    IF v_avg >= 8 THEN
        v_label := 'Excellent';
    ELSIF v_avg >= 6 THEN
        v_label := 'Good';
    ELSIF v_avg >= 4 THEN
        v_label := 'Fair';
    ELSE
        v_label := 'Poor';
    END IF;

    RETURN FORMAT('%s (%s avg from %s ratings)', v_label, ROUND(v_avg, 1), v_count);
END;
$$;

-- Test it
SELECT title, get_rating_summary(movie_id) AS summary
FROM movies
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Exercise 2: Your Turn - Custom Functions
-- Time: 20 minutes
-- ----------------------------------------------------------------------------

-- Exercise 2a: Create get_user_rating_count
-- Create a function that takes a user_id
-- Returns the number of ratings that user has made
-- If user doesn't exist or has no ratings, return 0

-- YOUR CODE HERE:




-- Test your function:
-- SELECT get_user_rating_count(1);
-- SELECT username, get_user_rating_count(user_id) AS rating_count
-- FROM users LIMIT 10;


-- Exercise 2b: Create get_genre_stats
-- Create a function that takes a genre name
-- Returns a TABLE with: movie_count, avg_rating, avg_runtime
-- Handle case where genre doesn't exist (return zeros)

-- YOUR CODE HERE:




-- Test your function:
-- SELECT * FROM get_genre_stats('Action');
-- SELECT * FROM get_genre_stats('NonExistent');


-- Exercise 2c: Create search_movies_by_keyword
-- Create a function that takes a keyword parameter
-- Returns movies where title OR tags contain the keyword (case-insensitive)
-- Return: movie_id, title, release_year, imdb_rating, matching_tags
-- Limit to 20 results, ordered by imdb_rating DESC
-- Hint: Use ILIKE for title, and array operators for tags

-- YOUR CODE HERE:




-- Test your function:
-- SELECT * FROM search_movies_by_keyword('robot');
-- SELECT * FROM search_movies_by_keyword('love');


-- ============================================================================
-- SECTION 3: Error Handling (15 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo: Basic Exception Handling
-- ----------------------------------------------------------------------------

-- Function that might fail without handling
CREATE OR REPLACE FUNCTION unsafe_get_rating(p_movie_id INT)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_rating NUMERIC;
BEGIN
    -- This will fail if no rows found with STRICT
    SELECT rating INTO STRICT v_rating
    FROM ratings
    WHERE movie_id = p_movie_id
    LIMIT 1;

    RETURN v_rating;
END;
$$;

-- This works:
SELECT unsafe_get_rating(1);

-- Try with a movie_id that might have no ratings (or doesn't exist):
-- SELECT unsafe_get_rating(99999);  -- May throw NO_DATA_FOUND


-- Now with proper error handling:
CREATE OR REPLACE FUNCTION safe_get_rating(p_movie_id INT)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_rating NUMERIC;
BEGIN
    SELECT rating INTO STRICT v_rating
    FROM ratings
    WHERE movie_id = p_movie_id
    LIMIT 1;

    RETURN v_rating;
EXCEPTION
    WHEN no_data_found THEN
        RETURN NULL;
    WHEN too_many_rows THEN
        -- This won't happen due to LIMIT 1, but showing the pattern
        RETURN NULL;
END;
$$;

-- Now it handles missing data gracefully
SELECT safe_get_rating(99999);  -- Returns NULL instead of error


-- ----------------------------------------------------------------------------
-- Demo: RAISE for Custom Errors and Logging
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION add_rating(
    p_movie_id INT,
    p_user_id INT,
    p_rating INT
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
    -- Validate rating range
    IF p_rating < 1 OR p_rating > 10 THEN
        RAISE EXCEPTION 'Rating must be between 1 and 10, got: %', p_rating
            USING HINT = 'Please provide a rating from 1 to 10';
    END IF;

    -- Validate movie exists
    IF NOT EXISTS (SELECT 1 FROM movies WHERE movie_id = p_movie_id) THEN
        RAISE EXCEPTION 'Movie with id % does not exist', p_movie_id;
    END IF;

    -- Validate user exists
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id) THEN
        RAISE EXCEPTION 'User with id % does not exist', p_user_id;
    END IF;

    -- Log what we're doing
    RAISE NOTICE 'Adding rating % for movie % by user %',
        p_rating, p_movie_id, p_user_id;

    -- Insert the rating
    INSERT INTO ratings (movie_id, user_id, rating)
    VALUES (p_movie_id, p_user_id, p_rating);

    RETURN 'Rating added successfully';

EXCEPTION
    WHEN unique_violation THEN
        RETURN 'User has already rated this movie';
    WHEN OTHERS THEN
        RETURN FORMAT('Unexpected error: %s', SQLERRM);
END;
$$;

-- Test validation
SELECT add_rating(1, 1, 15);  -- Invalid rating
SELECT add_rating(99999, 1, 5);  -- Invalid movie

-- Test success (may fail if rating already exists)
-- SELECT add_rating(1, 5001, 8);  -- Should work if user 5001 hasn't rated movie 1


-- ----------------------------------------------------------------------------
-- Exercise 3: Your Turn - Add Error Handling
-- Time: 10 minutes
-- ----------------------------------------------------------------------------

-- Exercise 3a: Improve get_genre_stats with error handling
-- Take your get_genre_stats function and add:
-- 1. RAISE NOTICE when the genre is found (for debugging)
-- 2. Handle the case where genre doesn't exist with a proper message
-- 3. Use GET STACKED DIAGNOSTICS to capture any unexpected errors

-- YOUR CODE HERE (modify your earlier function):




-- Exercise 3b: Create safe_update_movie_rating
-- Create a function that updates a movie's imdb_rating
-- Parameters: p_movie_id INT, p_new_rating NUMERIC
-- Validations:
--   - Rating must be between 0 and 10
--   - Movie must exist
-- Return 'Success' or descriptive error message
-- Use proper EXCEPTION handling

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 4: Triggers (40 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo: Auto-Update Timestamps
-- ----------------------------------------------------------------------------

-- First, let's see the current state
SELECT movie_id, title, updated_at FROM movies LIMIT 3;

-- Create a trigger function for updating timestamps
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

-- Attach it to the movies table
DROP TRIGGER IF EXISTS set_movies_timestamp ON movies;
CREATE TRIGGER set_movies_timestamp
    BEFORE UPDATE ON movies
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

-- Test it
UPDATE movies SET imdb_rating = imdb_rating WHERE movie_id = 1;
SELECT movie_id, title, updated_at FROM movies WHERE movie_id = 1;
-- Notice updated_at changed!


-- ----------------------------------------------------------------------------
-- Demo: Maintaining popularity_cache
-- ----------------------------------------------------------------------------

-- Let's see current popularity_cache state
SELECT * FROM popularity_cache LIMIT 5;

-- Create trigger function to update cache when ratings change
CREATE OR REPLACE FUNCTION refresh_popularity_cache()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_movie_id INT;
BEGIN
    -- Determine which movie was affected
    IF TG_OP = 'DELETE' THEN
        v_movie_id := OLD.movie_id;
    ELSE
        v_movie_id := NEW.movie_id;
    END IF;

    -- Update the cache for this movie
    UPDATE popularity_cache
    SET
        avg_rating = (
            SELECT ROUND(AVG(rating), 2)
            FROM ratings
            WHERE movie_id = v_movie_id
        ),
        rating_count = (
            SELECT COUNT(*)
            FROM ratings
            WHERE movie_id = v_movie_id
        ),
        last_updated = NOW()
    WHERE movie_id = v_movie_id;

    -- For INSERT/UPDATE return NEW, for DELETE return OLD
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- Create the trigger
DROP TRIGGER IF EXISTS update_popularity_on_rating ON ratings;
CREATE TRIGGER update_popularity_on_rating
    AFTER INSERT OR UPDATE OR DELETE ON ratings
    FOR EACH ROW
    EXECUTE FUNCTION refresh_popularity_cache();

-- Test it
-- First, check current state
SELECT pc.movie_id, m.title, pc.avg_rating, pc.rating_count, pc.last_updated
FROM popularity_cache pc
JOIN movies m ON pc.movie_id = m.movie_id
WHERE pc.movie_id = 1;

-- Add a new rating
INSERT INTO ratings (movie_id, user_id, rating)
VALUES (1, (SELECT user_id FROM users ORDER BY random() LIMIT 1), 10);

-- Check if cache updated
SELECT pc.movie_id, m.title, pc.avg_rating, pc.rating_count, pc.last_updated
FROM popularity_cache pc
JOIN movies m ON pc.movie_id = m.movie_id
WHERE pc.movie_id = 1;
-- Notice: rating_count increased, last_updated changed!


-- ----------------------------------------------------------------------------
-- Demo: Audit Logging
-- ----------------------------------------------------------------------------

-- Create an audit table
DROP TABLE IF EXISTS rating_audit;
CREATE TABLE rating_audit (
    audit_id SERIAL PRIMARY KEY,
    operation TEXT NOT NULL,
    movie_id INT,
    user_id INT,
    old_rating INT,
    new_rating INT,
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    changed_by TEXT DEFAULT CURRENT_USER
);

-- Create audit trigger function
CREATE OR REPLACE FUNCTION log_rating_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO rating_audit (operation, movie_id, user_id, new_rating)
        VALUES ('INSERT', NEW.movie_id, NEW.user_id, NEW.rating);
    ELSIF TG_OP = 'UPDATE' THEN
        -- Only log if rating actually changed
        IF OLD.rating != NEW.rating THEN
            INSERT INTO rating_audit (operation, movie_id, user_id, old_rating, new_rating)
            VALUES ('UPDATE', NEW.movie_id, NEW.user_id, OLD.rating, NEW.rating);
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO rating_audit (operation, movie_id, user_id, old_rating)
        VALUES ('DELETE', OLD.movie_id, OLD.user_id, OLD.rating);
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- Create the trigger
DROP TRIGGER IF EXISTS audit_ratings ON ratings;
CREATE TRIGGER audit_ratings
    AFTER INSERT OR UPDATE OR DELETE ON ratings
    FOR EACH ROW
    EXECUTE FUNCTION log_rating_changes();

-- Test it
INSERT INTO ratings (movie_id, user_id, rating)
VALUES (2, (SELECT user_id FROM users ORDER BY random() LIMIT 1), 7);

-- Check the audit log
SELECT * FROM rating_audit ORDER BY audit_id DESC LIMIT 5;


-- ----------------------------------------------------------------------------
-- Exercise 4: Your Turn - Create Triggers
-- Time: 20 minutes
-- ----------------------------------------------------------------------------

-- Exercise 4a: Create timestamp trigger for users table
-- Create a trigger that automatically updates created_at on the users table
-- When a user record is updated, set a new column 'last_active' to NOW()
-- First, add the column if needed:
-- ALTER TABLE users ADD COLUMN IF NOT EXISTS last_active TIMESTAMPTZ;

-- YOUR CODE HERE:




-- Test:
-- UPDATE users SET country = country WHERE user_id = 1;
-- SELECT user_id, username, last_active FROM users WHERE user_id = 1;


-- Exercise 4b: Create validation trigger
-- Create a BEFORE INSERT trigger on ratings that:
-- 1. Checks that the rating is between 1 and 10
-- 2. If invalid, raise an exception with a helpful message
-- Note: This duplicates the CHECK constraint but shows trigger validation

-- YOUR CODE HERE:




-- Test:
-- INSERT INTO ratings (movie_id, user_id, rating) VALUES (1, 1, 15);
-- Should fail with your custom message


-- ----------------------------------------------------------------------------
-- OPTIONAL CHALLENGE: Trending Notification Trigger
-- (Skip if short on time - this is bonus material)
-- ----------------------------------------------------------------------------

-- Exercise 4c (OPTIONAL): Create a "trending" notification trigger
-- Create a trigger that:
-- 1. Fires after INSERT on ratings
-- 2. Checks if the movie now has > 100 ratings
-- 3. If so, inserts a record into a new 'notifications' table
-- First create the table:
DROP TABLE IF EXISTS notifications;
CREATE TABLE notifications (
    notification_id SERIAL PRIMARY KEY,
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- YOUR CODE HERE:




-- ============================================================================
-- SECTION 5: Wrap-up & Key Takeaways (5 min)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Review: Key patterns we learned today
-- ----------------------------------------------------------------------------

-- 1. Function structure
/*
CREATE OR REPLACE FUNCTION name(params)
RETURNS type
LANGUAGE plpgsql
AS $$
DECLARE
    variables;
BEGIN
    logic;
    RETURN value;
EXCEPTION
    WHEN condition THEN handle;
END;
$$;
*/

-- 2. Trigger function structure
/*
CREATE OR REPLACE FUNCTION trigger_func()
RETURNS TRIGGER
AS $$
BEGIN
    -- Use NEW for INSERT/UPDATE, OLD for UPDATE/DELETE
    -- Return NEW or OLD (NULL cancels in BEFORE trigger)
END;
$$;

CREATE TRIGGER name
    BEFORE/AFTER INSERT/UPDATE/DELETE
    ON table FOR EACH ROW
    EXECUTE FUNCTION trigger_func();
*/

-- 3. Error handling
/*
EXCEPTION
    WHEN no_data_found THEN ...
    WHEN unique_violation THEN ...
    WHEN OTHERS THEN ...
*/

-- Clean up demo objects (optional)
-- DROP TRIGGER IF EXISTS audit_ratings ON ratings;
-- DROP TRIGGER IF EXISTS update_popularity_on_rating ON ratings;
-- DROP TABLE IF EXISTS rating_audit;
-- DROP TABLE IF EXISTS notifications;

