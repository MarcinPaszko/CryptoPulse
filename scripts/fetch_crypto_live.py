import requests
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from datetime import datetime

def run_ingest():
    spark = SparkSession.builder \
        .appName("CryptoPulse_Ingest") \
        .config("spark.jars", "/opt/airflow/scripts/postgresql-42.7.3.jar") \
        .getOrCreate()

    url = "https://api.coingecko.com/api/v3/coins/markets"
    params = {
        "vs_currency": "usd",
        "ids": "bitcoin",
        "order": "market_cap_desc",
        "sparkline": "false"
    }
    
    try:
        response = requests.get(url, params=params)
        data = response.json()[0]

        
        row = [{
            "ticker": "BTC",
            "price_usd": float(data['current_price']),
            "volume_24h": float(data['total_volume']),
            "pct_change_24h": float(data['price_change_percentage_24h']),
            "fetch_timestamp": datetime.now() 
        }]
        
        sdf = spark.createDataFrame(row)

        
        db_conf = {
            "url": "jdbc:postgresql://postgres_crypto:5432/crypto_db",
            "user": "admin",
            "password": "password123",
            "driver": "org.postgresql.Driver"
        }

        sdf.write.format("jdbc") \
            .options(**db_conf) \
            .option("dbtable", "f_btc_realtime") \
            .mode("append") \
            .save()
        
        print(f"[{datetime.now()}] Sucess: BTC @ {data['current_price']} USD")

    except Exception as e:
        print(f"Error while ingestation: {e}")
    finally:
        spark.stop()

if __name__ == "__main__":
    run_ingest()