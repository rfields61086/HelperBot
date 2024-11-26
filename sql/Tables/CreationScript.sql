DECLARE @TableName NVARCHAR(128) = 'YourTableName';
DECLARE @TableScript NVARCHAR(MAX) = '';

-- Columns
WITH TableColumns AS (
    SELECT 
        c.name AS ColumnName,
        t.name AS DataType,
        CASE 
            WHEN t.name IN ('varchar', 'nvarchar') THEN 
                CASE WHEN c.max_length = -1 THEN 'MAX'
                     ELSE CAST(c.max_length / CASE t.name WHEN 'nvarchar' THEN 2 ELSE 1 END AS NVARCHAR)
                END
            WHEN t.name IN ('decimal', 'numeric') THEN 
                CAST(c.precision AS NVARCHAR) + ',' + CAST(c.scale AS NVARCHAR)
            ELSE NULL
        END AS DataTypeLength,
        c.is_nullable AS IsNullable,
        dc.definition AS DefaultConstraint
    FROM sys.columns c
    INNER JOIN sys.tables tb ON c.object_id = tb.object_id
    INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
    LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
    WHERE tb.name = @TableName
)
SELECT @TableScript = @TableScript + 
    '    ' + QUOTENAME(ColumnName) + ' ' + DataType +
    ISNULL('(' + DataTypeLength + ')', '') +
    CASE WHEN IsNullable = 0 THEN ' NOT NULL' ELSE ' NULL' END +
    ISNULL(' DEFAULT ' + DefaultConstraint, '') + ',' + CHAR(13)
FROM TableColumns;

-- Constraints (Primary Key, Unique, Foreign Key)
WITH TableConstraints AS (
    SELECT 
        i.name AS ConstraintName,
        i.type_desc AS ConstraintType,
        c.name AS ColumnName
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    INNER JOIN sys.tables tb ON i.object_id = tb.object_id
    WHERE tb.name = @TableName
)
SELECT @TableScript = @TableScript +
    CASE 
        WHEN ConstraintType = 'CLUSTERED' OR ConstraintType = 'NONCLUSTERED' THEN 
            '    CONSTRAINT ' + QUOTENAME(ConstraintName) + ' ' + ConstraintType + ' INDEX (' + STRING_AGG(QUOTENAME(ColumnName), ', ') WITHIN GROUP (ORDER BY ColumnName) + '),' + CHAR(13)
        WHEN ConstraintType = 'PRIMARY_KEY' THEN 
            '    PRIMARY KEY (' + STRING_AGG(QUOTENAME(ColumnName), ', ') WITHIN GROUP (ORDER BY ColumnName) + '),' + CHAR(13)
        WHEN ConstraintType = 'UNIQUE' THEN 
            '    CONSTRAINT ' + QUOTENAME(ConstraintName) + ' UNIQUE (' + STRING_AGG(QUOTENAME(ColumnName), ', ') WITHIN GROUP (ORDER BY ColumnName) + '),' + CHAR(13)
    END
FROM TableConstraints;

-- Remove trailing comma and add closing parenthesis
SET @TableScript = 'CREATE TABLE ' + QUOTENAME(@TableName) + '(' + CHAR(13) +
                   LEFT(@TableScript, LEN(@TableScript) - 2) + CHAR(13) + ');';

-- Add indexes
WITH TableIndexes AS (
    SELECT 
        i.name AS IndexName,
        i.type_desc AS IndexType,
        STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS Columns
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    INNER JOIN sys.tables tb ON i.object_id = tb.object_id
    WHERE tb.name = @TableName AND i.is_primary_key = 0 AND i.is_unique_constraint = 0
    GROUP BY i.name, i.type_desc
)
SELECT @TableScript = @TableScript + CHAR(13) + 
    'CREATE ' + IndexType + ' INDEX ' + QUOTENAME(IndexName) + ' ON ' + QUOTENAME(@TableName) +
    ' (' + Columns + ');'
FROM TableIndexes;

PRINT @TableScript;
