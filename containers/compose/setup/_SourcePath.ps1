param(
    [Parameter(Mandatory=$True)]
    $WebsiteRootPath,
    [Parameter(Mandatory=$True)]
    $ScVariableName,
    [Parameter(Mandatory=$False)]
    $SrcSourceFolderPath
)

# Logic (should be the same across different _SourcePath.ps1 files in the solution)
# TODO: extract this to ps module
$SourceFolderConfigPath = "$WebsiteRootPath\App_Config\Include\zzz\zzz.$ScVariableName.config"

# create source folder config file for unicorn and other integrations
$SourceFolderConfigDir = [System.IO.Path]::GetDirectoryName($SourceFolderConfigPath)
if (-not (Test-Path ($SourceFolderConfigDir))) {
    Write-Host "Creating folder: $SourceFolderConfigDir"
    
    MKDIR $SourceFolderConfigDir | Out-Null
}

if ([string]::IsNullOrWhiteSpace($SrcSourceFolderPath)) {
    $SrcSourceFolderPath = [System.IO.Path]::GetDirectoryName((Get-Location).Path)
}

Write-Host "Creating $SourceFolderConfigPath file that defines $ScVariableName as `"$SrcSourceFolderPath`""
"<!-- The purpose of this file is to define sourceFolder variable pointing to current src folder in project git repo -->`
<configuration>`
    <sitecore>`
        <sc.variable name=`"$ScVariableName`" value=`"$SrcSourceFolderPath`"/>`
    </sitecore>`
</configuration>" | Out-File "$SourceFolderConfigPath"
