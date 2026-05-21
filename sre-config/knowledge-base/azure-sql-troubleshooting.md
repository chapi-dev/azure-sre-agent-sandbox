# Azure SQL Troubleshooting Runbook

Diagnose and remediate **DTU saturation, blocking, deadlocks, and expensive queries** for the S0 demo database.

---

## Step 1: Classify the SQL Problem

| Signal | Likely Cause | Jump To |
|--------|--------------|---------|
| DTU or CPU near 100% | Resource saturation | Step 2 |
| Requests wait on another session | Blocking chain | Step 3 |
| Transactions fail or retry with deadlock errors | Deadlocks | Step 4 |
| Top queries dominate duration/CPU | Query regression | Step 5 |

---

## Step 2: Confirm DTU Saturation

**Symptoms:** writes time out, order or checkout paths slow down, SQL dependencies dominate App Insights duration.

**Diagnostic steps:**
1. Query Azure Monitor metrics:
   ```kql
   AzureMetrics
   | where TimeGenerated > ago(30m)
   | where ResourceProvider == 'MICROSOFT.SQL'
   | where MetricName in ('dtu_consumption_percent', 'cpu_percent', 'physical_data_read_percent', 'log_write_percent', 'workers_percent', 'sessions_percent')
   | summarize AvgValue = avg(Total), MaxValue = max(Maximum) by Resource, MetricName, bin(TimeGenerated, 5m)
   | order by MaxValue desc
   ```
2. Check recent database resource usage from the database itself:
   ```sql
   SELECT TOP (60)
       end_time,
       avg_cpu_percent,
       avg_data_io_percent,
       avg_log_write_percent,
       avg_memory_usage_percent,
       xtp_storage_percent,
       max_worker_percent,
       max_session_percent
   FROM sys.dm_db_resource_stats
   ORDER BY end_time DESC;
   ```
3. Correlate with App Insights SQL dependencies:
   ```kql
   dependencies
   | where timestamp > ago(30m)
   | where target contains '.database.windows.net'
   | summarize Calls = count(), Failures = countif(success == false), P95 = percentile(duration, 95) by cloud_RoleName, resultCode
   | order by Failures desc, P95 desc
   ```

**Remediation:**
- Stop the synthetic load generator or reduce parallel query count.
- Scale above S0 if the workload is legitimate.
- Tune the heaviest query before scaling if the pressure is caused by a single offender.

---

## Step 3: Find Blocking Queries

**Symptoms:** sessions pile up, requests wait a long time but CPU may be moderate.

**Diagnostic steps:**
1. Find active blockers:
   ```sql
   SELECT
       r.session_id,
       r.blocking_session_id,
       r.status,
       r.wait_type,
       r.wait_time,
       DB_NAME(r.database_id) AS database_name,
       SUBSTRING(
           t.text,
           (r.statement_start_offset / 2) + 1,
           ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE r.statement_end_offset END - r.statement_start_offset) / 2) + 1
       ) AS running_statement
   FROM sys.dm_exec_requests AS r
   CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
   WHERE r.session_id <> @@SPID
     AND (r.blocking_session_id <> 0 OR EXISTS (
         SELECT 1
         FROM sys.dm_exec_requests AS r2
         WHERE r2.blocking_session_id = r.session_id
     ))
   ORDER BY r.wait_time DESC;
   ```
2. Look for long-lived transactions in the application or a demo load script.
3. If blocking is widespread, compare it to DTU and log write saturation from Step 2.

**Remediation:**
- Kill the blocking test session if it is synthetic.
- Reduce transaction scope and duration.
- Add indexes to avoid scans that hold locks for too long.

---

## Step 4: Detect Deadlocks

**Symptoms:** requests fail fast with deadlock errors, retries may hide the root cause while latency grows.

**Diagnostic steps:**
1. Query the SQL event log:
   ```sql
   SELECT TOP (20)
       start_time,
       end_time,
       event_type,
       description
   FROM sys.event_log
   WHERE event_type = 'deadlock'
   ORDER BY start_time DESC;
   ```
2. Compare App Insights exception spikes to the same time window.
3. Check whether multiple code paths update rows in inconsistent order.

**Remediation:**
- Keep transactions short.
- Access shared tables in a consistent order.
- Add retries for deadlock victims, but still fix the underlying lock ordering problem.

---

## Step 5: Use Query Store to Find Regressions

**Symptoms:** one statement dominates CPU or duration, often after a deployment or workload change.

**Diagnostic steps:**
1. Query top statements by average duration:
   ```sql
   SELECT TOP (20)
       qsq.query_id,
       rs.avg_duration,
       rs.avg_cpu_time,
       rs.avg_logical_io_reads,
       qt.query_sql_text
   FROM sys.query_store_runtime_stats AS rs
   JOIN sys.query_store_plan AS qsp
     ON rs.plan_id = qsp.plan_id
   JOIN sys.query_store_query AS qsq
     ON qsp.query_id = qsq.query_id
   JOIN sys.query_store_query_text AS qt
     ON qsq.query_text_id = qt.query_text_id
   ORDER BY rs.avg_duration DESC;
   ```
2. Check whether the same query also appears in the blocking or DTU views.
3. Compare the query plan before and after the slowdown if Query Store history exists.

**Remediation:**
- Add or fix indexes.
- Reduce row counts scanned or returned.
- Force a known-good plan only after verifying the regression pattern.

---

## General Recovery

For the demo baseline, stop the query bomb processes, wait a few minutes for metrics to settle, and confirm DTU falls back below sustained saturation. If saturation is expected for the scenario, call it out as the bottleneck in the service map report.
