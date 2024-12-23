CREATE PROCEDURE dbo.GetMaxStartLsn
(
    @captureInstanceName NVARCHAR(128),
    @maxStartLsn BINARY(10) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @changeTableName NVARCHAR(128);
    DECLARE @sql NVARCHAR(MAX);

    -- Get the name of the change table for the provided capture instance
    SELECT @changeTableName = CONCAT('cdc.', capture_instance + '_CT')
    FROM cdc.change_tables
    WHERE capture_instance = @captureInstanceName;

    -- If the capture instance doesn't exist, set the output to NULL
    IF @changeTableName IS NULL
    BEGIN
        SET @maxStartLsn = NULL;
        RETURN;
    END;

    -- Construct dynamic SQL to get the MAX(__$start_lsn) from the change table
    SET @sql = 'SELECT @result = MAX(__$start_lsn) FROM ' + @changeTableName;

    -- Execute the dynamic SQL and capture the result
    EXEC sp_executesql @sql, N'@result BINARY(10) OUTPUT', @result = @maxStartLsn OUTPUT;
END;
GO
