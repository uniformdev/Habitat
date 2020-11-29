[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript( { Test-Path $_ -PathType 'Container' })]
    [string]$InstallPath,
    [Parameter(Mandatory = $true)]
    [ValidateScript( { Test-Path $_ -PathType 'Container' })]
    [string]$DataPath
)

$timeFormat = "HH:mm:ss:fff"

$noDatabases = $null -eq (Get-ChildItem -Path $DataPath -Filter "*.mdf")

if ($noDatabases)
{
    Write-Host "$(Get-Date -Format $timeFormat): Sitecore databases not found in '$DataPath', seeding clean databases..."

    Get-ChildItem -Path $InstallPath | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $DataPath
    }
}
else
{
    Write-Host "$(Get-Date -Format $timeFormat): Existing Sitecore databases found in '$DataPath'..."
}

$webPath = Join-path $DataPath "Sitecore.Web.mdf"
$webLdfPath = Join-path $DataPath "Sitecore.Web.ldf"
$masterPath = Join-path $DataPath "Sitecore.Master.mdf"
$masterLdfPath = Join-path $DataPath "Sitecore.Master.ldf"

if (-not (Test-Path $webPath)) {
    Write-Warning "$(Get-Date -Format $timeFormat): Sitecore.Web database not found in '$DataPath', copying Sitecore.Master..."
    
    Copy-Item $masterPath $webPath    
    if (Test-Path $masterLdfPath)
    {
        Copy-Item $masterLdfPath $webLdfPath
    } else {        
        $masterLdfPath = Join-path $DataPath "Sitecore.Master_ldf.ldf"
        if (Test-Path $masterLdfPath)
        {
            Copy-Item $masterLdfPath $webLdfPath
        }
    }
}

Get-ChildItem -Path $DataPath -Filter "*.mdf" | ForEach-Object {
    $databaseName = $_.BaseName.Replace("_Primary", "")
    $mdfPath = $_.FullName
    $ldfPath = $mdfPath.Replace(".mdf", ".ldf")
    if (Test-Path $ldfPath) {
        $sqlcmd = "IF EXISTS (SELECT 1 FROM SYS.DATABASES WHERE NAME = '$databaseName') BEGIN EXEC sp_detach_db [$databaseName] END;CREATE DATABASE [$databaseName] ON (FILENAME = N'$mdfPath'), (FILENAME = N'$ldfPath') FOR ATTACH;"
    } else {
        $ldfPath = $ldfPath.Replace(".ldf", "_log.ldf")
        if (Test-Path $ldfPath) {
            $sqlcmd = "IF EXISTS (SELECT 1 FROM SYS.DATABASES WHERE NAME = '$databaseName') BEGIN EXEC sp_detach_db [$databaseName] END;CREATE DATABASE [$databaseName] ON (FILENAME = N'$mdfPath'), (FILENAME = N'$ldfPath') FOR ATTACH;"
        } else {
            $sqlcmd = "IF EXISTS (SELECT 1 FROM SYS.DATABASES WHERE NAME = '$databaseName') BEGIN EXEC sp_detach_db [$databaseName] END;CREATE DATABASE [$databaseName] ON (FILENAME = N'$mdfPath') FOR ATTACH;"
        }
    }

    Write-Host "$(Get-Date -Format $timeFormat): Attaching '$databaseName'..."

    Invoke-Sqlcmd -Query $sqlcmd
}

Write-Host "$(Get-Date -Format $timeFormat): Sitecore databases ready!"

& C:\Start.ps1 -sa_password $env:sa_password -ACCEPT_EULA $env:ACCEPT_EULA -attach_dbs \"$env:attach_dbs\" -Verbose
