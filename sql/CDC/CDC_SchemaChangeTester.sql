-- Step 1: Create a test database
CREATE DATABASE TestCDC;
GO

-- Use the test database
USE TestCDC;
GO

-- Step 2: Create a test table
CREATE TABLE TestTable (
    ID INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    Col1 NVARCHAR(50),
    Col2 INT,
    Col3 DATETIME DEFAULT GETDATE()
);
GO

-- Step 3: Enable CDC on the database and table
-- Enable CDC on the database
EXEC sys.sp_cdc_enable_db;
GO

-- Enable CDC on the table
EXEC sys.sp_cdc_enable_table 
    @source_schema = N'dbo',
    @source_name = N'TestTable',
    @role_name = NULL,
    @supports_net_changes = 1;
GO

-- Step 4: Generate a continuous DML script for random changes
-- Save this in a separate query session and run it concurrently
WHILE (1=1)
BEGIN
    DECLARE @Random INT = ABS(CHECKSUM(NEWID())) % 3;

    IF @Random = 0
        INSERT INTO TestTable (Col1, Col2) VALUES (NEWID(), RAND()*1000);
    ELSE IF @Random = 1
        UPDATE TestTable SET Col2 = Col2 + 1 WHERE ID = (SELECT TOP 1 ID FROM TestTable ORDER BY NEWID());
    ELSE IF @Random = 2
        DELETE FROM TestTable WHERE ID = (SELECT TOP 1 ID FROM TestTable ORDER BY NEWID());

    WAITFOR DELAY '00:00:03'; -- 3 second delay
END;

-- Step 5: Add a column to the table and enable a 2nd capture instance in one transaction
BEGIN TRANSACTION;
    -- Add a new column
    ALTER TABLE TestTable ADD Col4 NVARCHAR(100);

    -- Enable a second capture instance
    EXEC sys.sp_cdc_enable_table 
        @source_schema = N'dbo',
        @source_name = N'TestTable',
        @role_name = NULL,
        @supports_net_changes = 1,
        @capture_instance = 'TestTable_2';
COMMIT TRANSACTION;
GO

-- Declare the range of LSNs for the first capture instance
DECLARE @from_lsn BINARY(10) = sys.fn_cdc_get_min_lsn('dbo_TestTable');
DECLARE @to_lsn BINARY(10) = sys.fn_cdc_get_max_lsn();

-- Step 6.1: Get rows that exist in both capture instances and store them in a temporary table
-- Replace with the actual column names for the capture instance
SELECT 
    __$start_lsn,
    __$end_lsn,
    __$seqval,
    __$operation,
    __$update_mask,
    ID,
    Col1,
    Col2,
    Col3,
    Col4 -- Include all relevant columns
INTO #ExistingRows
FROM cdc.fn_cdc_get_all_changes_dbo_TestTable(@from_lsn, @to_lsn, 'all')
INTERSECT
SELECT 
    __$start_lsn,
    __$end_lsn,
    __$seqval,
    __$operation,
    __$update_mask,
    ID,
    Col1,
    Col2,
    Col3,
    Col4 -- Ensure the columns match between both capture instances
FROM cdc.fn_cdc_get_all_changes_dbo_TestTable_2(@from_lsn, @to_lsn, 'all');

-- Step 6.2: Insert rows from the 1st capture instance into the 2nd, excluding rows that already exist
INSERT INTO cdc.dbo_TestTable_2_CT -- Replace with the actual target table for the 2nd capture instance
(__$start_lsn, __$end_lsn, __$seqval, __$operation, __$update_mask, ID, Col1, Col2, Col3, Col4) -- List all columns
SELECT 
    __$start_lsn,
    __$end_lsn,
    __$seqval,
    __$operation,
    __$update_mask,
    ID,
    Col1,
    Col2,
    Col3,
    Col4 -- Add all relevant columns
FROM cdc.fn_cdc_get_all_changes_dbo_TestTable(@from_lsn, @to_lsn, 'all')
EXCEPT
SELECT 
    __$start_lsn,
    __$end_lsn,
    __$seqval,
    __$operation,
    __$update_mask,
    ID,
    Col1,
    Col2,
    Col3,
    NULL -- NULL For The New Column.
FROM #ExistingRows;

-- Step 6.3: Clean up the temporary table
DROP TABLE #ExistingRows;
GO

-- Step 7: Create a copy of the test table with the new column
CREATE TABLE TestTable_Copy (
    ID INT PRIMARY KEY,
    Col1 NVARCHAR(50),
    Col2 INT,
    Col3 DATETIME,
    Col4 NVARCHAR(100)
);
GO

-- Step 8: Consume Change Data Into Table
-- Declare the range of LSNs for the second capture instance
DECLARE @from_lsn BINARY(10) = sys.fn_cdc_get_min_lsn('dbo_TestTable_2');
DECLARE @to_lsn BINARY(10) = sys.fn_cdc_get_max_lsn();

-- Temporary table to hold change data
IF OBJECT_ID('tempdb..#CDC_Changes') IS NOT NULL
    DROP TABLE #CDC_Changes;

SELECT 
    __$operation,
    __$start_lsn,
    __$command_id,
    ID,
    Col1,
    Col2,
    Col3,
    Col4
INTO #CDC_Changes
FROM cdc.fn_cdc_get_all_changes_dbo_TestTable_2(@from_lsn, @to_lsn, 'all');

-- Initialize variables for batch processing
DECLARE @BatchSize INT = 1000; -- Number of rows to process at a time
DECLARE @RowCount INT = 1; -- To track the number of rows left to process

-- WHILE loop to process data in batches
WHILE @RowCount > 0
BEGIN
    -- Process a batch of rows
    WITH CTE_Batch AS (
        SELECT TOP (@BatchSize) *
        FROM #CDC_Changes
        ORDER BY __$start_lsn, __$command_id -- Process changes in correct sequence
    )
    SELECT @RowCount = COUNT(*) FROM CTE_Batch;

    -- INSERT or UPDATE (NEW) operations
    MERGE INTO TestTable_Copy AS Target
    USING CTE_Batch AS Source
    ON Target.ID = Source.ID
    WHEN MATCHED AND Source.__$operation = 4 THEN -- Update (New Values)
        UPDATE SET
            Col1 = Source.Col1,
            Col2 = Source.Col2,
            Col3 = Source.Col3,
            Col4 = Source.Col4
    WHEN NOT MATCHED AND Source.__$operation IN (2, 4) THEN -- Insert or Update (New Values)
        INSERT (ID, Col1, Col2, Col3, Col4)
        VALUES (Source.ID, Source.Col1, Source.Col2, Source.Col3, Source.Col4);

    -- Handle DELETE operations (True Deletes Only)
    DELETE FROM TestTable_Copy
    WHERE ID IN (
        SELECT ID
        FROM CTE_Batch AS Deletes
        WHERE __$operation = 1 -- True Delete
          AND NOT EXISTS (
              SELECT 1 
              FROM CTE_Batch AS Updates
              WHERE Updates.ID = Deletes.ID 
                AND Updates.__$operation IN (3, 4) -- Ignore part of an UPDATE sequence
          )
    );

    -- Remove processed rows from the temporary table
    DELETE FROM #CDC_Changes
    WHERE __$start_lsn IN (SELECT __$start_lsn FROM CTE_Batch);
END;

-- Clean up the temporary table
DROP TABLE #CDC_Changes;
GO

-- Step 9: Compare the test table and consumer copy
-- Compare rows in TestTable that are not in TestTable_Copy
SELECT ID, Col1, Col2, Col3, Col4
FROM TestTable
EXCEPT
SELECT ID, Col1, Col2, Col3, Col4
FROM TestTable_Copy;

-- Compare rows in TestTable_Copy that are not in TestTable
SELECT ID, Col1, Col2, Col3, Col4
FROM TestTable_Copy
EXCEPT
SELECT ID, Col1, Col2, Col3, Col4
FROM TestTable;

