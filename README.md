# Intermediate PostgreSQL - Hands-on Exercises

Hands-on lab exercises for the Intermediate PostgreSQL course.

## Setup

### 1. Load the Dataset

Connect to your database and run the dataset script:

```bash
psql -d movies_db -f datasets/movies_dataset.sql
```

Or copy/paste the contents into pgAdmin's Query Tool.

### 2. Verify Setup

```sql
SELECT
    (SELECT COUNT(*) FROM movies) AS movies,
    (SELECT COUNT(*) FROM users) AS users,
    (SELECT COUNT(*) FROM ratings) AS ratings;
-- Expected: 500 movies, 5000 users, ~75,000 ratings
```

## Exercises

| Day | Topic | File |
|-----|-------|------|
| 1 | Foundation & Advanced Data Types | `exercises/day1_exercises.sql` |

## Dataset Overview

The `movies_db` database includes:

- **movies** (500) - With JSONB metadata, TEXT[] tags
- **users** (5,000) - With HSTORE preferences
- **ratings** (~75,000) - User ratings for movies
- **people** (308) - Actors, directors, producers
- **genres** (15) - Movie genres
- **movie_cast** (~2,750) - Cast members per movie
- **movie_genres** (~1,000) - Genre assignments

See `datasets/DATASET_SETUP.md` for detailed setup instructions.
