import pandas as pd
from sqlalchemy import create_engine

data = pd.read_csv(r"C:\Users\thaib\Downloads\Python Practice\Customer Master.csv")

data['ingestion_timestamp'] = pd.Timestamp.now()

print(data.head())

DB_HOST = 'localhost'
DB_PORT = '5432'
DB_USER = 'postgres'
DB_PASSWORD = '123456'
DB_NAME = 'postgres'

try:
    engine = create_engine(f'postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}')
    print("engine created successfully")
except Exception as e:
    print(f"Error creating database engine: {e}")
    exit(1)

try:
    data.to_sql(
        name = "Raw_Customer",
        con = engine,
        schema = "bronze",
        if_exists = "append",
        index = False
)
    print("Data inserted successfully into the database.")
except Exception as e:
    print(f"Error inserting data into the database: {e}")
    exit(1)