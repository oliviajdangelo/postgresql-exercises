# Dataset Setup Instructions

Synthetic movie ratings database for Intermediate PostgreSQL course.

## Files

1. **movies_dataset.sql** - Creates schema and loads ~140,000 records
2. **seed_monitoring_data.sql** - Populates pg_stat_statements with slow queries

## Quick Setup

**Recommended database name:** `movies_db`

### Step 1: Load the dataset (Required)
```bash
psql -d movies_db -f datasets/movies_dataset.sql
```
**Time:** ~3-5 minutes
**Creates:** 9 tables, ~500 movies, 5000 users, ~75,000 ratings

### Step 2: Seed monitoring data (Optional but Recommended)
```bash
psql -d movies_db -f datasets/seed_monitoring_data.sql
```
**Time:** ~30 seconds
**Purpose:** Populates pg_stat_statements with slow query patterns for Days 4-5

This script is optional but helpful for demonstrating query performance monitoring, EXPLAIN ANALYZE, and optimization techniques.

## Verify Setup

```sql
SELECT
    (SELECT COUNT(*) FROM movies) AS movies,
    (SELECT COUNT(*) FROM users) AS users,
    (SELECT COUNT(*) FROM ratings) AS ratings;

-- Expected: 500 movies, 5000 users, ~75,000 ratings
```

## What Gets Created

**9 Tables with ~140,000 total rows (~30-50MB):**

| Table | Rows | Description |
|-------|------|-------------|
| movies | 500 | Movies with JSONB metadata, TEXT[] tags, TSVECTOR search |
| people | 308 | Actors, directors, producers (includes 8 animal actors) |
| genres | 15 | Standard movie genres |
| movie_cast | ~2,750 | 3-8 cast members per movie with genre-aware character names |
| movie_genres | ~1,000 | 1-3 genres per movie |
| users | 5,000 | Users with HSTORE preferences |
| ratings | ~75,000 | Variable ratings per movie (30-300 based on popularity/recency) |
| watchlist | ~56,000 | 5-20 movies per user watchlist |
| popularity_cache | 500 | Cached aggregates for UPDATE contention demos |

**Key Features:**
- Advanced data types: JSONB, TEXT[], HSTORE, TSVECTOR
- Realistic patterns: popularity bias, rating correlations, temporal trends
- Reproducible: Uses random seed (all 20 databases will be identical)
- No indexes initially (students create them on Day 3)
- Intentional data quality issues for teaching

**Extensions:**
- hstore (auto-installed)
- pg_stat_statements (auto-installed by monitoring script)

## Advanced: Adjust Dataset Size

If 3-5 minute load times are too long, edit `movies_dataset.sql`:

**Line 321** - Reduce number of users:
```sql
FROM generate_series(1, 5000) AS gs  -- Change to 2000 for smaller dataset
```

**Line 488** - Reduce ratings per movie:
```sql
LIMIT (100 + (floor(random() * 101))::INT)  -- Change to (20 + (floor(random() * 81))::INT)
```

**Line 610** - Reduce watchlist entries:
```sql
LIMIT (5 + (random() * 15)::INT)  -- Change to (2 + (random() * 8)::INT)
```

**Smaller settings create:**
- ~30,000 ratings instead of ~75,000
- ~30,000 watchlist entries instead of ~56,000
- Load time: 1-2 minutes per database

**Note:** The larger dataset (75K ratings) is recommended for clearer performance demonstrations.

## Troubleshooting

**Error: "extension hstore does not exist"**
- The script creates it automatically
- If you still get this error, run: `CREATE EXTENSION hstore;` first

**Error: "out of memory"**
- Reduce dataset size using instructions above
- Or increase `work_mem` temporarily: `SET work_mem = '256MB';`

**Slow loading:**
- Normal for 75K-140K rows (3-5 minutes is expected)
- Can reduce dataset size if needed

**Different row counts each run:**
- Should NOT happen - uses `setseed(0.42)` for reproducibility
- All 20 databases should have identical data
- If you see different counts, check that you're using the latest version of the script

## For Cloud SQL Setup

**Prerequisites:**
- PostgreSQL 16+ (using PostgreSQL 17)
- ~50MB disk space per database instance
- Database creation privileges
- Extension installation permissions

**Setup for 20 learners:**
1. Create 20 identical Cloud SQL instances
2. Create database `movies_db` on each
3. Run both scripts on each instance
4. Verify counts match expected values
5. Share connection details with learners

---

Ready for training! All data is synthetic and safe for corporate training use.
