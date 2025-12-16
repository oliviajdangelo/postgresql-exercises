-- seed_monitoring_data.sql
-- Purpose: Populate pg_stat_statements with slow or inefficient queries
-- so you can demonstrate monitoring, diagnosis, and tuning.
--
-- IMPORTANT: Run this AFTER loading movies_dataset.sql
-- This script creates realistic query activity for performance monitoring exercises

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Reset pg_stat_statements to start fresh
SELECT pg_stat_statements_reset();

-- Set random seed for reproducible query patterns across all database instances
SELECT setseed(0.43);

------------------------------------------------------------
-- 1. Repeated wildcard searches (slow due to seq scans)
------------------------------------------------------------

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..200 LOOP
        PERFORM *
        FROM movies
        WHERE title ILIKE '%' || (ARRAY[
            'dog','summer','train','cloud','echo','lantern','parrot','dream',
            'library','penguin','miracle','moon','robot','lighthouse','garden'
        ])[1 + ((random() * 1000)::int % 15)]
        || '%';
    END LOOP;
END $$;

------------------------------------------------------------
-- 2. JSONB metadata lookups (no indexes → slow)
------------------------------------------------------------

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..150 LOOP
        PERFORM movie_id
        FROM movies
        WHERE metadata->>'streaming' = (ARRAY[
            'Streamly','CinePlus','BingeNow','PrimeShow'
        ])[1 + ((random() * 1000)::int % 4)];
    END LOOP;
END $$;

------------------------------------------------------------
-- 3. Multi-table join with ORDER BY + LIMIT (common bottleneck)
------------------------------------------------------------

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..200 LOOP
        PERFORM m.title, p.full_name, r.rating
        FROM ratings r
        JOIN movies m ON m.movie_id = r.movie_id
        JOIN movie_cast mc ON mc.movie_id = m.movie_id
        JOIN people p ON p.person_id = mc.person_id
        ORDER BY r.rated_at DESC
        LIMIT 20;
    END LOOP;
END $$;

------------------------------------------------------------
-- 4. Aggregation queries (stress CPU + grouping)
------------------------------------------------------------

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..150 LOOP
        PERFORM movie_id, AVG(rating)
        FROM ratings
        GROUP BY movie_id
        HAVING COUNT(*) > 10;
    END LOOP;
END $$;

------------------------------------------------------------
-- 5. Cross-filter queries with IN predicates
------------------------------------------------------------

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..150 LOOP
        PERFORM *
        FROM ratings r
        WHERE r.rating IN (
            (1 + ((random() * 1000)::int % 10)),
            (1 + ((random() * 1000)::int % 10)),
            (1 + ((random() * 1000)::int % 10))
        );
    END LOOP;
END $$;

------------------------------------------------------------
-- 6. Missing-index join + ORDER BY (forces sort)
------------------------------------------------------------

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..200 LOOP
        PERFORM *
        FROM movie_cast mc
        JOIN people p ON p.person_id = mc.person_id
        ORDER BY p.full_name;
    END LOOP;
END $$;

------------------------------------------------------------
-- 7. Correlated subquery (intentionally inefficient)
------------------------------------------------------------

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..120 LOOP
        PERFORM title
        FROM movies m
        WHERE imdb_rating > (
            SELECT AVG(imdb_rating)
            FROM movies m2
            WHERE m2.release_year = m.release_year
        );
    END LOOP;
END $$;

------------------------------------------------------------
-- 8. Array operations without GIN index
------------------------------------------------------------

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..100 LOOP
        PERFORM *
        FROM movies
        WHERE tags @> ARRAY[(ARRAY[
            'heartwarming','thrilling','mind-bending','hilarious','emotional','intense'
        ])[1 + ((random() * 1000)::int % 6)]];
    END LOOP;
END $$;

------------------------------------------------------------
-- 9. Full-text search without proper index
------------------------------------------------------------

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..100 LOOP
        PERFORM *
        FROM movies
        WHERE search_vector @@ to_tsquery('english', (ARRAY[
            'robot','penguin','detective','adventure','mystery','cloud'
        ])[1 + ((random() * 1000)::int % 6)]);
    END LOOP;
END $$;

------------------------------------------------------------
-- Done - Display summary
------------------------------------------------------------

SELECT 'Monitoring data seeded successfully!' AS status;

-- Show top slow queries
SELECT
    query,
    calls,
    ROUND(total_exec_time::numeric, 2) AS total_time_ms,
    ROUND(mean_exec_time::numeric, 2) AS mean_time_ms,
    ROUND((100 * total_exec_time / SUM(total_exec_time) OVER ())::numeric, 2) AS pct_total_time
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 10;

-- End of seed_monitoring_data.sql
