CREATE TABLE StagingTableMetrics (
    TableName NVARCHAR(128) NOT NULL,
    RowCount INT NOT NULL,
    SizeOnDiskMB DECIMAL(18, 2) NOT NULL,
    OriginalTableScript NVARCHAR(MAX),
    NewTableScript NVARCHAR(MAX),
    TimeToCopyRowsInSeconds DECIMAL(18, 2),
    ReportDate DATETIME DEFAULT GETDATE()
);
