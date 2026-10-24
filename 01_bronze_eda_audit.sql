DROP VIEW IF EXISTS staging.start_end_date_validation;

CREATE DATABASE "LanguageApps";

-- BRONZE layer
CREATE SCHEMA "staging";
-- SILVER layer
CREATE SCHEMA "intermediate";
-- GOLD layer 
CREATE SCHEMA "analytics";

SELECT *
FROM staging.raw_apps_data
ORDER BY session_id;


-- Check type of NULL/invalid values

SELECT DISTINCT country
FROM staging.raw_apps_data
ORDER BY country;


SELECT DISTINCT app
FROM staging.raw_apps_data
ORDER BY app;


SELECT DISTINCT native_language
FROM staging.raw_apps_data
ORDER BY native_language;


-- Count NULL/invalid values in relevant columns

SELECT 
	COUNT(*) AS total_rows,
	COUNT(*) FILTER (WHERE session_id IS NULL OR session_id = 'NULL') AS missing_session_id,
	COUNT(*) FILTER (WHERE session_timestamp IS NULL OR session_timestamp = 'NULL') AS missing_session_timestamp,
	COUNT(*) FILTER (WHERE user_id IS NULL OR user_id = 'NULL') AS missing_user_id,
	COUNT(*) FILTER (WHERE age IS NULL OR age = 'NULL') AS missing_age,
	COUNT(*) FILTER (WHERE country IS NULL OR country = 'NULL') AS missing_country,
	COUNT(*) FILTER (WHERE native_language IS NULL OR native_language = 'NULL') AS missing_native_language,
	COUNT(*) FILTER (WHERE app IS NULL OR app = 'NULL') AS missing_app,
	COUNT(*) FILTER (WHERE subscription_type IS NULL OR subscription_type = 'NULL') AS missing_subscription_type,
	COUNT(*) FILTER (WHERE start_date IS NULL OR start_date = 'NULL') AS missing_start_date,
	COUNT(*) FILTER (WHERE end_date IS NULL OR end_date = 'NULL') AS missing_end_date,
	COUNT(*) FILTER (WHERE start_level IS NULL OR start_level = 'NULL') AS missing_start_level,
	COUNT(*) FILTER (WHERE end_level IS NULL OR end_level = 'NULL') AS missing_end_level,
	COUNT(*) FILTER (WHERE session_duration_mins IS NULL OR session_duration_mins = 'NULL') AS missing_session_duration_mins
FROM staging.raw_apps_data;


-- CONSISTENCY: session_id - focusing on FORMAT rather than whitespace/casing
SELECT 
	session_id,
	COUNT(*) OVER() AS total_incorrect
FROM staging.raw_apps_data 
WHERE TRIM(session_id) !~ '^S[0-9]{4}$';


-- CONSISTENCY: session_timestamp - focusing on FORMAT
SELECT 
	session_timestamp,
	COUNT(*) OVER() AS total_incorrect
FROM staging.raw_apps_data 
WHERE TRIM(session_timestamp) !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$';


-- CONSISTENCY: user_id - focusing on FORMAT
SELECT 
	user_id,
	COUNT(*) OVER() AS total_incorrect
FROM staging.raw_apps_data
WHERE TRIM(user_id) !~ '^U[0-9]{3}$';


-- SAMPLE CONSTISTENCY: to be applied to 'name', 'country', 'native_language', 'app', 'subscription_type'
--1.EXPLICIT 
SELECT 
	name,
	CASE 
		WHEN name <> TRIM(name) AND name <> INITCAP(name) THEN 'Whitespace and casing'
		WHEN name <> TRIM(name) THEN 'Whitespace'
		ELSE 'Casing'
	END AS issue,
	COUNT(*) AS group_count,
	SUM(COUNT(*)) OVER() AS total_incorrect
FROM staging.raw_apps_data
WHERE name <> TRIM(name) OR name <> INITCAP(name)
GROUP BY name
ORDER BY name;

--2. PARAMETER: insert 'name', 'country', 'native_language', 'app', 'subscription_type'
SELECT 
	$1,
	CASE 
		WHEN $1 <> TRIM($1) AND $1 <> INITCAP($1) THEN 'Whitespace and casing'
		WHEN $1 <> TRIM($1) THEN 'Whitespace'
		ELSE 'Casing'
	END AS issue, 
	COUNT(*) AS group_count,
	SUM(COUNT(*)) OVER() AS total_incorrect
FROM staging.raw_apps_data
WHERE $1 <> TRIM($1) OR $1 <> INITCAP($1)
GROUP BY $1
ORDER BY $1;


-- CONSISTENCY and COMFORMITY : age should be between 14 and 70
SELECT  
	age, 
	CASE 
		WHEN NOT pg_input_is_valid(TRIM(age), 'integer') THEN 'Non-numeric'
		WHEN TRIM(age)::INTEGER NOT BETWEEN 14 AND 70 THEN 'Out of bounds'
		ELSE 'Whitespace'
	END AS issue,
	COUNT(*) AS group_count, 
	SUM(COUNT(*)) OVER() AS total_incorrect
FROM staging.raw_apps_data 
WHERE NOT pg_input_is_valid(TRIM(age), 'integer') 
	OR (TRIM(age)::INTEGER NOT BETWEEN 14 AND 70) 
	OR TRIM(age) <> age
GROUP BY age
ORDER BY age;


-- CONSISTENCY: to be applied to 'start_date' and 'end_date' - focusing on FORMAT
SELECT 
	start_date,
	SUM(COUNT(*)) OVER() AS total_incorrect
FROM staging.raw_apps_data 
WHERE TRIM(start_date) !~ '^\d{4}-\d{2}-\d{2}$' AND start_date <> 'NULL'
GROUP BY start_date 
ORDER BY start_date;


-- CONSISTENCY: to be applied to 'start_level' and 'end_level' - focusing on FORMAT
SELECT start_level,	
	CASE 
		WHEN TRIM(start_level) ~* '^[ABC][12]$' THEN 'Casing'
		ELSE 'Wrong format'
	END AS issue,
	COUNT(*) AS group_count, 
	SUM(COUNT(*)) OVER() AS total_incorrect
FROM staging.raw_apps_data
WHERE TRIM(start_level) !~ '^[ABC][12]$' AND start_level <> 'NULL'
GROUP BY start_level
ORDER BY start_level;


-- CONSISTENCY and COMFORMITY : session_duration_mins should be between 1 and 120
SELECT  
	session_duration_mins, 
	CASE 
		WHEN NOT pg_input_is_valid(TRIM(session_duration_mins), 'integer') THEN 'Non-numeric'
		WHEN TRIM(session_duration_mins)::INTEGER NOT BETWEEN 1 AND 120 THEN 'Out of bounds'
		ELSE 'Whitespace'
	END AS issue,
	COUNT(*) AS group_count, 
	SUM(COUNT(*)) OVER() AS total_incorrect
FROM staging.raw_apps_data 
WHERE NOT pg_input_is_valid(TRIM(session_duration_mins), 'integer') 
	OR (TRIM(session_duration_mins)::INTEGER NOT BETWEEN 1 AND 120) 
	OR TRIM(session_duration_mins) <> session_duration_mins
GROUP BY session_duration_mins
ORDER BY session_duration_mins;


-- DUPLICATE session_id: simple check as the synthetic data for this field purposely does not contain duplicates
SELECT 
	TRIM(UPPER(session_id)) AS session_id_t,
	COUNT(*) total_count
FROM staging.raw_apps_data
GROUP BY TRIM(UPPER(session_id))
HAVING COUNT(*) > 1
ORDER BY session_id_t;


-- DUPLICATE user_id: more advanced check even though user_id is purposely unique
WITH user_names AS (
	SELECT 
		DISTINCT TRIM(UPPER(user_id)) AS user_id_t,
		TRIM(INITCAP(name)) AS name_t 
	FROM staging.raw_apps_data
),
total_occurrencies AS ( 
	SELECT 
		user_id_t,   
		name_t, 
		COUNT(*) OVER(PARTITION BY user_id_t) AS distinct_name_per_user_id
	FROM user_names
)
SELECT  
	user_id_t, 
	name_t,
	distinct_name_per_user_id AS total_names_per_user_id
FROM total_occurrencies 
WHERE distinct_name_per_user_id > 1
ORDER BY user_id_t;


-- CORRECTNESS/COHERENCE: start/end_date 
-- VIEW to check valid start/end_date, reusable for session_timestamp validation
CREATE VIEW staging.start_end_date_validation AS 
WITH convert_date AS (
SELECT    
	session_id,
	session_timestamp,
	user_id,
	start_date, 
	end_date,
	CASE 
		WHEN TRIM(start_date) !~ '^\d{4}-\d{2}-\d{2}$' THEN NULL
		WHEN pg_input_is_valid(TRIM(start_date), 'date') THEN TRIM(start_date)::DATE
		ELSE NULL
	END start_date_clean,
	CASE 
		WHEN TRIM(end_date) !~ '^\d{4}-\d{2}-\d{2}$' THEN NULL
		WHEN pg_input_is_valid(TRIM(end_date), 'date') THEN TRIM(end_date)::DATE 
		ELSE NULL
	END end_date_clean
FROM staging.raw_apps_data
),
date_validation AS (
SELECT 
	*,
	CASE
		WHEN start_date_clean IS NULL AND end_date_clean IS NULL THEN 'Both dates missing'
		WHEN start_date_clean IS NULL OR end_date_clean IS NULL THEN 'One date missing'
		WHEN end_date_clean >= start_date_clean THEN 'Valid'
		ELSE 'Invalid'
	END AS valid_dates
FROM convert_date
)
SELECT 
	*,
	COUNT(*) OVER(PARTITION BY valid_dates) total_per_start_end_date_validity
FROM date_validation
;

SELECT *
FROM staging.start_end_date_validation;


-- COHERENCE: session_timestamp between start_date_clean and end_date_clean
WITH timestamp_to_date AS (
SELECT 
	session_id, 
	user_id,
	start_date_clean, 
	end_date_clean,
	valid_dates,
	CASE 
		WHEN pg_input_is_valid(TRIM(session_timestamp), 'timestamp') THEN TRIM(session_timestamp)::TIMESTAMP::DATE 
		ELSE NULL
	END session_timestamp_converted
FROM staging.start_end_date_validation
),
validity_check AS (
SELECT 
	*, 
	CASE 
		WHEN session_timestamp_converted IS NULL THEN 'Missing session_timestamp'
		WHEN start_date_clean IS NULL OR end_date_clean IS NULL THEN 'Missing bounds'
		WHEN session_timestamp_converted BETWEEN start_date_clean AND end_date_clean THEN 'Valid'
		ELSE 'Out of bounds'
	END AS valid_session_timestamp
FROM timestamp_to_date
)
SELECT  
	*,
	COUNT(*) OVER(PARTITION BY valid_session_timestamp) AS total_per_timestamp_validity
FROM validity_check
ORDER BY total_per_timestamp_validity
;

-- Further checks were carried out and automatically applied in transformation.sql to avoid a very verbose eda_audit.sql 



