DROP TABLE IF EXISTS analytics.fact_session;
DROP TABLE IF EXISTS analytics.dim_users;

-- Although USER_ID and SESSION_ID are unique and non-NULL, 
-- surrogate integer keys are used to follow dimensional modelling best practices
-- and they can reduce key storage and join costs.


-- Create DIM_USERS TABLE 
CREATE TABLE analytics.dim_users (
	user_key INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	user_id TEXT NOT NULL UNIQUE,
	name TEXT, 
	age INT2, 
	country TEXT,
	native_language TEXT, 
	app TEXT, 
	subscription_type TEXT, 
	start_date DATE, 
	end_date DATE,
	start_level_cefr TEXT,
	end_level_cefr TEXT, 
	start_level_number INT2, 
	end_level_number INT2
);


INSERT INTO analytics.dim_users (user_id, name, age, country, native_language, app, subscription_type, 
								start_date, end_date, start_level_cefr, end_level_cefr, start_level_number, end_level_number)
SELECT DISTINCT user_id, name, age, country, native_language, app, subscription_type, 
	start_date, end_date, start_level_cefr, end_level_cefr, start_level_number, end_level_number
FROM intermediate.clean_apps_data
ORDER BY user_id;


SELECT *
FROM analytics.dim_users
ORDER BY user_key;


-- Create FACT_SESSION TABLE
CREATE TABLE analytics.fact_session (
	session_key INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	session_id TEXT NOT NULL UNIQUE,
	session_timestamp TIMESTAMP, 
	user_key INT NOT NULL 
		REFERENCES analytics.dim_users(user_key),   
	session_duration_mins INT2
); 


INSERT INTO analytics.fact_session (session_id, session_timestamp, user_key, session_duration_mins)
SELECT session_id, session_timestamp, user_key, session_duration_mins
FROM intermediate.clean_apps_data cad
JOIN analytics.dim_users du 
	ON cad.user_id = du.user_id
ORDER BY session_id;


SELECT *
FROM analytics.fact_session;

SELECT *
FROM analytics.dim_users
ORDER BY user_key;