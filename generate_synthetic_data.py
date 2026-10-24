from faker import Faker
import pandas as pd
import random 
from datetime import datetime, time

fake = Faker('en_GB')

COUNTRIES = ['Italy', 'France', 'Brazil', 'Argentina', 'Morocco','Japan', 'Russia']

LANGUAGE = {
    'Italy': 'Italian',
    'France': 'French',
    'Brazil': 'Portuguese',
    'Argentina': 'Spanish',
    'Morocco': 'Arabic',
    'Japan': 'Japanese',
    'Russia': 'Russian'
}

APPS = ['Speedlang', 'Duolingo', 'Babble', 'Rosetta Stone', 'Englify']

SUBSCRIPTION_TYPE = ['Free', 'Premium']

CEFR = {
    1: 'A1',
    2: 'A2',
    3: 'B1',
    4: 'B2',
    5: 'C1',
    6: 'C2'
}

def inject_anomaly(data):
    #Purposely create and inject data anomalies
    num = random.random()
    
    if 0 < num <= 0.03: 
        data = None
    
    elif 0.1 < num <= 0.13:
        data = 'NULL'
    
    elif isinstance(data, str):
        if 0.2 < num <= 0.4:
            data = data.upper()
        elif 0.4 < num <= 0.6:
            data = f' {data.lower()} '
    
    else:
        if num >= 0.7:
            data = str(data)
    
    return data


def create_users():
    #Create list of users
    users = []
    
    for num in range(1,901):
        
        fake_name_original = fake.name()
        fake_name = inject_anomaly(fake_name_original)
        
        age_original = random.randint(14, 70)
        age = inject_anomaly(age_original)
        
        country_original = random.choice(COUNTRIES)
        native_language_original = LANGUAGE[country_original] 
        country = inject_anomaly(country_original)
        native_language = inject_anomaly(native_language_original)
        
        app_original = random.choice(APPS)
        app = inject_anomaly(app_original)  
        
        subscription_original = random.choice(SUBSCRIPTION_TYPE)
        subscription = inject_anomaly(subscription_original)
        
        start_date = fake.date_between(start_date='-3y', end_date='-2m')
        end_date = fake.date_between(start_date=start_date, end_date='-1m')
        
        cefr_number = random.randint(1, 5)
        start_level_original = CEFR[cefr_number]
        start_level = inject_anomaly(start_level_original)
        end_level_original = CEFR[random.randint(cefr_number, 6)]
        end_level = inject_anomaly(end_level_original)
        
        
        user = {
            'user_id': f'U{num:03d}',
            'name': fake_name,
            'age': age,
            'country': country,
            'native_language': native_language,
            'app': app,
            'subscription_type': subscription,
            'start_date': start_date,
            'end_date': end_date,
            'start_level': start_level,
            'end_level': end_level
        }
        
        users.append(user)
        
    return users
    
    
def create_sessions(users):
    #Create list of sessions/lessons
    sessions = []
    session_id = 0
    
    for user in users:
        number_of_sessions = random.randint(3, 11)
        
        original_start_date = user['start_date']
        original_end_date = user['end_date']
        
        user['start_date'] = inject_anomaly(user['start_date'].isoformat())
        user['end_date'] = inject_anomaly(user['end_date'].isoformat())
    
        for i in range(number_of_sessions):
            session_id += 1
            session_timestamp = fake.date_time_between(
                start_date=datetime.combine(original_start_date, time.min),
                end_date=datetime.combine(original_end_date, time.max)).isoformat()
            session_duration_original = random.randint(1, 120) 
            session_duration = inject_anomaly(session_duration_original)
                
            session = {
                'session_id': f'S{session_id:04d}',
                'session_timestamp': session_timestamp,
                **user,
                'session_duration_mins': session_duration
            }
            
            sessions.append(session)
    
    random.shuffle(sessions)
    return sessions


def main():
    users = create_users()
    sessions = create_sessions(users)
    df = pd.DataFrame(sessions)
    df.to_csv('raw_apps_data.csv', index=False)
        
if __name__ == '__main__':
    main()