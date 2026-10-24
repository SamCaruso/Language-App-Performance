# Language Apps Performance — Data Pipeline & Power BI Dashboard

## Overview

This project analyses the effectiveness of language learning apps across different user profiles. It was built end-to-end: from synthetic data generation, through a multi-layer PostgreSQL pipeline, to a Power BI dashboard.

---

## Project Structure

| File | Description |
|---|---|
| `generate_synthetic_data.py` | Generates synthetic raw data with intentional anomalies |
| `raw_apps_data.csv` | Raw output from the data generator |
| `01_bronze_eda_audit.sql` | Exploratory data analysis and audit queries on the raw data |
| `02_silver_transformation.sql` | Full silver-layer cleaning and deduplication pipeline |
| `03_gold_star_schema.sql` | Gold-layer star schema — `dim_users` and `fact_session` |
| `Language_apps_performance.pbix` | Power BI dashboard |

---

## Data Generation

Synthetic data was generated using Python's `Faker` library (`generate_synthetic_data.py`). The dataset simulates 900 users across 7 countries, each with between 3 and 11 learning sessions.

Intentional anomalies were injected to simulate real-world data quality issues:
- `NULL` values and literal `'NULL'` strings
- Inconsistent casing and leading/trailing whitespace
- Logically incoherent records (e.g. end date before start date, end level below start level)

For the purposes of this portfolio project:
- `session_id`, `user_id` and `session_timestamp` are always NON-NULL and in a valid format
- The dataset spans a 3-year period
- `native_language` is directly linked to `country`, i.e. Italy -> Italian 

---

## Pipeline Architecture

The pipeline follows a three-layer medallion architecture:

```
Bronze (staging)  →  Silver (intermediate)  →  Gold (analytics)
raw_apps_data         clean_apps_data            dim_users
                                                 fact_session
```

### Bronze
Raw CSV data loaded as-is into `staging.raw_apps_data`. No transformations applied.

### Silver — `02_silver_transformation.sql`
The raw data is cleaned and transformed through a multi-step CTE pipeline in PostgreSQL.

The pipeline covers:

Data validation and standardisation: handles missing values, inconsistent formatting, invalid data types and logically inconsistent dates and CEFR levels.

Date and timestamp validation: excludes sessions outside users' valid learning periods, assuming the recorded start and end dates are authoritative.

Deduplication: identifies potential duplicate users through pairwise comparisons of user attributes, including NULL-safe comparisons, and removes duplicate sessions according to defined retention rules.

CEFR level mapping: maps CEFR levels to numeric values to support progress calculations and analysis.

The resulting dataset is used to build the Gold-layer analytical tables.

#### Duplicate Detection Rule
Two users are considered duplicates (regardless of `user_id`) if:
1. All 10 attribute columns agree — either matching on real values or both NULL in the same column.
2. 9 columns agree and exactly 1 column has a real value on one side and NULL on the other.

This is implemented as a pairwise self-join with NULL-safe column scoring, rather than a simple `GROUP BY`, to correctly handle NULL values under a well-defined business rule.

> **Production note:** The self-join approach is O(n²) and suited to small-to-medium datasets. At scale, a blocking or profile-hashing strategy would be used instead.

### Gold — `03_gold_star_schema.sql`
Splits the clean silver table into a star schema:

- **`analytics.dim_users`** — one row per user, with `user_key` as a surrogate primary key.

- **`analytics.fact_session`** — one row per session, with `session_key` as a surrogate primary key. References `dim_users` via `user_key` as a foreign key, obtained by joining on `user_id` during the insert.

---

## Tools & Technologies

- **Python** — data generation (`Faker`, `pandas`)
- **PostgreSQL** — data pipeline (EDA, cleaning, transformation, star schema)
- **Power BI** — dashboard and visualisations

---

## Power BI Dashboard

The interactive dashboard contains four analytical views exploring app usage, user learning progression, and engagement patterns.

### 1. Overview & Usage
High-level metrics comparing session volume and user distribution across the five language-learning apps, with filters for country, age group, and subscription type.
![Dashboard overview](images/sessions_&_users_by_app)

### 2. Learning Progression by App
Average CEFR level progression (scores between 0 and 5) across apps between user groups.
![Progress by App](images/progress_by_app)

### 3. Learning Progression by Session Count
Relationship between users' session counts and average CEFR level progression, grouped by session frequency.
![Progress by Session Count](images/progress_by_session_count)

### 4. Learning Progression by Total Study Duration
Behavioral analysis mapping total session duration ranges against learning progression.
![Progress by Session Duration](images/progress_by_session_duration)

---

## Assumptions, Limitations & Further Improvements

- `user_id` and `session_id` are assumed non-NULL by construction of the data generator. In a production pipeline, a NULL-tolerant strategy using profile hashing and a sentinel dimension member would be required.
- if two `session_timestamp`s belong to the same user, they should be checked against `session_duration_mins` to verify plausibility (if the two `session_timestamp`s are 3 seconds apart but the first one lasts 30 minutes, a validity issue endues).
- The dataset is static. No incremental load or SCD (Slowly Changing Dimension) logic is implemented.
