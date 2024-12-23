CREATE FUNCTION dbo.GetMaxStartLsn
(
    @captureInstanceName NVARCHAR(128)
)
RETURNS BINARY(10)
AS
BEGIN
    DECLARE @changeTableName NVARCHAR(128)
    DECLARE @sql NVARCHAR(MAX)
    DECLARE @result BINARY(10)

    -- Get the name of the change table for the provided capture instance
    SELECT @changeTableName = CONCAT('cdc.', capture_instance + '_CT')
    FROM cdc.change_tables
    WHERE capture_instance = @captureInstanceName

    -- If the capture instance doesn't exist, return NULL
    IF @changeTableName IS NULL
    BEGIN
        RETURN NULL
    END

    -- Construct dynamic SQL to get the MAX(__$start_lsn) from the change table
    SET @sql = 'SELECT @result = MAX(__$start_lsn) FROM ' + @changeTableName

    -- Execute the dynamic SQL
    EXEC sp_executesql @sql, N'@result BINARY(10) OUTPUT', @result OUTPUT

    RETURN @result
END
GO
