DROP TABLE IF EXISTS intermediate.clean_apps_data;

-- Create single clean table
-- For the purposes of this portfolio project, SESSION_ID, SESSION_TIMESTAMP and USER_ID are always valid and non-NULL

CREATE TABLE intermediate.clean_apps_data AS 
WITH clean_individual_values AS (
SELECT 
	CASE 
		WHEN TRIM(session_id) !~ '^S[0-9]{4}$' THEN NULL
		ELSE TRIM(session_id)
	END AS session_id,
	
	CASE 
		WHEN pg_input_is_valid(TRIM(session_timestamp), 'timestamp') THEN TRIM(session_timestamp)::TIMESTAMP
	END AS session_timestamp,
	
	CASE 
		WHEN TRIM(user_id) !~ '^U[0-9]{3}$' THEN NULL
		ELSE TRIM(user_id)
	END AS user_id,
	
	NULLIF(TRIM(INITCAP(name)), 'Null') AS name,
	
	CASE 
		WHEN NOT pg_input_is_valid(TRIM(age), 'integer') THEN NULL 
		WHEN TRIM(age)::INTEGER NOT BETWEEN 14 AND 70 THEN NULL
		ELSE TRIM(age)::INTEGER
	END AS age,
	
	NULLIF(TRIM(INITCAP(country)), 'Null') AS country,
	NULLIF(TRIM(INITCAP(native_language)), 'Null') AS native_language,
	NULLIF(TRIM(INITCAP(app)), 'Null') AS app,
	NULLIF(TRIM(INITCAP(subscription_type)), 'Null') AS subscription_type,
	
	CASE 
		WHEN TRIM(start_date) !~ '^\d{4}-\d{2}-\d{2}$' THEN NULL
		WHEN pg_input_is_valid(TRIM(start_date), 'date') THEN TRIM(start_date)::DATE
	END AS start_date,
	
	CASE 
		WHEN TRIM(end_date) !~ '^\d{4}-\d{2}-\d{2}$' THEN NULL
		WHEN pg_input_is_valid(TRIM(end_date), 'date') THEN TRIM(end_date)::DATE
	END AS end_date,
	
	CASE 
		WHEN TRIM(start_level) ~* '^[ABC][12]$' THEN TRIM(UPPER(start_level))
		ELSE NULL
	END AS start_level,
	
	CASE 
		WHEN TRIM(end_level) ~* '^[ABC][12]$' THEN TRIM(UPPER(end_level))
		ELSE NULL
	END AS end_level,
	
	CASE 
		WHEN NOT pg_input_is_valid(TRIM(session_duration_mins), 'integer') THEN NULL  
		WHEN TRIM(session_duration_mins)::INTEGER NOT BETWEEN 1 AND 120 THEN NULL 
		ELSE TRIM(session_duration_mins)::INTEGER
	END AS session_duration_mins
FROM staging.raw_apps_data
),

-- start_date < end_date and drop rows where either value is NULL
coherent_date AS (
SELECT 
	*,
	CASE 
		WHEN end_date < start_date THEN NULL 
		ELSE start_date
	END valid_start_date,
	CASE 
		WHEN end_date < start_date THEN NULL 
		ELSE end_date
	END valid_end_date
FROM clean_individual_values
WHERE start_date IS NOT NULL AND end_date IS NOT NULL 
),

-- session_timestamp between valid_start_date and valid_end_date and 
-- drop rows where this does not happen (assuming valid_start_date and end_start_date are correct)
coherent_timestamp AS (
SELECT 
	*
FROM coherent_date
WHERE session_timestamp::DATE >= valid_start_date AND session_timestamp::DATE <= valid_end_date
),

-- Based on USER_ID always being valid and non-NULL as per the synthetic data.
-- Remove duplicate USER_ID and keep instance with latest valid_timestamp.
-- Prepare CTE for pairwise duplicate check.
one_row_per_user AS (
SELECT DISTINCT ON (user_id)
	user_id,
	name,
	age,
	country,
	native_language,
	app,
	subscription_type,
	valid_start_date AS start_date,
	valid_end_date   AS end_date,
	start_level      AS start_level_cefr,
	end_level        AS end_level_cefr
FROM coherent_timestamp
ORDER BY user_id, session_timestamp DESC NULLS LAST
),

-- Pairwise duplicate check across all user attribute columns regardless of user_id.
-- RULE: two users are considered duplicates (regardless of user_id) if:
-- 1. All 10 columns agree, both as valid values and as NULLs
-- 2. 9 columns agree apart from one where one user has a NULL value.
column_comparisons AS (
SELECT
	a.user_id AS user_id_1,
	b.user_id AS user_id_2,
	(
		(a.name              IS NOT DISTINCT FROM b.name             )::int +
		(a.age               IS NOT DISTINCT FROM b.age              )::int +
		(a.country           IS NOT DISTINCT FROM b.country          )::int +
		(a.native_language   IS NOT DISTINCT FROM b.native_language  )::int +
		(a.app               IS NOT DISTINCT FROM b.app              )::int +
		(a.subscription_type IS NOT DISTINCT FROM b.subscription_type)::int +
		(a.start_date        IS NOT DISTINCT FROM b.start_date       )::int +
		(a.end_date          IS NOT DISTINCT FROM b.end_date         )::int +
		(a.start_level_cefr  IS NOT DISTINCT FROM b.start_level_cefr )::int +
		(a.end_level_cefr    IS NOT DISTINCT FROM b.end_level_cefr   )::int
	) AS matching_columns_count,
	(
		((a.name              IS NULL) <> (b.name              IS NULL))::int +
		((a.age               IS NULL) <> (b.age               IS NULL))::int +
		((a.country           IS NULL) <> (b.country           IS NULL))::int +
		((a.native_language   IS NULL) <> (b.native_language   IS NULL))::int +
		((a.app               IS NULL) <> (b.app               IS NULL))::int +
		((a.subscription_type IS NULL) <> (b.subscription_type IS NULL))::int +
		((a.start_level_cefr  IS NULL) <> (b.start_level_cefr  IS NULL))::int +
		((a.end_level_cefr    IS NULL) <> (b.end_level_cefr    IS NULL))::int
	) AS one_sided_null_count
FROM one_row_per_user a
JOIN one_row_per_user b ON a.user_id < b.user_id
),

-- Extract the user_id to remove from each duplicate pair.
-- Tiebreaker: keep user_id_1, drop user_id_2.
duplicate_user_ids AS (
SELECT user_id_2 AS user_id_to_remove
FROM column_comparisons
WHERE (matching_columns_count = 10 AND one_sided_null_count = 0)
   OR (matching_columns_count = 9  AND one_sided_null_count = 1)
),

-- Remove all session rows belonging to duplicate user_ids from the full table.
deduplicated_users AS (
SELECT *
FROM coherent_timestamp
WHERE user_id NOT IN (SELECT user_id_to_remove FROM duplicate_user_ids)
),

-- Find USER_ID with multiple identical SESSION_TIMESTAMPs
rank_users_timestamps AS (
SELECT 
	*,
	CASE 
		WHEN session_timestamp IS NOT NULL 
		THEN ROW_NUMBER() OVER(PARTITION BY user_id, session_timestamp ORDER BY session_duration_mins DESC NULLS LAST)
		ELSE 1 
	END AS ranking
FROM deduplicated_users
),

-- Keep SESSION_TIMESTAMP with the highest SESSION_DURATION_MINS
deduplicated_session_timestamps AS ( 
SELECT *
FROM rank_users_timestamps
WHERE ranking = 1
),

-- Remove duplicate SESSION_ID and keep the one with the latest SESSION_TIMESTAMP
deduplicated_session_id AS ( 
SELECT DISTINCT ON(session_id)
	*
FROM deduplicated_session_timestamps
ORDER BY session_id, session_timestamp DESC NULLS LAST 
),

-- Convert levels to numbers for comparison and validation
convert_levels AS (
SELECT   
	*,
	CASE start_level   -- no need for mapping since it's only 6 values
		WHEN 'A1' THEN 1
		WHEN 'A2' THEN 2
		WHEN 'B1' THEN 3
		WHEN 'B2' THEN 4
		WHEN 'C1' THEN 5
		WHEN 'C2' THEN 6
		ELSE NULL
	END AS start_level_converted,
	CASE end_level
		WHEN 'A1' THEN 1
		WHEN 'A2' THEN 2
		WHEN 'B1' THEN 3
		WHEN 'B2' THEN 4
		WHEN 'C1' THEN 5
		WHEN 'C2' THEN 6
		ELSE NULL 
	END AS end_level_converted
FROM deduplicated_session_id
),

-- Validate start_level_converted < end_level_converted.
-- Create cefr and numeric columns.
coherent_levels AS (
SELECT 
	*,
	CASE 
		WHEN end_level_converted < start_level_converted THEN NULL 
		ELSE start_level
	END AS valid_start_level_cefr,
	CASE 
		WHEN end_level_converted < start_level_converted THEN NULL 
		ELSE end_level
	END AS valid_end_level_cefr,
	CASE 
		WHEN end_level_converted < start_level_converted THEN NULL
		ELSE start_level_converted
	END AS start_level_number,
	CASE 
		WHEN end_level_converted < start_level_converted THEN NULL
		ELSE end_level_converted
	END AS end_level_number
FROM convert_levels
)
SELECT 
	session_id,
	session_timestamp,
	user_id,
	name, 
	age,
	country,
	native_language,
	app,
	subscription_type,
	valid_start_date AS start_date,
	valid_end_date AS end_date,
	valid_start_level_cefr AS start_level_cefr,
	valid_end_level_cefr AS end_level_cefr,
	start_level_number,
	end_level_number,
	session_duration_mins
FROM coherent_levels;


SELECT *
FROM intermediate.clean_apps_data
ORDER BY session_id;
