-- movies_dataset.sql
-- Creates schema and seeds synthetic data for the Intermediate PostgreSQL Course
-- Covers advanced data types, indexing, performance tuning, locking scenarios
-- All data is artificial and safe for training.

BEGIN;

-- Drop existing tables if re-running
DROP TABLE IF EXISTS ratings CASCADE;
DROP TABLE IF EXISTS movie_cast CASCADE;
DROP TABLE IF EXISTS movie_genres CASCADE;
DROP TABLE IF EXISTS watchlist CASCADE;
DROP TABLE IF EXISTS popularity_cache CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS genres CASCADE;
DROP TABLE IF EXISTS people CASCADE;
DROP TABLE IF EXISTS movies CASCADE;

------------------------------------------------------------
-- Create extensions first (required before schema creation)
------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS hstore;

-- Set random seed for reproducible data across all database instances
SELECT setseed(0.42);

------------------------------------------------------------
-- Schema with Advanced Data Types
------------------------------------------------------------

CREATE TABLE movies (
    movie_id        SERIAL PRIMARY KEY,
    title           TEXT NOT NULL,
    release_year    INT,
    runtime_min     INT,
    imdb_rating     NUMERIC(3,1),
    tags            TEXT[],                      -- ARRAY: for keyword search
    metadata        JSONB,                       -- JSONB: flexible metadata
    search_vector   TSVECTOR,                    -- Full-text search
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE people (
    person_id   SERIAL PRIMARY KEY,
    full_name   TEXT NOT NULL,
    birth_year  INT,
    bio         TEXT
);

CREATE TABLE movie_cast (
    movie_id       INT REFERENCES movies(movie_id) ON DELETE CASCADE,
    person_id      INT REFERENCES people(person_id) ON DELETE CASCADE,
    role           TEXT,
    character_name TEXT,
    billing_order  INT,
    PRIMARY KEY (movie_id, person_id, role)
);

CREATE TABLE genres (
    genre_id SERIAL PRIMARY KEY,
    name     TEXT NOT NULL UNIQUE
);

CREATE TABLE movie_genres (
    movie_id INT REFERENCES movies(movie_id) ON DELETE CASCADE,
    genre_id INT REFERENCES genres(genre_id) ON DELETE CASCADE,
    PRIMARY KEY (movie_id, genre_id)
);

CREATE TABLE users (
    user_id       SERIAL PRIMARY KEY,
    username      TEXT NOT NULL UNIQUE,
    email         TEXT,
    country       TEXT,
    preferences   HSTORE,                        -- HSTORE: key-value user settings
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE ratings (
    rating_id     SERIAL PRIMARY KEY,
    movie_id      INT REFERENCES movies(movie_id) ON DELETE CASCADE,
    user_id       INT REFERENCES users(user_id) ON DELETE CASCADE,
    rating        INT NOT NULL CHECK (rating BETWEEN 1 AND 10),
    rated_at      TIMESTAMPTZ DEFAULT NOW(),
    review_title  TEXT,
    review_text   TEXT,
    helpful_count INT DEFAULT 0
);

-- Table for demonstrating locking scenarios
CREATE TABLE popularity_cache (
    movie_id       INT PRIMARY KEY REFERENCES movies(movie_id) ON DELETE CASCADE,
    view_count     BIGINT DEFAULT 0,
    avg_rating     NUMERIC(3,2),
    rating_count   INT DEFAULT 0,
    last_updated   TIMESTAMPTZ DEFAULT NOW()
);

-- Watchlist for many-to-many relationship examples
CREATE TABLE watchlist (
    user_id    INT REFERENCES users(user_id) ON DELETE CASCADE,
    movie_id   INT REFERENCES movies(movie_id) ON DELETE CASCADE,
    added_at   TIMESTAMPTZ DEFAULT NOW(),
    watched    BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (user_id, movie_id)
);

------------------------------------------------------------
-- Seed genres
------------------------------------------------------------

INSERT INTO genres (name) VALUES
  ('Action'),
  ('Adventure'),
  ('Comedy'),
  ('Drama'),
  ('Sci-Fi'),
  ('Fantasy'),
  ('Thriller'),
  ('Romance'),
  ('Animation'),
  ('Documentary'),
  ('Horror'),
  ('Mystery'),
  ('Musical'),
  ('Western'),
  ('Crime');

------------------------------------------------------------
-- Seed movies (~500) with combinatorial titles and standalone quirky titles
------------------------------------------------------------

WITH movie_base AS (
    SELECT
        gs AS movie_num,
        -- Build more natural titles using combinatorial approach + standalone quirky titles
        (
          CASE
            WHEN random() < 0.3 THEN
              -- Fully quirky standalone titles (whimsical, not tech-punny)
              (ARRAY[
                'Midnight at the Carousel',
                'Time Travel for Beginners',
                'Rent-Controlled Miracles',
                'Echoes of Tuesday',
                'We Regret to Inform You About the Ending',
                'Almost Famous in Ohio',
                'The Dog Who Solved Crimes',
                'Cats, Dogs, and One Confused Penguin',
                'Parrot with a Passport',
                'The Train That Never Left',
                'Clouds Are Not Real',
                'Sprinkles & the Universe',
                'Biscuit the Brave',
                'Space Tourism Gone Wrong',
                'A Brief History of Left Turns',
                'Subway Serenade',
                'Lighthouse for Lost Phones',
                'The Library of Misplaced Ideas',
                'Three Tuesdays in April',
                'Pineapples Don''t Belong Here',
                'The Great Sock Conspiracy',
                'Breakfast at Midnight',
                'Dancing with Hedgehogs',
                'Penguins of Wall Street',
                'The Secret Life of Toasters',
                'The Pickle Paradox',
                'The Last Donut',
                'Mission: Find My Keys',
                'The Fast and the Furiously Polite',
                'Silence of the Llamas',
                'The Godfather of Sourdough',
                'Underwater Basket Weaving: The Movie',
                'Seven Llamas and a Saxophone',
                'The Incredibly True Adventure of Two Ferrets',
                'Everyone Forgot About Steve',
                'The Backwards Marathon',
                'Muffins at Dawn',
                'The Penguin Who Said No',
                'Tuesdays with Maurice (The Cat)',
                'When Pigeons Attack',
                'The Mysterious Case of the Missing Spatula'
              ])[1 + (floor(random() * 40))::INT]
            ELSE
              -- Combinatorial titles like "Jupiter Rising", "Robot Odyssey"
              (
                CASE WHEN random() < 0.5 THEN 'The ' ELSE '' END
              ) ||
              (ARRAY[
                'Jupiter','Dog','Nebula','Train','Penguin','Algorithm','Ferret','Moonlight',
                'Tuesday','Parrot','Miracle','Cloud','Rocket','Carousel','Garden','Echo',
                'Secret','Summer','Midnight','Galaxy','Robot','Chef','Lighthouse','Comet',
                'Subway','Library','Dream','River','Storm','Signal','Playlist','Postcard',
                'Umbrella','Lantern','Notebook','Horizon','Traffic','Elevator','Phoenix',
                'Atlas','Harbor','Compass','Cascade','Oracle','Prism','Zenith','Archive'
              ])[1 + (floor(random() * 46))::INT]
              || ' ' ||
              (ARRAY[
                'Rising','Returns','Origins','Legacy','Eclipse','Awakening','Chronicles','Odyssey',
                'Mystery','Story','Diaries','Files','Club','Paradox','Project','Theory','Quest',
                'Adventure','Experiment','Weekend','Problem','Protocol','Blueprint','Phenomenon',
                'Convergence','Sequence','Directive'
              ])[1 + (floor(random() * 26))::INT]
          END
        ) AS title,
        1970 + (random() * 54)::INT AS release_year,   -- 1970–2024
        85 + (random() * 75)::INT AS runtime_min,      -- 85–160
        ROUND((4.5 + random() * 5)::NUMERIC, 1) AS imdb_rating -- 4.5–9.5
    FROM generate_series(1, 500) AS gs
)
INSERT INTO movies (title, release_year, runtime_min, imdb_rating, tags, metadata, created_at, updated_at)
SELECT
    mb.title,
    mb.release_year,
    mb.runtime_min,
    mb.imdb_rating,
    -- ARRAY column with tags (1-5 tags per movie for variety)
    array_remove(ARRAY[
        (ARRAY['heartwarming', 'thrilling', 'mind-bending', 'hilarious', 'emotional', 'intense', 'quirky', 'suspenseful'])[1 + (random() * 7)::INT],
        (ARRAY['award-winner', 'cult-classic', 'hidden-gem', 'blockbuster', 'indie', 'experimental'])[1 + (random() * 5)::INT],
        CASE WHEN random() < 0.8 THEN (ARRAY['family-friendly', 'dark', 'uplifting', 'thought-provoking', 'action-packed'])[1 + (random() * 4)::INT] END,
        CASE WHEN random() < 0.5 THEN (ARRAY['epic', 'atmospheric', 'gritty', 'whimsical', 'fast-paced'])[1 + (random() * 4)::INT] END,
        CASE WHEN random() < 0.3 THEN (ARRAY['cerebral', 'nostalgic', 'visceral', 'poignant', 'gripping'])[1 + (random() * 4)::INT] END
    ], NULL)::TEXT[],
    -- JSONB metadata
    jsonb_build_object(
        'age_rating', (ARRAY['G', 'PG', 'PG-13', 'R'])[1 + (random() * 3)::INT],
        'language', (ARRAY['English', 'Spanish', 'French', 'German', 'Japanese', 'Korean', 'Mandarin'])[1 + (random() * 6)::INT],
        'streaming', (ARRAY['CinePlus', 'BingeNow', 'Streamly', 'PrimeShow', 'FlixNet'])[1 + (random() * 4)::INT],
        'budget_millions', (10 + random() * 190)::INT,
        'box_office_millions', (5 + random() * 495)::INT,
        'awards', jsonb_build_object(
            'oscars', (random() * 8)::INT,
            'golden_globes', (random() * 5)::INT,
            'nominated', (random() > 0.7)
        )
    ),
    -- Realistic created_at: older movies added to DB earlier
    NOW() - (
        CASE
            WHEN mb.release_year >= 2020 THEN (random() * 365)::INT           -- Last year
            WHEN mb.release_year >= 2015 THEN (365 + random() * 730)::INT     -- 1-3 years ago
            WHEN mb.release_year >= 2010 THEN (1095 + random() * 1095)::INT   -- 3-6 years ago
            WHEN mb.release_year >= 2000 THEN (2190 + random() * 1095)::INT   -- 6-9 years ago
            ELSE (3285 + random() * 1095)::INT                                -- 9-12 years ago
        END * INTERVAL '1 day'
    ),
    -- updated_at same as created_at (most movies not updated)
    NOW() - (
        CASE
            WHEN mb.release_year >= 2020 THEN (random() * 365)::INT
            WHEN mb.release_year >= 2015 THEN (365 + random() * 730)::INT
            WHEN mb.release_year >= 2010 THEN (1095 + random() * 1095)::INT
            WHEN mb.release_year >= 2000 THEN (2190 + random() * 1095)::INT
            ELSE (3285 + random() * 1095)::INT
        END * INTERVAL '1 day'
    )
FROM movie_base mb;

------------------------------------------------------------
-- Seed people (~300) with natural, realistic names
------------------------------------------------------------

WITH names AS (
    SELECT
        gs AS person_num,
        (ARRAY[
            'Alex','Jordan','Taylor','Casey','Riley','Morgan','Cameron','Avery','Skyler','Quinn',
            'Jamie','Kendall','Logan','Reese','Rowan','Emerson','Parker','Hayden','Blake','Finley',
            'Nova','Luna','Indigo','Milo','Sunny','Zara','Harper','Jace','Marin','Silas',
            'Elara','Orion','Cassidy','Theo','Aya','Nico','Rory','Sage','Juniper','Kai',
            'Iris','Felix','Jasper','Oscar','Stella','Ruby','Violet','Hazel','Finn','Poppy'
        ])[1 + (floor(random() * 50))::INT]
        || ' ' ||
        (ARRAY[
            'Smith','Johnson','Lee','Brown','Garcia','Martinez','Davis','Lopez','Martins','Taylor',
            'Nguyen','Wilson','Anderson','Thomas','Jackson','White','Harris','Clark','Lewis','Walker',
            'Rivers','Stone','Brooks','Hill','Woods','North','West','Fields','Lake','Forest'
        ])[1 + (floor(random() * 30))::INT] AS full_name
    FROM generate_series(1, 300) AS gs
)
INSERT INTO people (full_name, birth_year, bio)
SELECT DISTINCT
    full_name,
    -- Age distribution: 1950–2010 (ages ~15–75 in 2025)
    1950 + (random() * 60)::INT,
    CASE
        WHEN random() < 0.3 THEN 'Award-winning performer known for versatile roles.'
        WHEN random() < 0.6 THEN 'Rising star in independent cinema.'
        ELSE NULL
    END
FROM names;

------------------------------------------------------------
-- Add a few animal "actors" for fun and variety
------------------------------------------------------------

INSERT INTO people (full_name, birth_year) VALUES
  ('Barkley the Dog',        NULL),
  ('Sir Whiskers III',       NULL),
  ('Flapjack the Parrot',    2018),
  ('Noodles the Ferret',     2020),
  ('Detective Paws',         2016),
  ('Pancake the Ferret',     2019),
  ('Captain Meow',           NULL),
  ('General Sniffles',       2017);

------------------------------------------------------------
-- Seed users (~5000) with HSTORE preferences
------------------------------------------------------------

WITH user_base AS (
    SELECT
        gs AS user_num,
        'user_' || LPAD(gs::TEXT, 5, '0') AS username,
        'user' || gs || '@example.com' AS email,
        (ARRAY['US', 'UK', 'CA', 'DE', 'FR', 'IN', 'BR', 'JP', 'AU', 'NL', 'MX', 'ES', 'IT', 'SE'])
        [1 + (random() * 13)::INT] AS country
    FROM generate_series(1, 5000) AS gs
)
INSERT INTO users (username, email, country, preferences, created_at)
SELECT
    username,
    email,
    country,
    -- HSTORE for user preferences
    hstore(ARRAY[
        'theme', (ARRAY['dark', 'light', 'auto'])[1 + (random() * 2)::INT],
        'language', (ARRAY['en', 'es', 'fr', 'de', 'ja'])[1 + (random() * 4)::INT],
        'notifications', (ARRAY['all', 'important', 'none'])[1 + (random() * 2)::INT],
        'autoplay', (ARRAY['true', 'false'])[1 + (random() * 1)::INT],
        'quality', (ARRAY['auto', '720p', '1080p', '4k'])[1 + (random() * 3)::INT]
    ]),
    -- Realistic user signup times: gradual growth over past 3 years
    NOW() - (random() * 1095)::INT * INTERVAL '1 day'
FROM user_base;

------------------------------------------------------------
-- Seed movie_genres (1–4 genres per movie)
------------------------------------------------------------

INSERT INTO movie_genres (movie_id, genre_id)
SELECT DISTINCT ON (m.movie_id, g.genre_id)
    m.movie_id,
    g.genre_id
FROM movies m
CROSS JOIN LATERAL (
    SELECT genre_id
    FROM genres
    ORDER BY random()
    LIMIT (1 + (random() * 3)::INT)
) g;

------------------------------------------------------------
-- Seed movie_cast (3–8 people per movie) with genre-aware character names
------------------------------------------------------------

INSERT INTO movie_cast (movie_id, person_id, role, character_name, billing_order)
SELECT
    m.movie_id,
    p.person_id,
    (ARRAY['Actor','Actor','Actor','Director','Producer'])[1 + (floor(random() * 5))::INT] AS role,
    -- genre-aware character names (mix of creative and realistic)
    CASE main_genre
        WHEN 'Action' THEN
            (ARRAY[
                'Blaze Thunder','Rogue Talon','Jett Cross','Nova Strike','Rex Ironhart',
                'Max Rocket','Aria Volt','Kade Fury','Raven Lock','Zane Steel',
                'Jack Ryan','Sarah Connor','Maria Santos','John Stone','Nina Cross'
            ])[1 + (floor(random() * 15))::INT]
        WHEN 'Adventure' THEN
            (ARRAY[
                'Indigo Rivers','Marin Quest','Atlas Wilder','Saffron Trail','Finn Compass',
                'Elara Drift','Juno Wayfarer','Rowan Tides','Cedar Fox','Luca North',
                'Indiana Cole','Diego Martinez','Sam Hunter','Maya Stone','River Song'
            ])[1 + (floor(random() * 15))::INT]
        WHEN 'Comedy' THEN
            (ARRAY[
                'Waffle McSnacks','Captain Marshmallow','Mr. Whiskerson','Detective Waffle',
                'Pickles McGee','Bingo Sprout','Sunny Giggles','Milo Daydream','Nora Noodle',
                'Pumpkin Fizz','Chuck Chuckles','Larry Laughs','Buddy Guffaw','Skip Jolly',
                'Wanda Whoopee'
            ])[1 + (floor(random() * 15))::INT]
        WHEN 'Drama' THEN
            (ARRAY[
                'Harper Quinn','Silas Hart','Marin Locke','Elara Finn','Jonah Keene',
                'Isla Rowan','Nico Hale','Rowan Pierce','Clara Wynn','Theo Merritt',
                'Michael Bennett','Sarah Williams','Elena Rodriguez','David Cooper','Rebecca Turner'
            ])[1 + (floor(random() * 15))::INT]
        WHEN 'Sci-Fi' THEN
            (ARRAY[
                'Nova Flux','Orion Pulse','Lyra Vector','Cassian Node','Zara Helix',
                'Jace Quantum','Aria Nebula','Kael Circuit','Riven Byte','Helio Trace',
                'Commander Shepard','Dr. Sarah Chen','Marcus Webb','Commander Stone','Maya Techson'
            ])[1 + (floor(random() * 15))::INT]
        WHEN 'Fantasy' THEN
            (ARRAY[
                'Luna Evergreen','Thorne Brightwind','Astra Willow','Cedric Moonglade',
                'Rowan Starfall','Mira Thornbloom','Kieran Foxglove','Elowen Lightfoot',
                'Bram Oakshield','Seren Nightbloom','Sage Whisperwind','Ember Nightshade',
                'Asher Thornfield','Briar Ravenwood','Sterling Frostborn'
            ])[1 + (floor(random() * 15))::INT]
        WHEN 'Thriller' THEN
            (ARRAY[
                'Jade Cross','Mason Vale','Iris Lockwood','Dorian Creed','Paige Ashcroft',
                'Vera Knox','Callum Roane','Sable Kerr','Miles Archer','Rhea Blackwell',
                'Detective Morgan','Agent Collins','Sarah Winters','Alex Turner','Eve Hunter'
            ])[1 + (floor(random() * 15))::INT]
        WHEN 'Romance' THEN
            (ARRAY[
                'Clara Hart','Eli Rivers','Siena Bloom','Jonah Wilde','Amelia Rhodes',
                'Rowan Hale','Isabel Quinn','Theo Calder','Nina Solace','Cal Hartley',
                'Emma Thompson','Jasper Wells','Sophie Martin','Liam Anderson','Grace Sullivan'
            ])[1 + (floor(random() * 15))::INT]
        WHEN 'Animation' THEN
            (ARRAY[
                'Bark Twain','Sir Pounce-a-Lot','Poppy Stardust','Nibbles McCloud',
                'Ziggy Sprinkles','Pebble Brightpaw','Tango Featherstone','Mochi Fizz',
                'Buttons Stardrop','Captain Meow','Whiskers McGraw','Sparkle Hopper',
                'Zoom Fastpaws','Puddles Raincloud','Twinkle Starshine'
            ])[1 + (floor(random() * 15))::INT]
        WHEN 'Documentary' THEN
            (ARRAY[
                'Dr. Avery Holt','Morgan Ashfield','Riley Penrose','Samir Kline',
                'Dana Whitaker','Elliot Marsh','Jordan Keats','Sasha Rowland',
                'Noah Adler','Leah Moritz','Dr. Sarah Mitchell','Professor Chen',
                'Dr. James Rodriguez','Dr. Maria Garcia','Dr. David Kumar'
            ])[1 + (floor(random() * 15))::INT]
        ELSE
            -- Fallback realistic character names
            (ARRAY[
                'Alex Morgan','Jordan Blake','Casey Rivers','Taylor Anderson','Sam Wilson',
                'Charlie Brown','Riley Cooper','Jamie Lee','Drew Parker','Quinn Harper',
                'Avery Stone','Parker Jones','Skyler Martin','Cameron Davis','Morgan Ellis'
            ])[1 + (floor(random() * 15))::INT]
    END AS character_name,
    1 + (floor(random() * 8))::INT AS billing_order   -- 1–8
FROM movies m
JOIN LATERAL (
    -- pick one "main" genre name for this movie
    SELECT g.name AS main_genre
    FROM movie_genres mg
    JOIN genres g ON g.genre_id = mg.genre_id
    WHERE mg.movie_id = m.movie_id
    ORDER BY random()
    LIMIT 1
) g_main ON TRUE
JOIN LATERAL (
    SELECT person_id
    FROM people
    ORDER BY random()
    LIMIT (3 + (floor(random() * 6))::INT)   -- 3–8 cast members
) p ON TRUE;

------------------------------------------------------------
-- Seed ratings (varies per movie) with sentiment-aware titles & texts
-- Realistic patterns: popularity bias, recency bias, normal distribution
------------------------------------------------------------

WITH rating_base AS (
    SELECT
        m.movie_id,
        m.imdb_rating,
        m.created_at,
        u.user_id,
        -- Realistic rating distribution: correlates with IMDB rating but with variation
        LEAST(10, GREATEST(1,
            ROUND(
                -- Base on IMDB rating with noise
                m.imdb_rating +
                -- Add random variation (-2 to +2)
                (random() * 4 - 2) +
                -- Slight bias toward higher ratings (people who rate tend to like movies)
                (CASE WHEN random() < 0.3 THEN 1 ELSE 0 END)
            )
        ))::INT AS rating,
        -- Rating timestamp: must be after movie was added to database
        m.created_at + (random() * (NOW() - m.created_at)) AS rated_at
    FROM movies m
    CROSS JOIN LATERAL (
        SELECT user_id
        FROM users
        ORDER BY random()
        -- Popularity bias: better movies and newer movies get more ratings
        LIMIT (
            CASE
                -- Recent blockbusters get most ratings
                WHEN m.release_year >= 2020 AND m.imdb_rating >= 7.5
                    THEN 200 + (floor(random() * 101))::INT  -- 200-300 ratings
                -- Recent movies get more ratings
                WHEN m.release_year >= 2020
                    THEN 150 + (floor(random() * 101))::INT  -- 150-250
                -- Good older movies still popular
                WHEN m.imdb_rating >= 8.0
                    THEN 120 + (floor(random() * 81))::INT   -- 120-200
                -- Mid-tier recent movies
                WHEN m.release_year >= 2015
                    THEN 80 + (floor(random() * 71))::INT    -- 80-150
                -- Older or lower-rated movies
                ELSE 30 + (floor(random() * 71))::INT        -- 30-100
            END
        )
    ) u
)
INSERT INTO ratings (movie_id, user_id, rating, rated_at, review_title, review_text, helpful_count)
SELECT
    rb.movie_id,
    rb.user_id,
    rb.rating,
    rb.rated_at,
    -- review_title based on rating bucket
    CASE
        WHEN rb.rating >= 8 THEN
            (ARRAY[
                'Loved it',
                'A masterpiece',
                'Exceeded my expectations',
                'Would definitely watch again',
                'My new comfort movie',
                'Absolutely brilliant',
                'Chef''s kiss'
            ])[1 + (floor(random() * 7))::INT]
        WHEN rb.rating BETWEEN 5 AND 7 THEN
            (ARRAY[
                'Pretty good overall',
                'It was okay',
                'Decent background movie',
                'Had some great moments',
                'Mixed feelings',
                'Solid effort',
                'Better than expected'
            ])[1 + (floor(random() * 7))::INT]
        ELSE
            (ARRAY[
                'Not my favorite',
                'Disappointing',
                'Couldn''t really get into it',
                'Struggled to finish it',
                'Had potential but missed the mark',
                'What did I just watch?',
                'Could have been better'
            ])[1 + (floor(random() * 7))::INT]
    END AS review_title,
    -- review_text based on rating bucket
    CASE
        WHEN rb.rating >= 8 THEN
            (ARRAY[
                'Surprisingly heartfelt. I came for the jokes and stayed for the characters. I''d happily rewatch this with friends.',
                'This had no business being this good. Great pacing, great soundtrack, and a finale that actually lands.',
                'I laughed, I teared up, and I immediately texted three people to watch it. One of the better things I''ve streamed lately.',
                'A cozy kind of movie. Nothing groundbreaking, but it made me smile the entire time.',
                'The kind of film you put on "just to try" and suddenly it''s 2AM and you''ve watched the whole thing.',
                'Charming from start to finish. The pacing was perfect and the characters felt incredibly real.'
            ])[1 + (floor(random() * 6))::INT]
        WHEN rb.rating BETWEEN 5 AND 7 THEN
            (ARRAY[
                'Fun in the moment but not super memorable. Good for a rainy afternoon.',
                'Some really strong scenes mixed with a few that dragged. Glad I watched it once.',
                'I watched this while cooking and kept looking up during the best parts. Solid background viewing.',
                'Started slow, picked up in the middle, and then sort of coasted to the end. Not bad, not amazing.',
                'Interesting ideas, uneven execution. Worth a try if you like the genre.',
                'Had its moments. Some scenes were great, others felt like filler.'
            ])[1 + (floor(random() * 6))::INT]
        ELSE
            (ARRAY[
                'The concept was better than the actual movie. I wanted to like it more than I did.',
                'Felt like a very long trailer for a better movie that doesn''t exist yet.',
                'I kept waiting for it to click, and it just... never did.',
                'Some cool visuals, but the story was all over the place. The ferret deserved better.',
                'I finished it out of stubbornness more than enjoyment.',
                'Not sure what they were going for here. It missed the mark for me.'
            ])[1 + (floor(random() * 6))::INT]
    END AS review_text,
    -- Helpful count: older reviews + higher ratings = more helpful votes
    (
        -- Base votes from age (older = more votes)
        (EXTRACT(EPOCH FROM (NOW() - rb.rated_at)) / 86400 / 10)::INT +
        -- Bonus for high ratings (helpful reviews tend to be positive)
        (CASE WHEN rb.rating >= 8 THEN 20 WHEN rb.rating <= 3 THEN 5 ELSE 10 END) +
        -- Random variation
        (random() * 30)::INT
    )::INT AS helpful_count
FROM rating_base rb;

------------------------------------------------------------
-- Seed watchlist (for JOIN exercises and locking scenarios)
------------------------------------------------------------

INSERT INTO watchlist (user_id, movie_id, added_at, watched)
SELECT
    u.user_id,
    m.movie_id,
    -- Realistic added_at: after user signup and movie creation
    GREATEST(u.created_at, m.created_at) + (random() * (NOW() - GREATEST(u.created_at, m.created_at))) AS added_at,
    -- Realistic watched status: if user rated it, likely watched (90%), otherwise 20%
    CASE
        WHEN EXISTS (
            SELECT 1 FROM ratings r
            WHERE r.user_id = u.user_id AND r.movie_id = m.movie_id
        ) THEN random() < 0.9  -- 90% watched if rated
        ELSE random() < 0.2    -- 20% watched if not rated
    END AS watched
FROM users u
CROSS JOIN LATERAL (
    SELECT movie_id, created_at
    FROM movies
    ORDER BY random()
    LIMIT (5 + (random() * 15)::INT)  -- 5-20 movies per watchlist
) m
ON CONFLICT (user_id, movie_id) DO NOTHING;

------------------------------------------------------------
-- Seed popularity_cache (for UPDATE contention scenarios)
------------------------------------------------------------

INSERT INTO popularity_cache (movie_id, view_count, avg_rating, rating_count, last_updated)
SELECT
    m.movie_id,
    (random() * 1000000)::BIGINT,  -- 0-1M views
    (SELECT AVG(rating) FROM ratings r WHERE r.movie_id = m.movie_id),
    rating_count,
    -- Realistic last_updated: popular movies (more ratings) updated more recently
    NOW() - (
        CASE
            WHEN rating_count > 200 THEN (random() * 30)::INT      -- Popular: last 30 days
            WHEN rating_count > 100 THEN (random() * 60)::INT      -- Moderate: last 60 days
            ELSE (random() * 180)::INT                              -- Less popular: last 180 days
        END * INTERVAL '1 day'
    ) AS last_updated
FROM movies m
CROSS JOIN LATERAL (
    SELECT COUNT(*)::INT AS rating_count FROM ratings r WHERE r.movie_id = m.movie_id
) rc;

------------------------------------------------------------
-- Update full-text search vectors
------------------------------------------------------------

UPDATE movies
SET search_vector = to_tsvector('english',
    COALESCE(title, '') || ' ' ||
    COALESCE(array_to_string(tags, ' '), '')
);

------------------------------------------------------------
-- Realistic updated_at timestamps (some movies updated after creation)
------------------------------------------------------------

-- 30% of movies have been updated (metadata corrections, etc.)
UPDATE movies
SET updated_at = created_at + (random() * (NOW() - created_at))
WHERE movie_id IN (
    SELECT movie_id
    FROM movies
    ORDER BY random()
    LIMIT (SELECT (COUNT(*) * 0.3)::INT FROM movies)
);

-- Popular recent movies updated more frequently
UPDATE movies
SET updated_at = NOW() - (random() * 90)::INT * INTERVAL '1 day'
WHERE release_year >= 2020
  AND imdb_rating >= 8.0
  AND movie_id IN (
    SELECT movie_id
    FROM movies
    WHERE release_year >= 2020 AND imdb_rating >= 8.0
    ORDER BY random()
    LIMIT 10
);

------------------------------------------------------------
-- Educational data quality issues for demos
------------------------------------------------------------

-- 1) Some movies with NULL metadata
UPDATE movies
SET metadata = NULL
WHERE movie_id IN (
    SELECT movie_id
    FROM movies
    ORDER BY random()
    LIMIT 15
);

-- 2) Some movies with absurd runtimes (data quality examples)
UPDATE movies
SET runtime_min = 999
WHERE movie_id IN (
    SELECT movie_id
    FROM movies
    ORDER BY random()
    LIMIT 8
);

-- 3) Some movies with negative runtimes (data quality)
UPDATE movies
SET runtime_min = -10
WHERE movie_id IN (
    SELECT movie_id
    FROM movies
    ORDER BY random()
    LIMIT 3
);

-- 4) Some people with unknown birth_year
UPDATE people
SET birth_year = NULL
WHERE person_id IN (
    SELECT person_id
    FROM people
    ORDER BY random()
    LIMIT 20
);

-- 5) Skew streaming platform so "Streamly" appears more often (for query optimization examples)
UPDATE movies
SET metadata = jsonb_set(
    COALESCE(metadata, '{}'::jsonb),
    '{streaming}',
    '"Streamly"'::jsonb
)
WHERE movie_id IN (
    SELECT movie_id
    FROM movies
    WHERE metadata IS NOT NULL
    ORDER BY random()
    LIMIT (SELECT (COUNT(*) * 0.45)::INT FROM movies WHERE metadata IS NOT NULL)
);

-- 6) Create duplicate ratings (for data quality/deduplication examples)
INSERT INTO ratings (movie_id, user_id, rating, rated_at, review_title, review_text, helpful_count)
SELECT movie_id, user_id, rating, rated_at, review_title, review_text, helpful_count
FROM ratings
WHERE rating_id IN (
    SELECT rating_id
    FROM ratings
    ORDER BY random()
    LIMIT 50
);

-- 7) Add some ratings from the future (data quality issue)
UPDATE ratings
SET rated_at = NOW() + INTERVAL '30 days'
WHERE rating_id IN (
    SELECT rating_id
    FROM ratings
    ORDER BY random()
    LIMIT 10
);

-- 8) Add some very old ratings (edge case testing)
UPDATE ratings
SET rated_at = '1990-01-01'::TIMESTAMPTZ
WHERE rating_id IN (
    SELECT rating_id
    FROM ratings
    ORDER BY random()
    LIMIT 5
);

COMMIT;

-- Display summary statistics
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Database Setup Complete!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Movies: %', (SELECT COUNT(*) FROM movies);
    RAISE NOTICE 'People: %', (SELECT COUNT(*) FROM people);
    RAISE NOTICE 'Users: %', (SELECT COUNT(*) FROM users);
    RAISE NOTICE 'Ratings: %', (SELECT COUNT(*) FROM ratings);
    RAISE NOTICE 'Genres: %', (SELECT COUNT(*) FROM genres);
    RAISE NOTICE 'Watchlist entries: %', (SELECT COUNT(*) FROM watchlist);
    RAISE NOTICE '========================================';
END $$;

-- End of movies_dataset.sql
