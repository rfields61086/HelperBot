-- Parameters
DECLARE @DatabaseName NVARCHAR(255) = 'YourDatabaseName'; -- Replace with your database name
DECLARE @FilegroupName NVARCHAR(255) = 'YourFilegroupName'; -- Replace with your filegroup name
DECLARE @RetentionMinutes INT = 4320; -- Set CDC retention period in minutes (default is 3 days)
DECLARE @TablesToEnable TABLE (
    TableID INT IDENTITY(1,1), -- Add an ID for iteration
    SchemaName NVARCHAR(255),
    TableName NVARCHAR(255)
);

-- Add tables to the list (SchemaName, TableName)
INSERT INTO @TablesToEnable (SchemaName, TableName)
VALUES 
    ('dbo', 'YourTable1'), 
    ('dbo', 'YourTable2'); -- Add more tables as needed

-- Enable CDC on the database
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @DatabaseName AND is_cdc_enabled = 1)
BEGIN
    DECLARE @EnableCdcDbSQL NVARCHAR(MAX);
    SET @EnableCdcDbSQL = N'USE [' + @DatabaseName + N']; EXEC sys.sp_cdc_enable_db;';
    EXEC sp_executesql @EnableCdcDbSQL;
    PRINT 'CDC has been enabled on the database: ' + @DatabaseName;
END
ELSE
    PRINT 'CDC is already enabled on the database: ' + @DatabaseName;

-- Temporary table to iterate through tables
DECLARE @CurrentTableID INT = 1;
DECLARE @MaxTableID INT;
DECLARE @SchemaName NVARCHAR(255);
DECLARE @TableName NVARCHAR(255);

-- Get the maximum TableID
SELECT @MaxTableID = MAX(TableID) FROM @TablesToEnable;

-- Iterate through each table
WHILE @CurrentTableID <= @MaxTableID
BEGIN
    -- Get the current table details
    SELECT @SchemaName = SchemaName, @TableName = TableName
    FROM @TablesToEnable
    WHERE TableID = @CurrentTableID;

    -- Enable CDC on the current table
    DECLARE @EnableCdcTableSQL NVARCHAR(MAX);
    SET @EnableCdcTableSQL = N'
        USE [' + @DatabaseName + N'];
        EXEC sys.sp_cdc_enable_table 
            @source_schema = N''' + @SchemaName + N''',
            @source_name = N''' + @TableName + N''',
            @role_name = NULL,
            @filegroup_name = N''' + @FilegroupName + N''';';
    EXEC sp_executesql @EnableCdcTableSQL;
    PRINT 'CDC enabled on table: ' + @SchemaName + '.' + @TableName;

    -- Increment the TableID
    SET @CurrentTableID = @CurrentTableID + 1;
END;

-- Update the CDC capture job to set the retention period
DECLARE @CaptureJobName NVARCHAR(255);

-- Get the capture job name for the database
SELECT @CaptureJobName = name 
FROM msdb.dbo.sysjobs
WHERE name LIKE '%cdc_' + @DatabaseName + '_capture%';

IF @CaptureJobName IS NOT NULL
BEGIN
    -- Use sp_cdc_change_job to update retention
    EXEC sys.sp_cdc_change_job 
        @job_type = N'capture',
        @retention = @RetentionMinutes;

    PRINT 'Retention period updated to ' + CAST(@RetentionMinutes AS NVARCHAR) + ' minutes for CDC capture job: ' + @CaptureJobName;
END
ELSE
    PRINT 'No capture job found for the database: ' + @DatabaseName;
