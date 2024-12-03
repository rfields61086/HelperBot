-- Query sys.fn_trace_getinfo(0) with CASE statements for Property and Value
SELECT 
    TraceID,
    CASE 
        WHEN Property = 1 THEN 'Trace Options'
        WHEN Property = 2 THEN 'File Path'
        WHEN Property = 3 THEN 'Max File Size (MB)'
        WHEN Property = 4 THEN 'Stop Time'
        WHEN Property = 5 THEN 'Current File Number'
        ELSE 'Unknown Property'
    END AS PropertyDescription,
    Value,
    CASE 
        -- Interpretation for 'Trace Options'
        WHEN Property = 1 AND Value = 1 THEN 'Default (includes rollover and shutdown)'
        WHEN Property = 1 AND Value = 2 THEN 'Disable File Rollover'
        
        -- Interpretation for 'File Path'
        WHEN Property = 2 THEN CAST(Value AS NVARCHAR(MAX)) -- File path is stored as a string
        
        -- Interpretation for 'Max File Size (MB)'
        WHEN Property = 3 THEN CONCAT(Value, ' MB') -- Max file size in MB
        
        -- Interpretation for 'Stop Time'
        WHEN Property = 4 AND Value IS NULL THEN 'No Stop Time Set'
        WHEN Property = 4 THEN CAST(Value AS NVARCHAR(MAX)) -- Stop time if set
        
        -- Interpretation for 'Current File Number'
        WHEN Property = 5 THEN CONCAT('Current File Number: ', Value)

        ELSE 'Unknown Value'
    END AS ValueDescription
FROM sys.fn_trace_getinfo(0);
