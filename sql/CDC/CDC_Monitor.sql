-- Retrieve CDC job failures from SQL Server Agent job history
SELECT 
    j.name AS JobName,
    h.run_status,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
    END AS RunStatusDescription,
    h.run_date AS RunDate,
    h.run_time AS RunTime,
    h.message AS ErrorMessage
FROM msdb.dbo.sysjobs AS j
INNER JOIN msdb.dbo.sysjobhistory AS h
    ON j.job_id = h.job_id
WHERE j.name LIKE 'cdc_%'
  AND h.run_status = 0 -- Only show failed jobs
ORDER BY h.run_date DESC, h.run_time DESC;
GO

-- Retrieve CDC log scan session errors
SELECT
    session_id AS SessionID,
    start_time AS StartTime,
    end_time AS EndTime,
    error_count AS ErrorCount,
    CASE
        WHEN error_count = 0 THEN 'No Error'
        ELSE 'Error Detected'
    END AS ErrorDescription,
    latency AS LatencyInSeconds,
    failed_sessions_count AS FailedSessionsCount
FROM sys.dm_cdc_log_scan_sessions
WHERE error_count > 0 -- Only show sessions with errors
ORDER BY start_time DESC;
GO


-- Retrieve CDC-specific errors from SQL Server Error Log
EXEC xp_readerrorlog 0, 1, N'cdc', NULL, NULL, NULL, N'desc';
GO


-- Retrieve CDC-enabled tables and their metadata
EXEC sys.sp_cdc_help_change_data_capture;


-- Retrieve information about CDC jobs
SELECT 
    sj.name AS JobName,
    cj.job_type AS JobType,
    cj.database_id AS DatabaseID,
    DB_NAME(cj.database_id) AS DatabaseName,
    sj.enabled AS IsEnabled,
    sj.date_created AS DateCreated,
    sj.date_modified AS DateModified,
    cj.maxtrans AS MaxTransactions,
    cj.maxscans AS MaxScans,
    cj.continuous AS IsContinuous,
    cj.pollinginterval AS PollingIntervalSeconds,
    cj.retention AS RetentionPeriodMinutes,
    cj.threshold AS Threshold
FROM msdb.dbo.cdc_jobs AS cj
INNER JOIN msdb.dbo.sysjobs AS sj
    ON cj.job_id = sj.job_id
ORDER BY cj.database_id, cj.job_type;
GO


-- Retrieve LSN ranges and commit times for CDC-enabled tables
SELECT
    ct.capture_instance AS CaptureInstance,
    ct.source_schema AS SchemaName,
    ct.source_name AS TableName,
    fn.cdc.fn_cdc_get_min_lsn(ct.capture_instance) AS MinLSN,
    fn.cdc.fn_cdc_get_max_lsn() AS MaxLSN,
    ltm.tran_begin_time AS MinLSNCommitTime,
    ltm.tran_end_time AS MaxLSNCommitTime
FROM
    cdc.change_tables AS ct
    CROSS APPLY (
        SELECT
            sys.fn_cdc_map_lsn_to_time(fn.cdc.fn_cdc_get_min_lsn(ct.capture_instance)) AS tran_begin_time,
            sys.fn_cdc_map_lsn_to_time(fn.cdc.fn_cdc_get_max_lsn()) AS tran_end_time
    ) AS ltm
ORDER BY
    ct.source_schema,
    ct.source_name;
GO



-- Monitor CDC latency and log usage
SELECT
    session_id AS SessionID,
    start_time AS StartTime,
    end_time AS EndTime,
    duration AS DurationSeconds,
    scan_phase AS ScanPhase,
    error_count AS ErrorCount,
    tran_count AS TransactionCount,
    last_commit_time AS LastCommitTime,
    latency AS LatencySeconds,
    log_record_count AS LogRecordCount,
    schema_change_count AS SchemaChangeCount,
    command_count AS CommandCount,
    empty_scan_count AS EmptyScanCount,
    failed_sessions_count AS FailedSessionsCount
FROM sys.dm_cdc_log_scan_sessions
ORDER BY start_time DESC;
GO

