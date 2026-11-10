# Data Engineering Journey

Hands-on learning log of my transition from **industrial automation** (PLC, SCADA) to **data engineering**.

In automation I worked daily with machine states, alarms and time-series sensor data. Here I am building the skills to engineer that kind of data at scale: SQL, Python and cloud data platforms (Azure, Databricks).

## Progress

| Week | Topic | Folder |
|------|-------|--------|
| 1 | SQL fundamentals | [week01_sql_fundamentals](week01_sql_fundamentals) |

## Week 1: SQL fundamentals

A synthetic dataset modelled on a small factory: 5 machines, hourly sensor readings, machine state changes and alarms over one production day.

The data intentionally contains real-world issues:

- duplicate sensor readings (at-least-once delivery)
- missing temperature values (sensor offline)
- an alarm that is still active

**Covered:** aggregations (`GROUP BY`, `HAVING`), `INNER` / `LEFT JOIN`, anti-joins, `NULL` handling, date and time arithmetic, window functions (`ROW_NUMBER`, `LAG`, `LEAD`), CTEs and deduplication.

### How to run

1. Create a PostgreSQL database.
2. Run `factory_dataset.sql` to create and load the tables.
3. Run queries from `solutions.sql`. Each task has a description, the expected result and notes on what I learned.

## Tools

PostgreSQL, pgAdmin

**Next up:** advanced SQL and data modelling, Git, Python, Docker, Azure and Databricks.
