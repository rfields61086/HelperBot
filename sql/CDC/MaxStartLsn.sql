-- Step 1: Create a temporary table to store the results
CREATE TABLE #MaxLsnResults (
    CaptureInstanceName NVARCHAR(128),
    MaxStartLsn BINARY(10)
);

-- Step 2: Get a list of all capture instances from cdc.change_tables
DECLARE @captureInstanceTable TABLE (RowNum INT IDENTITY(1, 1), CaptureInstance NVARCHAR(128));
INSERT INTO @captureInstanceTable (CaptureInstance)
SELECT capture_instance
FROM cdc.change_tables;

-- Variables for iteration
DECLARE @rowCount INT, @currentRow INT = 1, @currentCaptureInstance NVARCHAR(128), @maxLsn BINARY(10);

-- Get the total number of capture instances
SELECT @rowCount = COUNT(*) FROM @captureInstanceTable;

-- Step 3: While loop to iterate through each capture instance
WHILE @currentRow <= @rowCount
BEGIN
    -- Get the current capture instance name
    SELECT @currentCaptureInstance = CaptureInstance
    FROM @captureInstanceTable
    WHERE RowNum = @currentRow;

    -- Execute the stored procedure to get the max LSN for the current capture instance
    EXEC dbo.GetMaxStartLsn 
        @captureInstanceName = @currentCaptureInstance,
        @maxStartLsn = @maxLsn OUTPUT;

    -- Insert the results into the temporary table
    INSERT INTO #MaxLsnResults (CaptureInstanceName, MaxStartLsn)
    VALUES (@currentCaptureInstance, @maxLsn);

    -- Move to the next row
    SET @currentRow = @currentRow + 1;
END;

-- Step 4: Select the results from the temporary table
SELECT * FROM #MaxLsnResults;

-- Clean up
DROP TABLE #MaxLsnResults;
