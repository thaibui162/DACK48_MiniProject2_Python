import pandas as pd
from sqlalchemy import create_engine
import os
from dotenv import load_dotenv

data = pd.read_csv(r"C:\Users\thaib\Desktop\UNIGAP\PYTHON\Final Project\Customer Master.csv")
data['ingestion_timestamp'] = pd.Timestamp.now()

load_dotenv()

DB_HOST = os.getenv('DB_HOST')
DB_PORT = os.getenv('DB_PORT')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')
DB_NAME = os.getenv('DB_NAME')

print(data.head())

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