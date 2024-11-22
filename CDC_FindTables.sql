-- Query to identify databases and tables with CDC enabled
SET NOCOUNT ON;

-- Temporary table to store the list of databases with CDC enabled
CREATE TABLE #DatabasesWithCDC (
    DatabaseID INT IDENTITY(1,1),
    DatabaseName NVARCHAR(255)
);

-- Populate the temporary table with CDC-enabled databases
INSERT INTO #DatabasesWithCDC (DatabaseName)
SELECT name 
FROM sys.databases 
WHERE is_cdc_enabled = 1;

-- Temporary table to store results
CREATE TABLE #CDCResults (
    DatabaseName NVARCHAR(255),
    TableName NVARCHAR(255),
    SchemaName NVARCHAR(255),
    CapturedColumnCount INT,
    ChangeTable NVARCHAR(255)
);

-- Variables for iteration
DECLARE @CurrentDatabaseID INT = 1;
DECLARE @MaxDatabaseID INT;
DECLARE @DatabaseName NVARCHAR(255);

-- Get the maximum database ID
SELECT @MaxDatabaseID = MAX(DatabaseID) FROM #DatabasesWithCDC;

-- Loop through each database
WHILE @CurrentDatabaseID <= @MaxDatabaseID
BEGIN
    -- Get the database name for the current ID
    SELECT @DatabaseName = DatabaseName 
    FROM #DatabasesWithCDC 
    WHERE DatabaseID = @CurrentDatabaseID;

    -- Dynamic SQL to query CDC-enabled tables in the current database
    DECLARE @SQL NVARCHAR(MAX) = N'
        INSERT INTO #CDCResults (DatabaseName, TableName, SchemaName, CapturedColumnCount, ChangeTable)
        SELECT 
            ''' + @DatabaseName + N''' AS DatabaseName,
            t.name AS TableName,
            s.name AS SchemaName,
            COUNT(cc.column_name) AS CapturedColumnCount,
            ct.name AS ChangeTable
        FROM [' + @DatabaseName + N'].sys.tables t
        JOIN [' + @DatabaseName + N'].sys.schemas s ON t.schema_id = s.schema_id
        JOIN [' + @DatabaseName + N'].cdc.change_tables ct ON t.object_id = ct.source_object_id
        LEFT JOIN [' + @DatabaseName + N'].cdc.captured_columns cc ON ct.object_id = cc.object_id
        GROUP BY t.name, s.name, ct.name
    ';
    EXEC sp_executesql @SQL;

    -- Increment the counter
    SET @CurrentDatabaseID = @CurrentDatabaseID + 1;
END;

-- Output the results
SELECT * FROM #CDCResults ORDER BY DatabaseName, SchemaName, TableName;

-- Cleanup
DROP TABLE #DatabasesWithCDC;
DROP TABLE #CDCResults;
