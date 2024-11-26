# Parameters
$serverName = "YourSqlServerName"
$databaseName = "YourDatabaseName"
$stagingTable = "StagingTableMetrics"
$batchSize = 1000  # Adjustable batch size

# Load dbatools module
Import-Module dbatools

# Function to execute a SQL query using Invoke-DbaQuery
function Execute-SQL {
    param (
        [string]$Query
    )
    Invoke-DbaQuery -SqlInstance $serverName -Database $databaseName -Query $Query
}

# Function to generate primary key column name
function Get-PrimaryKeyName {
    param (
        [string]$TableName
    )
    return "$TableName" + "Id"
}

# Function to get the table creation script using dbatools
function Get-TableScript {
    param (
        [string]$TableName
    )

    $tableDetails = Get-DbaTable -SqlInstance $serverName -Database $databaseName -Table $TableName
    return $tableDetails.Script
}

# Function to create a new table with a primary key
function Create-NewTable {
    param (
        [string]$OriginalTableName
    )
    $primaryKeyName = Get-PrimaryKeyName -TableName $OriginalTableName

    # Fetch the original table creation script
    $originalTableScript = Get-TableScript -TableName $OriginalTableName

    # Modify the script to create the new table and add a primary key
    $newTableName = "$OriginalTableName"_WithPK
    $newTableScript = $originalTableScript -replace "CREATE TABLE \[$OriginalTableName\]", "CREATE TABLE [$newTableName]"
    $newTableScript += @"
ALTER TABLE [$newTableName] ADD [$primaryKeyName] INT NOT NULL IDENTITY(1,1) PRIMARY KEY;
"@

    # Execute the new table creation script
    Execute-SQL -Query $newTableScript

    return @{
        NewTableName      = $newTableName
        NewTableScript    = $newTableScript
        OriginalTableScript = $originalTableScript
    }
}

# Function to bulk copy data
function Bulk-CopyData {
    param (
        [string]$SourceTable,
        [string]$DestinationTable
    )
    $startTime = Get-Date

    Copy-DbaDbTableData -SourceSqlInstance $serverName `
                        -DestinationSqlInstance $serverName `
                        -SourceDatabase $databaseName `
                        -DestinationDatabase $databaseName `
                        -SourceTable $SourceTable `
                        -DestinationTable $DestinationTable `
                        -BatchSize $batchSize `
                        -AutoCreateTable $false

    $endTime = Get-Date
    $rowCount = (Execute-SQL -Query "SELECT COUNT(*) AS RowCount FROM [$DestinationTable];").RowCount

    return @{
        RowCount = $rowCount
        TimeTaken = ($endTime - $startTime).TotalSeconds
    }
}

# Main Process
$tables = Execute-SQL -Query "SELECT DISTINCT TableName FROM $stagingTable;"

foreach ($table in $tables) {
    $tableName = $table.TableName
    Write-Host "Processing table: $tableName"

    # Create the new table with a primary key
    $tableMetrics = Create-NewTable -OriginalTableName $tableName

    # Bulk copy data from the original table to the new table
    $copyMetrics = Bulk-CopyData -SourceTable $tableName -DestinationTable $tableMetrics.NewTableName

    # Get the size of the original table
    $sizeQuery = "EXEC sp_spaceused '$tableName';"
    $tableSize = (Execute-SQL -Query $sizeQuery).Data[0].size

    # Insert metrics into the staging table
    $insertMetricsQuery = @"
        INSERT INTO $stagingTable (TableName, RowCount, SizeOnDiskMB, OriginalTableScript, NewTableScript, TimeToCopyRowsInSeconds)
        VALUES ('$tableName', $($copyMetrics.RowCount), $tableSize, N'$($tableMetrics.OriginalTableScript)', N'$($tableMetrics.NewTableScript)', $($copyMetrics.TimeTaken));
"@
    Execute-SQL -Query $insertMetricsQuery
}

Write-Host "Processing complete!"
