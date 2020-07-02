<#
.DESCRIPTION
    Backup Postgres databases with pg_dump and write Windows event log appropriately.
.PARAMETER databases
    Specify postgres databases as comma separated values.
.PARAMETER retention
    Specify retention of backups in days.
    Default value is 14 days.
.PARAMETER postgresUser
    Specify postgres user with permissions to backup databases.
    Default value is postgres.
.PARAMETER postgresHost
    Specify postgres host address.
    Default value is localhost.
.PARAMETER postgresPort
    Specify postgres port.
    Default value is postgres' default (5432)
.PARAMETER eventSource
    Specify Windows Event Log source name.
    Default value is Postgres Backup.
.EXAMPLE
    .\Backup-WindowsPostgres.ps1 -databases "postgres", "db1", "db2"
    .\Backup-WindowsPostgres.ps1 -databases "postgres", "db1", "db2" -retention 15 -postgresUser "postgresbackup" -postgresHost "localhost" -postgresPort "5433" -eventSource "BackupJob - Postgres Backup"
.NOTES
    Version:        0.2
    Last updated:   06/30/2020
    Creation date:  06/29/2020
    Author:         Zachary Choate
    URL:            https://raw.githubusercontent.com/KSMC-TS/backup-windowspostgres/main/backup-windowspostgres.ps1
#>

[CmdletBinding(PositionalBinding=$false)]

param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
    [string[]]$databases=@(),
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [int]$retention = 14,
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$postgresUser = "postgres",
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$postgresHost = "localhost",
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [int]$postgresPort = 5432,
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$eventSource = "Postgres Backup"
)

# Check that Event Log source exists and create if it doesn't.
If(![System.Diagnostics.EventLog]::SourceExists($eventSource)) {

    New-EventLog -LogName Application -Source $eventSource

    }

Function Backup-Postgres {
    param(
        [string]$database,
        [int]$retention,
        [string]$postgresUser,
        [string]$postgresHost,
        [int]$postgresPort,
        [string]$eventSource
    )

    $argumentList = "--file `"$database\\$database-$(get-date -format yyyyMMdd-HHmm).tar`" --host `"$postgresHost`" --port `"$postgresPort`" --username `"$postgresUser`" --verbose --format=t --blobs `"$database`""

    # Check for backup directory and create if it doesn't exist.
    If(!(Test-Path .\$database)) {

        $backupPath = New-Item -ItemType Directory .\$database
        Write-EventLog -LogName Application -Source $eventSource -EventId 2 -EntryType Information -Message "Created backup directory for $database at $($backupPath.FullName)."

        }

    # Start the backup.
    Try {

        Start-Process "$env:ProgramFiles\pgAdmin 4\v4\runtime\pg_dump.exe" -ArgumentList $argumentList -Wait -PassThru -NoNewWindow
        Write-EventLog -LogName Application -Source $eventSource -EventId 1 -EntryType Information -Message "Daily Postgres backup for $database was successful."

        } catch {
        
            Write-EventLog -LogName Application -Source $eventSource -EventId 3 -EntryType Error -Message "Daily Postgres backup for $database appears to have failed. Please investigate further. $_"

        }

    # Clean up old backups
    $agedBackups = Get-ChildItem -path .\$database | Where-Object {$_.LastAccessTime -lt (Get-Date).AddDays(-($retention))}
    $totalBackupCount = (Get-ChildItem -Path .\$database).Count
    If($totalBackupCount -ge $($agedBackups.Count) + 2) {
        
            ForEach($item in $agedBackups) {
                
                Remove-Item -Path $item.FullName

            }

    }

}

ForEach($database in $databases) {

    Backup-Postgres -database $database -retention $retention -postgresUser $postgresUser -postgresHost $postgresHost -postgresPort $postgresPort -eventSource $eventSource

    }
