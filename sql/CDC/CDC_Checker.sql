-- Declare parameter for the database name
DECLARE @DatabaseName NVARCHAR(255) = 'YourDatabaseName'; -- Replace with the target database or pass as a parameter
DECLARE @DatabaseId INT;

-- Verify the database exists
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @DatabaseName)
BEGIN
    PRINT 'Database does not exist.';
    RETURN;
END

-- Get the database ID for reference
SET @DatabaseId = DB_ID(@DatabaseName);

-- Store results of the checks
DECLARE @Results TABLE (
    CheckDescription NVARCHAR(255),
    FailureDetails NVARCHAR(MAX)
);

-- 1. Check if accelerated database recovery is turned off
IF EXISTS (
    SELECT 1
    FROM sys.databases
    WHERE database_id = @DatabaseId
      AND is_accelerated_database_recovery_on = 1
)
BEGIN
    INSERT INTO @Results (CheckDescription, FailureDetails)
    VALUES ('Accelerated Database Recovery', 'Accelerated Database Recovery is turned ON.');
END

-- 2. Check for existing CDC objects in the CDC schema, including the user
IF EXISTS (
    SELECT 1
    FROM sys.schemas s
    JOIN sys.database_principals p ON s.principal_id = p.principal_id
    WHERE s.name = 'cdc'
)
BEGIN
    INSERT INTO @Results (CheckDescription, FailureDetails)
    VALUES ('Existing CDC Schema Objects', 'CDC schema or user exists in the database.');
END

-- 3. Check for a filegroup ending in "_CDC"
IF NOT EXISTS (
    SELECT 1
    FROM sys.filegroups
    WHERE name LIKE '%_CDC'
)
BEGIN
    INSERT INTO @Results (CheckDescription, FailureDetails)
    VALUES ('Filegroup Naming', 'No filegroup with a name ending in "_CDC" exists.');
END

-- 4. Check for columns with collation different from database collation
DECLARE @DatabaseCollation NVARCHAR(128);
SELECT @DatabaseCollation = collation_name FROM sys.databases WHERE database_id = @DatabaseId;

INSERT INTO @Results (CheckDescription, FailureDetails)
SELECT 
    'Column Collation Check',
    CONCAT('Table: ', t.name, ', Column: ', c.name, ', Collation: ', c.collation_name)
FROM sys.tables t
JOIN sys.columns c ON t.object_id = c.object_id
WHERE t.is_ms_shipped = 0 -- Exclude system tables
  AND c.collation_name IS NOT NULL
  AND c.collation_name <> @DatabaseCollation;

-- 5. Check for tables without a primary key or unique index
INSERT INTO @Results (CheckDescription, FailureDetails)
SELECT 
    'Primary Key or Unique Index Check',
    CONCAT('Table: ', t.name, ' does not have a primary key or unique index.')
FROM sys.tables t
WHERE t.is_ms_shipped = 0 -- Exclude system tables
  AND NOT EXISTS (
      SELECT 1
      FROM sys.indexes i
      WHERE i.object_id = t.object_id
        AND (i.is_unique = 1 OR i.type = 1) -- Check for unique or primary key indexes
);

-- Output the results
IF EXISTS (SELECT 1 FROM @Results)
BEGIN
    PRINT 'Preliminary checks failed. Review the details below:';
    SELECT * FROM @Results;
END
ELSE
BEGIN
    PRINT 'All preliminary checks passed.';
END;
