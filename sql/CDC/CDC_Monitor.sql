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
    capture_instance AS CaptureInstance,
    log_scan_start_time AS LogScanStartTime,
    log_scan_end_time AS LogScanEndTime,
    log_scan_error AS LogScanErrorCode,
    CASE 
        WHEN log_scan_error = 0 THEN 'No Error'
        ELSE 'Error Detected'
    END AS ErrorDescription,
    log_scan_error_message AS ErrorMessage
FROM sys.dm_cdc_log_scan_sessions
WHERE log_scan_error <> 0 -- Only show sessions with errors
ORDER BY log_scan_start_time DESC;
GO

-- Retrieve CDC-specific errors from SQL Server Error Log
EXEC xp_readerrorlog 0, 1, 'cdc'; -- Searches the current error log for 'cdc'
GO


-- Retrieve CDC-enabled tables and their metadata
SELECT 
    cdc.name AS CaptureInstance,
    s.name AS SchemaName,
    t.name AS TableName,
    cdc.create_date AS CDCEnableDate,
    cdc.supports_net_changes AS SupportsNetChanges,
    cdc.filegroup_name AS FileGroupName,
    cdc.capture_instance AS CDCInstance,
    cdc.source_object_id AS SourceObjectID,
    cdc.start_lsn AS StartLSN
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.sp_cdc_enabled_tables() AS cdc
    ON cdc.source_object_id = t.object_id
ORDER BY SchemaName, TableName;
GO

-- Retrieve information about CDC jobs
SELECT 
    job.name AS JobName,
    cdc.state_desc AS State,
    cdc.start_date AS JobStartDate,
    cdc.last_run_date AS LastRunDate,
    cdc.retention AS RetentionPeriodMinutes,
    cdc.latency AS LatencyInSeconds
FROM msdb.dbo.cdc_jobs AS cdc
INNER JOIN msdb.dbo.sysjobs AS job
    ON cdc.job_id = job.job_id;
GO

-- Monitor LSN ranges for CDC-enabled tables
SELECT 
    cdc.name AS CaptureInstance,
    lsn.start_lsn AS StartLSN,
    lsn.end_lsn AS EndLSN,
    lsn.capture_time AS CaptureTime
FROM sys.sp_cdc_enabled_tables() AS cdc
CROSS APPLY sys.fn_cdc_get_min_lsn(cdc.name) AS lsn
ORDER BY cdc.name, lsn.start_lsn;
GO

-- Monitor CDC latency and log usage
SELECT 
    capture_instance AS CaptureInstance,
    capture_time AS LastCaptureTime,
    latency AS CurrentLatencyInSeconds,
    filegroup_name AS CaptureFileGroup
FROM sys.dm_cdc_log_scan_sessions
WHERE capture_instance IS NOT NULL
ORDER BY capture_time DESC;
GO
