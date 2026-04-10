# CryptoPulse — Dokumentacja Projektu

> Ostatnia aktualizacja: 2026-04-09

---

## 1. Co to jest CryptoPulse?

CryptoPulse to system monitorowania rynku kryptowalut w czasie rzeczywistym. Co minutę pobiera aktualną cenę Bitcoina z publicznego API (CoinGecko), zapisuje dane do bazy PostgreSQL, a wyniki wizualizuje w Grafanie. Całość działa w kontenerach Docker.

**Trzy warstwy systemu:**

| Warstwa | Technologia | Rola |
|---|---|---|
| Orkiestracja | Apache Airflow | Harmonogramowanie i uruchamianie pipeline'u |
| Przetwarzanie | Python + PySpark | Pobieranie danych z API i zapis do bazy |
| Przechowywanie | PostgreSQL 15 | Baza danych z cenami BTC |
| Wizualizacja | Grafana | Dashboardy i wykresy w czasie rzeczywistym |

---

## 2. Jak uruchomić projekt

### Wymagania
- Docker Desktop zainstalowany i uruchomiony
- Port 5434, 8081, 3000 wolne na hoście

### Uruchomienie

```bash
# Z katalogu projektu
cd c:\Projects\CryptoPulse

# Uruchomienie wszystkich serwisów w tle
docker-compose up -d

# Sprawdzenie stanu kontenerów
docker ps

# Zatrzymanie
docker-compose down
```

### Sprawdzenie czy wszystko działa

```bash
docker ps
```

Powinieneś widzieć trzy kontenery:
- `postgres_crypto` — status `healthy`
- `airflow_crypto` — status `running`
- `grafana_crypto` — status `running`

---

## 3. Adresy i dane dostępowe

| Serwis | URL / Adres | Login | Hasło |
|---|---|---|---|
| Airflow (Web UI) | http://localhost:8081 | admin | admin |
| Grafana (Web UI) | http://localhost:3000 | admin | admin |
| PostgreSQL (zewnętrzny port) | localhost:5434 | admin | password123 |

---

## 4. Baza danych PostgreSQL

### Jak się połączyć

**Opcja A — przez Docker (z terminala, bez instalowania klienta):**
```bash
docker exec -it postgres_crypto psql -U admin -d crypto_db
```

**Opcja B — z hosta (jeśli masz zainstalowane psql lub DBeaver):**
```
Host:     localhost
Port:     5434
Database: crypto_db
User:     admin
Password: password123
```

**Opcja C — connection string (np. do DBeaver / DataGrip):**
```
postgresql://admin:password123@localhost:5434/crypto_db
```

### Struktura bazy

Baza: `crypto_db`

#### Tabela: `f_btc_realtime`

Główna tabela faktów — każdy rekord to jeden odczyt ceny BTC.

| Kolumna | Typ | Opis |
|---|---|---|
| `ticker` | VARCHAR | Symbol krypto, zawsze "BTC" |
| `price_usd` | FLOAT | Aktualna cena w USD |
| `volume_24h` | FLOAT | Wolumen obrotu z ostatnich 24h |
| `pct_change_24h` | FLOAT | Zmiana procentowa ceny w ciągu 24h |
| `fetch_timestamp` | TIMESTAMP | Czas pobrania danych (UTC) |

> Tabela jest tworzona automatycznie przez Spark przy pierwszym zapisie (tryb `append`). Brak klucza głównego — rekordy tylko się dokładają.

### Przydatne zapytania SQL

```sql
-- Ostatnie 10 rekordów
SELECT * FROM f_btc_realtime
ORDER BY fetch_timestamp DESC
LIMIT 10;

-- Aktualna cena (ostatni odczyt)
SELECT price_usd, fetch_timestamp
FROM f_btc_realtime
ORDER BY fetch_timestamp DESC
LIMIT 1;

-- Średnia cena z ostatniej godziny
SELECT AVG(price_usd) AS avg_price
FROM f_btc_realtime
WHERE fetch_timestamp > NOW() - INTERVAL '1 hour';

-- Min/Max cena z dzisiaj
SELECT
    MIN(price_usd) AS min_price,
    MAX(price_usd) AS max_price,
    COUNT(*) AS records_today
FROM f_btc_realtime
WHERE fetch_timestamp::date = CURRENT_DATE;

-- Ile rekordów mamy w bazie?
SELECT COUNT(*) FROM f_btc_realtime;

-- Dane z ostatnich 24 godzin pogrupowane co godzinę
SELECT
    DATE_TRUNC('hour', fetch_timestamp) AS hour,
    AVG(price_usd) AS avg_price,
    MAX(price_usd) AS max_price,
    MIN(price_usd) AS min_price
FROM f_btc_realtime
WHERE fetch_timestamp > NOW() - INTERVAL '24 hours'
GROUP BY 1
ORDER BY 1;
```

---

## 5. Apache Airflow

### Dostęp

- **URL:** http://localhost:8081
- **Login:** admin / admin

### Jak poruszać się po Airflow

1. Po zalogowaniu widzisz listę DAGów → znajdź `crypto_live_monitoring`
2. Kliknij w nazwę DAGa → widzisz graf zadań
3. Zakładka **Graph** — wizualizacja przepływu
4. Zakładka **Grid** — historia uruchomień (zielony = sukces, czerwony = błąd)
5. Kliknij w konkretny run → kliknij w zadanie → **Logs** — zobaczysz output skryptu

### DAG: `crypto_live_monitoring`

**Plik:** `dags/crypto_dag.py`

| Parametr | Wartość |
|---|---|
| Harmonogram | Co minutę (`* * * * *`) |
| Start date | 2026-01-01 |
| Catchup | Wyłączony (nie uruchamia starych run'ów) |
| Retries | 1 (czeka 5 minut przed ponowną próbą) |

**Zadania w DAGu:**

```
fetch_btc_price_task
  └── Uruchamia: python3 /opt/airflow/scripts/fetch_crypto_live.py
```

Tylko jedno zadanie — uruchamia skrypt Python, który pobiera dane i zapisuje do bazy.

### Ręczne uruchomienie DAGa

W UI: przycisk **▶ Trigger DAG** (prawy górny róg widoku DAGa)

Lub z terminala:
```bash
docker exec -it airflow_crypto airflow dags trigger crypto_live_monitoring
```

### Logi Airflow

Logi są zapisywane lokalnie w katalogu projektu:
```
logs/
  dag_id=crypto_live_monitoring/
    run_id=.../
      task_id=fetch_btc_price_task/
        attempt=1.log
```

Lub przez UI: Grid → wybierz run → kliknij zadanie → Logs

### Zatrzymanie/wstrzymanie DAGa

W UI: przełącznik przy nazwie DAGa (niebieski = aktywny, szary = wstrzymany)

---

## 6. Grafana

### Dostęp

- **URL:** http://localhost:3000
- **Login:** admin / admin

### Konfiguracja źródła danych (jednorazowa)

Jeśli Grafana nie jest jeszcze podłączona do bazy:

1. Lewy pasek → **Connections** → **Data Sources**
2. **Add new data source** → wybierz **PostgreSQL**
3. Wypełnij:
   - **Host:** `postgres_crypto:5432`
   - **Database:** `crypto_db`
   - **User:** `admin`
   - **Password:** `password123`
   - **SSL Mode:** `disable`
4. Kliknij **Save & Test** — powinno pojawić się "Database Connection OK"

### Tworzenie dashboardu

1. Lewy pasek → **Dashboards** → **New Dashboard**
2. **Add visualization**
3. Wybierz data source: PostgreSQL
4. W edytorze zapytań wklej SQL (przykłady poniżej)

### Przykładowe zapytania do paneli Grafany

**Panel: Cena BTC w czasie (Time Series)**
```sql
SELECT
    fetch_timestamp AS time,
    price_usd AS "Cena BTC (USD)"
FROM f_btc_realtime
WHERE fetch_timestamp BETWEEN $__timeFrom() AND $__timeTo()
ORDER BY fetch_timestamp ASC;
```

**Panel: Aktualna cena (Stat)**
```sql
SELECT
    fetch_timestamp AS time,
    price_usd AS "Aktualna cena"
FROM f_btc_realtime
ORDER BY fetch_timestamp DESC
LIMIT 1;
```

**Panel: Zmiana 24h % (Gauge)**
```sql
SELECT
    fetch_timestamp AS time,
    pct_change_24h AS "Zmiana 24h (%)"
FROM f_btc_realtime
ORDER BY fetch_timestamp DESC
LIMIT 1;
```

**Panel: Wolumen 24h (Bar Chart)**
```sql
SELECT
    DATE_TRUNC('hour', fetch_timestamp) AS time,
    AVG(volume_24h) AS "Wolumen 24h"
FROM f_btc_realtime
WHERE fetch_timestamp BETWEEN $__timeFrom() AND $__timeTo()
GROUP BY 1
ORDER BY 1;
```

### Wskazówki Grafana

- Ustaw **Time range** (prawy górny róg) na "Last 1 hour" lub "Last 24 hours"
- **Auto-refresh:** kliknij ikonę zegara obok time range → ustaw np. `10s` dla odświeżania live
- Typ wykresu zmień klikając nazwę panelu → Edit → po prawej stronie wybór visualization type
- `$__timeFrom()` i `$__timeTo()` to wbudowane zmienne Grafany — automatycznie filtrują dane do wybranego zakresu czasu

---

## 7. Przepływ danych (ETL)

```
CoinGecko API
     │
     │  GET /api/v3/coins/markets?vs_currency=usd&ids=bitcoin
     ▼
fetch_crypto_live.py (Python + PySpark)
     │
     │  Ekstrakcja: ticker, price_usd, volume_24h, pct_change_24h, fetch_timestamp
     ▼
PostgreSQL: tabela f_btc_realtime (APPEND)
     │
     ▼
Grafana: zapytania SQL → wykresy
```

**Harmonogram:** Airflow odpala skrypt co minutę → ~1440 rekordów dziennie

---

## 8. Struktura plików projektu

```
CryptoPulse/
├── docker-compose.yaml          # Definicja serwisów Docker
├── Dockerfile                   # Obraz Airflow z Javą (wymagana dla Spark)
├── requirements.txt             # Zależności Pythona
├── README.md                    # Skrócona dokumentacja
├── DOKUMENTACJA.md              # Ten plik
│
├── dags/
│   └── crypto_dag.py            # Definicja DAGa Airflow
│
├── scripts/
│   ├── fetch_crypto_live.py     # Główny skrypt ETL (pobieranie + zapis do bazy)
│   ├── info.txt                 # Komendy pomocnicze do łączenia z bazą
│   └── postgresql-42.7.3.jar   # Sterownik JDBC (Spark → PostgreSQL)
│
└── logs/                        # Logi Airflow (auto-generowane)
    └── dag_id=crypto_live_monitoring/
        └── ...
```

---

## 9. Zależności Python

**Plik:** `requirements.txt`

| Pakiet | Wersja | Zastosowanie |
|---|---|---|
| apache-airflow | 2.7.1 | Orkiestracja pipeline'u |
| pyspark | 3.4.1 | Przetwarzanie danych i zapis przez JDBC |
| requests | latest | HTTP client do API CoinGecko |
| pandas | latest | Manipulacja danymi |

---

## 10. Rozwiązywanie problemów

### Kontenery nie startują

```bash
# Sprawdź logi konkretnego kontenera
docker logs postgres_crypto
docker logs airflow_crypto
docker logs grafana_crypto
```

### Baza danych nie odpowiada

```bash
# Sprawdź czy kontener jest healthy
docker inspect postgres_crypto | grep -A 5 '"Health"'

# Restart kontenera
docker restart postgres_crypto
```

### DAG nie uruchamia się

1. Sprawdź czy DAG jest aktywny (niebieski przełącznik w UI)
2. Sprawdź logi w UI: Grid → ostatni run → task → Logs
3. Sprawdź logi airflow: `docker logs airflow_crypto`

### Grafana nie widzi danych

1. Sprawdź datasource: Connections → Data Sources → PostgreSQL → Save & Test
2. Sprawdź czy zapytanie SQL jest poprawne w Query Editor
3. Upewnij się że Time Range w Grafanie obejmuje czas kiedy dane były zbierane

### Tabela nie istnieje w bazie

Tabela `f_btc_realtime` jest tworzona automatycznie przy pierwszym uruchomieniu skryptu. Jeśli DAG uruchomił się przynajmniej raz z sukcesem, tabela powinna istnieć.

```bash
# Sprawdź czy tabela istnieje
docker exec -it postgres_crypto psql -U admin -d crypto_db -c "\dt"
```

---

## 11. Notatki techniczne

- **Strefa czasowa:** UTC (wszystkie timestampy w bazie są w UTC)
- **Brak retencji danych:** Rekordy tylko się dodają, brak mechanizmu czyszczenia starych danych
- **API CoinGecko:** Publiczne API, bez klucza, limit ~30 req/min (bezpieczne przy 1 req/min)
- **PySpark jako klient JDBC:** Spark jest używany nie do przetwarzania dużych danych, ale jako wygodny klient JDBC do PostgreSQL
- **Airflow standalone mode:** Prostsza konfiguracja (bez osobnego schedulera/webservera), wystarczająca dla małych projektów
