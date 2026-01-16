from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2026, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    'crypto_live_monitoring',
    default_args=default_args,
    description='Pobieranie cen BTC co 5 minut',
    schedule_interval='* * * * *',
    catchup=False
) as dag:

    # To zadanie mówi Airflow: "Wejdź do kontenera i odpal skrypt Pythona"
    run_spark_script = BashOperator(
        task_id='fetch_btc_price_task',
        bash_command='python3 /opt/airflow/scripts/fetch_crypto_live.py'
    )
